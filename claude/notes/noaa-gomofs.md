# GoMOFS (virtual, rolling-window snapshot)

Store: `ocean-icechunks/noaa-gomofs` (Source Cooperative product, **us-east-1**, public).
Builder: `noaa-gomofs/noaa-gomofs-icechunk-sc.ipynb`. Source: `s3://noaa-nos-ofs-pds/gomofs/netcdf/`.

## Build record

| | |
|---|---|
| First snapshot | `6SSGY2GQR24J0YFNYGFG`, 2026-11-11 |
| Coverage | 2026-11-06 21:00 -> 2026-11-14 12:00, 62 steps, 3-hourly |
| Files | 38 nowcast (`n003`/`n006` of every cycle for 5 days) + 24 forecast (`f003`-`f072` of the 2026-11-11 12z cycle) |
| Virtual chunk container | `s3://noaa-nos-ofs-pds/`, anonymous, `us-east-1` |

Not an update pipeline: rebuilding means an empty repository. The notebook refuses a
repository that already has commits.

## Things learned

- **Product creation.** `source-coop product create` returned HTTP 501 and a write to a
  non-existent product failed with `NoSuchBucket`. The product was created in the web UI. The
  product ID cannot be edited afterwards (`product edit` changes title, description,
  visibility and state only), so a typo means delete and recreate. Region is chosen at creation.
- **`source-coop auth login` is separate from `source-coop creds`.** `creds --format env`
  renews S3 credentials from the refresh token; product management calls need a completed
  browser login (`auth status` showing the account instead of "unknown").
- **Nowcast files tile the truth series.** `n003` is valid 3 h before the cycle time and `n006`
  at it, so four cycles a day give an unbroken 3-hourly series; the newest cycle's `f003`
  starts right after.
- **Comparing against the source needs masking and nowcast-only times.** The source writes land
  as `_FillValue` 1e37, xarray masks it to NaN. Forecast times differ between builds made on
  different days, so a source-comparison against a store built earlier must use nowcast times
  before that store's commit.
- **Source NetCDF `temp` is uncompressed** (no deflate, no shuffle), chunked `(1, 8, 259, 391)`,
  3.24 MB per chunk.

## Benchmark against NOAA's native Zarr v3 store (2026-11-11)

Native store: `noaa-nodd-kerchunk-pds/zarr3/gomofs` (zstd, chunks `(1, 8, 195, 294)`, chunks
0.15-1.15 MB for the surface layer). Same 62 time steps, surface layer, run from a home
workstation (12 vCPU, not on AWS), medians of 3, icechunk read from Source Cooperative.

| test | zarr3 | icechunk |
|---|---|---|
| open | 2.16 s | 1.93 s |
| one-time map | 0.56 s | 1.56 s |
| point time series | 2.00 s | 5.00 s |
| mean over all times | 26.9 s | 46.5 s |

Opening with `chunks=None` (no dask) gave the same ranking (mean over all times 26.2 s vs
44.1 s), so dask was neither helping nor hurting. In no-dask mode xarray caches a loaded
array on the variable, so build the lazy array fresh inside each timed call or repeat runs
read from memory.

The most likely cause of the gap is bytes transferred (uncompressed 3.2 MB chunks against
zstd chunks of at most 1.15 MB), and read amplification for the single-time and point reads
(the whole 8-layer chunk is fetched for one layer). Bytes transferred were **not measured
directly**. An intermittent `connection closed before message completed` from icechunk's
virtual chunk fetches occurred in several early runs of the heavy read under dask; it did
not recur in the final runs.

Untested: rewriting the same steps as native Zarr with zstd and the `(1, 8, 195, 294)`
chunking, to confirm compression and chunking explain all of the gap; running from
us-east-1.

## Full-archive design: four stores (started 2026-11-12)

Four repositories side by side under `ocean-icechunks/noaa-gomofs/`, built by scripts in
`noaa-gomofs/` (`gomofs_common.py`, `build_fmrc.py`, `build_timeseries.py`), modelled on
`~/repos/necofs-provider`. `3d` = `fields` files (3-hourly, 26 per cycle: n003, n006, f003-f072);
`2d` = `2ds` files (hourly surface fields, 78 per cycle: n001-n006, f001-f072).

| store | dims | built by |
|---|---|---|
| `fmrc-3d`, `fmrc-2d` | `time` (cycle time) x `step` (lead, -3..72 h / -5..72 h) | `build_fmrc.py` |
| `timeseries-3d`, `timeseries-2d` | `time` (valid time, monotonic) | `build_timeseries.py` |

What the archive actually holds (S3 listing of 107,051 objects, 2026-11-12):

