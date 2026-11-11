#!/usr/bin/env bash
#
# upload_to_source_coop.sh — copy PacIOOS model NetCDF files, unchanged, to Source Cooperative.
#
# Run this ON THE MACHINE THAT HOLDS THE FILES. It reads each file once, at low disk priority,
# and uploads it with rclone. It writes nothing on this machine. The only things it writes are
# on Source Cooperative.
#
#   ./upload_to_source_coop.sh --dry-run roms_hiig      # show what would be uploaded
#   ./upload_to_source_coop.sh roms_hiig wrf_hi         # upload two products
#   ./upload_to_source_coop.sh roms_hiig_assim=/some/folder   # a product not listed below
#
# For every file it:
#   1. skips it if it is already on Source Cooperative (same size, with its .md5 file;
#      a file changed later without changing size is NOT noticed, as model output isn't edited),
#   2. skips it if it was modified in the last MIN_AGE_MINUTES (it may still be being written),
#   3. computes its MD5 checksum,
#   4. uploads it,
#   5. checks the uploaded size, then uploads "<file>.md5" next to it. A .md5 file therefore
#      means "this upload finished". Anyone can check a file with `md5sum -c <file>.md5`.
#
# So the script can be stopped at any time and run again: it carries on where it left off.
# One line per file is printed: OK, SKIP or FAIL. Save it if you want a record, e.g.
#   ./upload_to_source_coop.sh roms_hiig 2>&1 | tee -a upload.log
#
# ---------------------------------------------------------------------------------------------
# What you need
#
#   rclone   https://rclone.org/downloads/ (a single program file; no install or root needed).
#            Put it on your PATH, or set RCLONE=/path/to/rclone.
#
#   Source Cooperative upload keys, in one of two ways:
#     a) Keys in the environment, which last about 12 hours:
#          eval "$(source-coop creds --format env)"
#     b) An AWS profile that fetches fresh keys by itself, which is better for long runs:
#          ~/.aws/config:
#            [profile source-coop]
#            credential_process = source-coop creds
#          export AWS_PROFILE=source-coop
#        `source-coop` is the Source Cooperative CLI:
#        https://github.com/source-cooperative/source-coop-cli
#
#   With (a), the keys may run out partway through a long upload. Then uploads start to FAIL.
#   Get fresh keys and run the script again; finished files are skipped.
#   MAX_HOURS stops the script cleanly before that happens.
#
# Settings (environment variables, all optional)
#
#   PARALLEL=2          files uploaded at the same time
#   MAX_HOURS=0         stop starting new files after this many hours (0 = no limit)
#   MIN_AGE_MINUTES=120 leave files younger than this alone
#   DEST=ocean-icechunks/pacioos   where on Source Cooperative ("account/product")
#   RCLONE=rclone       the rclone program to use
# ---------------------------------------------------------------------------------------------

set -euo pipefail

# Which folder each product comes from. The folder layout under it, e.g. 2026/<file>.nc,
# is kept as it is on Source Cooperative: DEST/<product>/2026/<file>.nc
declare -A SOURCE_DIR=(
  [roms_hiig]=/export/data/model/ocn/roms_forecast/hiig     # ROMS ocean forecast, Main Hawaiian Islands
  [wrf_hi]=/export/data/model/atm/wrf_hi                    # WRF atmosphere, Main Hawaiian Islands
  [ww3_hawaii]=/export/data/model/ore/ww3/hawaii            # WaveWatch III waves, Hawaiʻi
)

PARALLEL=${PARALLEL:-2}
MAX_HOURS=${MAX_HOURS:-0}
MIN_AGE_MINUTES=${MIN_AGE_MINUTES:-120}
DEST=${DEST:-ocean-icechunks/pacioos}
RCLONE=${RCLONE:-rclone}

usage() { sed -n '3,12p' "$0" 2>/dev/null || true; echo "Products: ${!SOURCE_DIR[*]}"; exit 1; }

DRY_RUN=0
PRODUCTS=()
for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage ;;
    *=*) SOURCE_DIR[${arg%%=*}]=${arg#*=}; PRODUCTS+=("${arg%%=*}") ;;
    *) [[ -n ${SOURCE_DIR[$arg]:-} ]] || { echo "Unknown product: $arg (known: ${!SOURCE_DIR[*]})"; exit 1; }
       PRODUCTS+=("$arg") ;;
  esac
done
[[ ${#PRODUCTS[@]} -gt 0 ]] || usage

# --- rclone settings for Source Cooperative ------------------------------------------------
# Given as environment variables, so no rclone config file is needed or written.
# Each of the last lines works around how Source Cooperative's service behaves
# (found by testing, Nov 2026):
export RCLONE_CONFIG=/dev/null
export RCLONE_CONFIG_SC_TYPE=s3
export RCLONE_CONFIG_SC_PROVIDER=Other
export RCLONE_CONFIG_SC_ENV_AUTH=true                   # keys from the environment or AWS_PROFILE
export RCLONE_CONFIG_SC_ENDPOINT=https://data.source.coop
export RCLONE_CONFIG_SC_REGION=us-east-1
export RCLONE_CONFIG_SC_FORCE_PATH_STYLE=true
export RCLONE_CONFIG_SC_SIGN_ACCEPT_ENCODING=false      # else: "SignatureDoesNotMatch"
export RCLONE_CONFIG_SC_LIST_VERSION=2                  # else: listings say "directory not found"
export RCLONE_CONFIG_SC_NO_CHECK_BUCKET=true            # else: "Missing object key"
export RCLONE_CONFIG_SC_UPLOAD_CUTOFF=0                 # send EVERY file in pieces (multipart):
export RCLONE_STREAMING_UPLOAD_CUTOFF=0                 #   one-piece uploads fail ("headers ... not
                                                        #   signed"), and requests over ~100 MB are
export RCLONE_CONFIG_SC_CHUNK_SIZE=64M                  #   refused, so pieces are 64 MB
export RCLONE_CONFIG_SC_UPLOAD_CONCURRENCY=4

command -v "$RCLONE" >/dev/null || { echo "rclone not found (set RCLONE=/path/to/rclone)"; exit 1; }
if [[ -z ${AWS_ACCESS_KEY_ID:-} && -z ${AWS_PROFILE:-} ]]; then
  echo "No Source Cooperative keys found. See 'What you need' at the top of this script."; exit 1
fi

# Programs that read big files run at the lowest CPU and disk priority, so the server's own
# work comes first.
low() { if command -v ionice >/dev/null; then nice -n 19 ionice -c3 "$@"; else nice -n 19 "$@"; fi; }

STOP_AT=0
[[ $MAX_HOURS != 0 ]] && STOP_AT=$(( $(date +%s) + $(awk -v h="$MAX_HOURS" 'BEGIN { print int(h * 3600) }') ))

# Upload one file. Arguments: product, path relative to the product's folder.
upload_one() {
  local product=$1 rel=$2
  local src="${SOURCE_DIR_OF_PRODUCT}/$rel" dst="sc:$DEST/$product/$rel" name=${rel##*/}
  if (( STOP_AT > 0 && $(date +%s) >= STOP_AT )); then
    echo "SKIP  $product/$rel  (MAX_HOURS reached; run again to continue)"; return 0
  fi
  local size t0 t1 t2 md5 got
  size=$(stat -c %s "$src"); t0=$(date +%s)
  md5=$(low md5sum "$src" | cut -d' ' -f1); t1=$(date +%s)
  # The file was just read for the checksum, so this upload mostly reads it from memory.
  if ! low "$RCLONE" copyto "$src" "$dst" --s3-disable-checksum --retries 3 -q; then
    echo "FAIL  $product/$rel  (upload failed)"; return 0
  fi
  got=$("$RCLONE" lsf --format s "$dst" 2>/dev/null || true)
  if [[ $got != "$size" ]]; then
    echo "FAIL  $product/$rel  (size on Source Cooperative is '${got}', expected $size)"; return 0
  fi
  if ! printf '%s  %s\n' "$md5" "$name" | "$RCLONE" rcat "$dst.md5" -q; then
    echo "FAIL  $product/$rel  (could not upload .md5 file)"; return 0
  fi
  t2=$(date +%s)
  echo "OK    $product/$rel  size=$size  md5=$md5  checksum=$((t1-t0))s  upload=$((t2-t1))s" \
       "($(( size / 1000000 / (t2 - t1 > 0 ? t2 - t1 : 1) )) MB/s)"
}
export -f upload_one low
export RCLONE DEST STOP_AT

echo "Started $(date '+%F %T %Z') on $(hostname) — products: ${PRODUCTS[*]} — parallel: $PARALLEL" \
     "— dry run: $DRY_RUN"

ok_n=0; fail_n=0; skip_n=0
for product in "${PRODUCTS[@]}"; do
  dir=${SOURCE_DIR[$product]}
  [[ -d $dir ]] || { echo "Folder not found for $product: $dir"; exit 1; }

  # What is already finished on Source Cooperative: NetCDF sizes, and which .md5 files exist.
  declare -A remote_size=() has_md5=()
  while IFS=';' read -r path rsize; do
    if [[ $path == *.md5 ]]; then has_md5[${path%.md5}]=1; else remote_size[$path]=$rsize; fi
  done < <("$RCLONE" lsf -R --files-only --format "ps" --separator ";" "sc:$DEST/$product/" 2>/dev/null || true)

  # What is here, and what still needs uploading.
  todo=(); todo_bytes=0; done_n=0; young_n=0
  while IFS=$'\t' read -r rel lsize mtime; do
    if [[ ${remote_size[$rel]:-} == "$lsize" && -n ${has_md5[$rel]:-} ]]; then
      done_n=$((done_n + 1))
    elif (( $(date +%s) - ${mtime%.*} < MIN_AGE_MINUTES * 60 )); then
      young_n=$((young_n + 1))
    else
      todo+=("$rel"); todo_bytes=$((todo_bytes + lsize))
    fi
  done < <(cd "$dir" && find . -type f -name '*.nc' -printf '%P\t%s\t%T@\n' | sort)

  echo "$product: ${#todo[@]} files to upload ($((todo_bytes / 1000000000)) GB)," \
       "$done_n already on Source Cooperative, $young_n too new (under $MIN_AGE_MINUTES min old)"
  if (( DRY_RUN )); then
    for rel in "${todo[@]:0:5}"; do echo "  would upload $rel"; done
    (( ${#todo[@]} > 5 )) && echo "  ... and $(( ${#todo[@]} - 5 )) more"
    unset remote_size has_md5; continue
  fi

  export SOURCE_DIR_OF_PRODUCT=$dir
  if (( ${#todo[@]} )); then
    while IFS= read -r line; do
      echo "$line"
      case $line in OK*) ok_n=$((ok_n + 1)) ;; FAIL*) fail_n=$((fail_n + 1)) ;; SKIP*) skip_n=$((skip_n + 1)) ;; esac
    done < <(printf '%s\0' "${todo[@]}" | xargs -0 -n1 -P "$PARALLEL" bash -c 'upload_one "$0" "$1"' "$product")
  fi
  unset remote_size has_md5
done

echo "Finished $(date '+%F %T %Z'): $ok_n uploaded, $fail_n failed, $skip_n left for the next run"
(( fail_n == 0 )) || { echo "Some files failed. Run the script again to retry them."; exit 2; }