- Earliest file 2024-07-10, but `nos.gomofs.*` names in flat `YYYYMM/` folders until Oct 2024;
  only `gomofs.tHHz.YYYYMMDD.*` names (2024-11-07 on) are used.
- **New-style names are nowcast-only until 2025-12-20 06Z.** Forecast files exist for only 249
  `fields` cycles; they are sparse until 2026-09-13 and complete from then. So the monotonic
  stores can start 2024-11-07 but an FMRC is mostly empty before 2026-09. Incomplete cycles
  are skipped and reported, never padded.
- From 2024-11-19 the same files are in both the flat `YYYYMM/` folder and `YYYY/MM/DD/`; the
  tree copy is used (byte-identity of the two not checked).

Traps found building it (each fixed in the code):

- `expand_dims("time")` on the whole dataset gave every static variable (`h`, masks, `Cs_r`,
  ROMS scalars) a time axis. Only variables with a `step` dim get `time`.
- xarray picks `days since` or `hours since` per cycle; an appended cycle then decoded to the
  wrong date (2025-12-20 12Z read as 2025-12-26 06Z). `time` and `step` encodings are pinned.
- Appending re-writes static scalar variables, which virtualizarr refuses (`dimension_names`
  `None` vs `()`). Appends carry only variables that have the append dimension.
- `ntimes` is dropped (per-file scalar, misleading once merged).
- Monotonic update: trim the old forecast tail with `zarr` `resize` (chunks are one time step,
  so the cut is exact), append the new cycles' nowcasts and the newest cycle's forecast; the
  newest cycle time is the root attribute `last_cycle`. Checked equal to a one-shot build.

Pilot (local repositories, no Source Cooperative writes): monotonic stores 2024-11-07..09,
FMRC 2025-12-20..22 (3 cycles). Sizes are under 1 MB each. Not yet done: a backfill, the
scheduled update, any `sc:` destination run, viewer, README.

## Backfill pipeline (2026-11-12): `~/repos/noaa-gomofs-virtualizarr-data-pipelines`

A local copy of developmentseed's `virtualizarr-data-pipelines` template (no remote, nothing
committed), with `processor.py` replaced by a GoMOFS nowcast processor (`GOMOFS_VARIANT` 3d|2d,
`GOMOFS_END_CYCLE`). Plan: backfill the two monotonic stores into an AWS bucket (profile
`esiplab2`), copy the repositories to `ocean-icechunks/noaa-gomofs/<store>`,
open them anonymously to check, then GitHub Actions (service account trusted via
`source-coop service-account create --github`) runs `build_timeseries.py` / `build_fmrc.py`.

- Nowcasts are complete: 2,940 cycles 2024-11-07 18Z .. 2026-11-12 12Z, none missing, both
  families; 5,880 `fields` and 17,640 `2ds` files. A 2024 and a 2026 file have identical
  variables, shapes, dtypes, chunking, compression and attributes. So the axis is declared up
  front from cycle times, no listing.
- The `YYYY/MM/DD/` tree starts at the **2024-11-19 18Z** cycle, not the day: earlier cycles that
  day are only in the flat folder. `list_cycles` had this wrong (fixed); every inventory key now
  exists in the saved listing.
- Region-write traps (virtualizarr rewrites root group attributes on every region write):
  per-file global attributes must be cleared and the root `coordinates` attribute must equal
  what workers write, or `session.merge` fails: "Multiple writers updated the same groups".
- Local fork/merge backfill (6 `3d` and 12 `2d` steps, real S3 reads) matches the independent
  `build_timeseries.py` stores exactly. Not yet done: `cdk synth`/deploy, the real backfill, the
  copy to Source Cooperative, the GitHub Actions workflow, the FMRC processor.
- `cdk synth` (esiplab2, stack `noaa-gomofs-timeseries-3d`, node 26 with `aws-cdk@latest`; the
  pinned 2.103 CLI is not used) works: 2 buckets (Retain), 7 Lambdas (2 GB; 900 s for the six
  backfill ones), 1 state machine, SQS mapping disabled. It caught that the backfill Lambdas
  did not get `GOMOFS_*` (their env dict is built separately from `processor_env`); fixed with
  `extra_env`. Docker image builds and the deploy are untested.
- **Deployed and tested 2026-11-12** (stack `noaa-gomofs-timeseries-3d`, esiplab2 account,
  us-east-1; account bootstrapped for CDK that day). Repository goes to
  `s3://esip-qhub/rsignell/gomofs/<store>` (bucket is us-west-2, `ICECHUNK_REGION=us-west-2`;
  Lambdas stay in us-east-1 near NOAA). Test run (`GOMOFS_END_CYCLE=2024-11-08T18:00`, prefix
  `rsignell/gomofs/test-3d`, 10 files): state machine SUCCEEDED in 129 s, 136 objects / 100 kB,
  commits "Repository initialized" -> "Initialize backfill shape" -> "Backfill partition 0";
  `temp`, `u`, `zeta` identical to the local pilot at all 10 steps; saved config has the NOAA
  container. The test store is still at `rsignell/gomofs/test-3d`.
- Docker bridge networking on the dev machine is broken (ufw `DEFAULT_FORWARD_POLICY="DROP"` drops
  container traffic; `sudo ufw route allow in on docker0` would fix it). `.env` sets
  `DOCKER_BUILD_NETWORK_HOST=1` so CDK builds images on the host network instead.
- Not done: full 3d backfill (reset `ICECHUNK_PREFIX=rsignell/gomofs/timeseries-3d`,
  `GOMOFS_END_CYCLE=2026-11-12T12:00:00`, redeploy, inventory of 5,880 keys), the 2d stack, copy to
  Source Cooperative, the GitHub Actions workflow, the FMRC processor.

## Full timeseries-3d backfill (2026-11-12)

- `s3://esip-qhub/rsignell/gomofs/timeseries-3d` (us-west-2), 5,878 steps, 2024-11-07 21Z to 2026-11-12 12Z,
  uniformly 3-hourly, 334 objects / 78 MB. Execution `gomofs-3d-3` took ~14 min (12 partitions, 50 workers).
  Spot reads (temp, zeta at steps 0, 1000, 5877) work against NOAA's bucket; root attr `last_cycle` = 2026-11-12T12:00:00.
- **NOAA is pruning the archive from the front.** The two 2024-11-07 18Z `fields` files existed in the
  listing taken that morning and were 404 a few hours later. The series start was moved to 2024-11-08 00Z
  (`FIRST_CYCLE` in the processor, `FIRST_DAY` in `gomofs_common.py`). Any reference to the oldest files can
  break at any time; the rolling-archive question is therefore answered "yes, at least for the oldest end".
- A failed first `initialize_backfill_store` leaves a `backfill` branch behind and a rerun then fails with
  `AlreadyExistsError`; clear the prefix (or delete the branch) before restarting.

## Rebuild after pruning was confirmed (2026-11-13)

- NOAA deletes the oldest files about a day a day (oldest `fields`/`2ds` file was 2024-11-09 00Z on 2026-11-13).
  The first timeseries-2d build (73 min) and the first 3d build both had their static variables
  (`h`, masks, `dstart`, ...) pointing at the oldest file, which was deleted, so those variables
  failed with `NoSuchKey`.
- Fixed in `processor.py`: statics and root attrs now come from the NEWEST nowcast file; the series starts
  `FIRST_CYCLE` = 2024-12-10 00Z (env `GOMOFS_FIRST_CYCLE`), ~30 days after the oldest surviving cycle.
- Rebuilt (executions `gomofs-3d-4`, `gomofs-2d-2`, run concurrently): `esip-qhub/rsignell/gomofs/timeseries-3d`
  5,622 steps 2024-12-09 21Z to 2026-11-12 12Z 3-hourly (~14 min); `timeseries-2d` 16,866 steps from
  2024-12-09 19Z hourly (~2 h when run alongside 3d). Statics and spot reads verified for both.
- The 2d stack is a second deployment from `.env.2d` (not gitignored; no secrets in it).
- Still to do: a monthly rebuild / drift check in the update job; copy to Source Cooperative; FMRC stores.

## Live on Source Cooperative (2026-11-13)

- `ocean-icechunks/noaa-gomofs/timeseries-3d` and `timeseries-2d` (copied from esip-qhub, anonymous open verified).
- Updater: <https://github.com/ocean-icechunks/noaa_gomofs> (local clone `~/repos/noaa-gomofs-icechunk`), modelled on
  noaa_oisst: `update.yml` every 3 h, OIDC into service account `ocean-icechunks--gomofs-updates` (trust: environment
  `source-coop`, write on `noaa-gomofs`). Created in the web UI because `source-coop service-account create` returned 404
  and the API 401 even after a fresh login. Repo variables: `GOMOFS_S3_BUCKET=ocean-icechunks`, `SOURCE_COOP_SERVICE_ACCOUNT`.
- First manual run succeeded for both: 3d 5,654 steps and 2d 16,962 steps, to 2026-11-16 12Z (forecast tail), spacing uniform.
- Open: monthly rebuild (NOAA prunes ~1 day/day; `status` warns at 715 d), FMRC stores, README/viewer, esip-qhub cleanup.
