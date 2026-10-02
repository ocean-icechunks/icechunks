# AGENTS.md

Instructions for coding agents working in this repository. `CLAUDE.md` contains
only `@AGENTS.md`, so Claude Code reads this file too; edit `AGENTS.md`, not
`CLAUDE.md`. Keep it under 20 KB: Antigravity truncates a rule file at 24 KB, so
detail belongs in `claude/notes/` with a pointer here.

Read `claude/handoff.md` first: it has where each store stands and the open work.

## What this repo is

Jupyter notebooks that publish NOAA ocean datasets as Icechunk repositories on Source Cooperative. Three datasets, built two different ways:

- `coastwatch-heat-content/` — **virtual**: the pattern **source NetCDF files → VirtualiZarr (virtual references) → Icechunk repository**, applied to the NOAA CoastWatch Ocean Heat Content archive. The large science arrays are never copied; Icechunk stores metadata and byte-range references back to the originals.
- `gobai-o2-monthly/` — **materialized**: GOBAI-O2 v2.3 monthly from NCEI, written as real Zarr v3 chunks with `Dataset.to_zarr`. Virtualizing would buy nothing there — the source is a single 12 GB contiguous, uncompressed NetCDF with no chunk boundaries to reference. Keep the two straight: the virtual gotchas below (virtual chunk containers, `url_prefix`, `authorize_virtual_chunk_access`) do not apply to it at all.

- `oa-indicators/` — **virtual**: NCEI accession 0270962, the ocean-acidification-indicator climatology on the North American margins. Same pattern as CoastWatch, but the merge problem is the opposite one: the source is **one indicator per NetCDF file**, twelve files on a byte-identical grid, merged into a single flat group of 72 variables. No time dimension — it is a climatology.

- `noaa-oisst/` — **a README and a viewer only; the store is not built here.** NOAA OISST v2.1 at `ocean-icechunks/noaa-oisst/oisst.icechunk` is built and updated about daily by NERACOOS/GMRI (Alex Kerney; <https://github.com/ocean-icechunks/noaa_oisst>, which as of 2026-09-19 holds only its project README). One repository, a virtual `daily` group with `s3://` references into NOAA's CDR bucket (so readers authorize with `s3_anonymous_credentials()`, not `HttpAccess`) and a materialized `monthly` group. Its README here was written by inspecting the published store. Never write under `noaa-oisst/oisst.icechunk/`.

Sibling repos apply the virtual pattern to other datasets — see "Skills and related repos" below.

## Status

Where each store stands, and what is unfinished, is in `claude/handoff.md`. Build records
(snapshot ids, coverage, object counts) are in the per-dataset notes:
`claude/notes/ohc-rebuild-2026-08-26.md`, `gobai-o2-monthly.md`, `oa-indicators.md`.
Status was kept here until 2026-10-02 and moved out to keep this file under Antigravity's
size limit.

## The browser viewer (`publish_viewer.py`)

`python publish_viewer.py --product gobai-o2 --build ~/gridlook [--prune]` builds
[gridlook](https://github.com/eeholmes/gridlook) and uploads the static build beside a store
(`--dry-run` lists without uploading). `PRODUCTS` is the one place a viewer is configured. The
store is named in the URL **fragment** (`…/viewer/index.html#icechunk+<store url>::varname=oxy`),
which the host never sees, so one build serves any store. A sibling script does the same for
NODD buckets in `nmfs-opensci/gobai-rfrom-icechunks`.

Rules, each learned the hard way — the reasons and details are in `claude/notes/viewers.md`:

- **Build only from a current gridlook.** The script fetches and refuses a checkout behind
  its remote (`--allow-stale` overrides); the 2026-09-17 viewers were 98 commits stale.
- **Every product needs a `catalog` key**, written into the build output, never into the
  gridlook checkout. The picker reads `static/catalog-extended.json`, not `catalog.json`.
- **Link to the repository root, not a group.** gridlook offers the groups and variables
  itself; a good camera view is found by dragging the globe and copying the URL.
- **A republished viewer looks unchanged until a hard reload.** curl the server before
  believing "the update isn't there", then have Eli Ctrl+Shift+R.
- **A virtual store draws only if the source host sends CORS headers.** CoastWatch does not,
  so the OHC viewer shows metadata and coordinates but no science arrays, and nothing on
  our side can fix it. It is published anyway, at Eli's call.
- **Source Cooperative** never infers content types (set one per upload), has no directory
  index (link `index.html`), and its edge 403s Python's default User-Agent.
- **Build with `vite build --sourcemap false` and a capped heap**; `npm run build` gets
  OOM-killed on a small machine.

## Store READMEs

Every store README follows Eli's standard format (reference copy:
`coastwatch-heat-content/README.md`): title ending "— Icechunk"; a one-line emoji navbar
(🌐 View data in browser · 💻 Data access (code) · 📦 Data access (provider) · 📄 DOI when
there is one); an intro with a table of store URLs and the "these stores are virtual"
paragraph; then `## View it in a browser`, `## How to open it`, `## About the data`,
dataset-specific sections, `## How this was built` (`### What was changed from the source`,
`### Provenance`), `## Reuse and citation`, `## Credits`. Directly above the opening code goes
the **"icechunk 1.x will not work"** note: `icechunk.http_storage` arrived in 2.0 and
`credentials.HttpAccess` in 2.1 (checked by installing 1.1.21, 2.0.1 and 2.1.0), and every
2.x needs Python >= 3.12, so an older Python quietly gets 1.1.x and an `AttributeError`.
Run every code block as written, in a venv holding only the README's own pip line, before
publishing. READMEs are mirrored to the store roots from merged `main` and checked by
checksum.

## Skills and related repos

- **`virtual-icechunk` skill** — <https://github.com/nmfs-opensci/agent-skills> (`skills/virtual-icechunk/`, checked out locally at `~/agent-skills`). The shared, agent-independent guidance for building, validating, documenting and auditing virtual Icechunk stores. Prefer it over re-deriving practice from this repo's notebooks, and feed genuinely new lessons back into it rather than only into this file.
- **Sibling repos using the same pattern**, each with its own notebooks and destinations — they are *not* in this repo:
  - `~/cefi-icechunks` — NOAA CEFI MOM6 (`https://data.source.coop/eeholmes/cefi/nepacific-icechunk`, groups `daily/regrid/main`, `daily/regrid/aux`; the yearly-file vs. full-period-file split is why it has two groups).
  - `~/pace-icechunks` — PACE ocean colour.
  - `~/hycom` (`ocean-icechunks/hycom`) — a collection of HYCOM stores, first the GOFS 3.1 reanalysis (306 TB, 63,341 uncompressed NetCDF-3 files). References are *computed* from each file's header rather than parsed, written as a skeleton plus `region=` batches. Its `publish_viewer.py` is a copy of this one, and the viewer fixes above were developed there. Its READMEs tell readers to open with `chunks=None` and select before chunking — right at 2.57 million chunks per variable, **not** advice to copy here.
  - `~/gobai-rfrom-icechunks` — GOBAI-O2 / RFROM, the source of the `requirements.txt` style used here.
  - GlobColour/Copernicus CHL — `https://data.source.coop/fish-pace/globcolour/cmems_obs-oc_glo_bgc-plankton_my_l3-multi-4km_P1D`.

## Required packages

Each pipeline declares its own floors — lower bounds, no lock file, reasoning inline. Both are
mirrored to their destination roots, so a reader who finds the stores on Source Cooperative gets the
pins with them.

```
pip install -r coastwatch-heat-content/requirements.txt   # CoastWatch (virtual)
pip install -r gobai-o2-monthly/requirements.txt          # GOBAI-O2 monthly (materialized)
pip install -r oa-indicators/requirements.txt             # OA indicators (virtual)
```

They are deliberately separate: the GOBAI-O2 notebook uses no virtualizarr, kerchunk, obstore or
scipy, and adds netCDF4 (the only engine that reads the `#mode=bytes` URL form).

Do not use conda; the env will not solve. Two constraints that bite:

- **Python >= 3.12 is required.** Every `icechunk` 2.x release is published
  `requires_python = ">=3.12"`. The JupyterLab image is currently Python 3.11.14, where
  `pip install "icechunk>=2.1"` finds no matching distribution at all (pip sees only the 1.1.x
  line). A 3.12 venv built from `/srv/conda/bin/python3.12` does work and has been used to run
  the notebooks — recipe and traps in `claude/notes/environment.md`.
- **The NetCDF-3 groups need `kerchunk` and `scipy`**, which the notebooks' own inline pip lines
  omit — `NetCDF3Parser` calls `kerchunk.netCDF3.NetCDF3ToZarr`, which subclasses scipy's
  `netcdf_file`. They are satisfied in the image by luck, not by declaration.
  `requirements.txt` lists them.

## Running notebooks

Notebooks run in JupyterLab. Install with
`pip install -r coastwatch-heat-content/requirements.txt` (see above); each
notebook also carries a commented pip line of its own, kept so a notebook downloaded standalone
from Source Cooperative is self-describing — those lines predate `requirements.txt` and omit
`kerchunk`/`scipy`.

The **write** notebooks (`ocean-heat-production-sc.ipynb`, `ocean-heat-test-sc.ipynb`) import shared helpers from `icechunk_utils.py`. It lives at the repo root (the notebooks add `..` to `sys.path`); when a notebook is downloaded standalone from Source Cooperative, `icechunk_utils.py` sits **alongside** it (Jupyter puts the notebook's own directory on `sys.path`, so the co-located copy imports without changes). `ocean-heat-test-local.ipynb` needs no helpers and is fully self-contained.

## Core pattern (used in all notebooks)

1. Create an `ObjectStoreRegistry` pointing to the source data location (S3 or HTTPS).
2. Open each source file virtually with `open_virtual_dataset(..., loadable_variables=[coords], decode_times=True)`.
3. Configure an `icechunk.RepositoryConfig` with a `VirtualChunkContainer` whose `url_prefix` **must have a trailing `/`**.
4. Create or open the Icechunk repo with `icechunk.Repository.create/open(storage, config)`.
5. Write the first file with `vds.vz.to_icechunk(session.store)` and append later files with `append_dim="time"`.
6. Commit with `session.commit("message")` — nothing persists until this call.
7. Reopen for reading: `repo.readonly_session("main").store` → `xr.open_zarr(store, consolidated=False)`.

## Credentials

- **Source Cooperative write credentials come from the `source-coop` CLI, not from a file in this repo.** `icechunk_utils.get_source_credentials()` shells out to `source-coop creds` and then reads the CLI's own cache at `~/.cache/source-coop/credentials/_default.json`. Any `*creds*.json` sitting in the working tree is a leftover from an older workflow; it is gitignored and nothing reads it. These are short-TTL STS tokens — refresh with a browser login:
  ```bash
  source-coop login --duration 1d --port 8400
  ```
  The CLI lives at `~/.cargo/bin/source-coop` on this hub and is not on `$PATH` by default;
  `icechunk_utils` finds it via `$SOURCE_COOP_CLI`, then `$PATH`, then `~/.cargo/bin`. The
  login flow is served on the given port — reach it through the hub proxy at
  `<hub-url>/user/<username>/proxy/8400/`.
  A full rebuild takes about 2.5 hours, so ask for a duration well beyond that.
  `open_source_icechunk_repo` enforces `min_minutes_left` (default 15) and stops cleanly
  rather than starting a write that cannot finish; `wait_for_fresh_repo` additionally
  prompts for a refresh, but needs an interactive session.
- Public Icechunk repos on Source Coop can be read anonymously via `icechunk.http_storage(url)`.
- NOAA S3 sources use `skip_signature=True` / `anonymous=True`.
- CoastWatch HTTPS requires a browser-like User-Agent header; the default `python-requests` UA returns 403.

## Notebooks

- `gobai-o2-monthly/gobai-o2-monthly-icechunk-sc.ipynb` is guarded by `RUN_WRITE` and
  `RUN_MIRROR`, both `False` in the committed copy, so as committed it writes nothing.
- `coastwatch-heat-content/` has three: `ocean-heat-test-local.ipynb` (local, no
  credentials, carries its outputs), `ocean-heat-test-sc.ipynb` (writes only to the scratch
  repo `ocean-icechunks/test-repo/noaa-ohc`, git only, never mirrored, no saved outputs) and
  `ocean-heat-production-sc.ipynb` (the published stores).

What each does, which are mirrored, and when each was last run: `claude/notes/notebooks.md`.

## Key gotchas (GOBAI-O2 / materialized)

In `claude/notes/gobai-o2-monthly.md` under "Gotchas": NCEI's broken download button and the
working archive path, streaming with `engine="netcdf4"` + `#mode=bytes`, and never sampling a
contiguous uncompressed source through dask chunks (11m41s vs 57 s).

## Key gotchas

- **`url_prefix` must end with `/`** in `VirtualChunkContainer` — missing the slash silently fails to match virtual chunks.
- **`authorize_virtual_chunk_access`** must be passed at `Repository.open/create` time for virtual chunks outside the Icechunk repo to be readable.
- **Anonymous read URL must include the bucket.** `icechunk.http_storage(url)` needs the full path `https://data.source.coop/{BUCKET}/{prefix}` (e.g. `ocean-icechunks/noaa-ohc/na`), not just the prefix. A wrong/short URL raises `RepositoryNotFoundError: the repository doesn't exist` **deterministically** — it is not a flaky gateway. When an open 404s, verify the full `{bucket}/{prefix}` URL by hand before adding retries. (The S3 write path via `open_source_icechunk_repo` takes `bucket=` separately, so `region_prefix()` intentionally omits it.)
- **`save_config()` is required for anonymous readers.** `Repository.open(storage, config=...)` uses the config only for the current session. To persist the `VirtualChunkContainer` so anonymous reopeners pick it up, call `repo.save_config()` after open/create.
- **Scalar vs. slice indexing on virtual arrays**: prefer `isel(time=slice(0,1), z_l=slice(0,1)).squeeze(drop=True)` over `isel(time=0, z_l=0)` to avoid loading unexpectedly large chunks.
- **Transient CoastWatch read failures are not corruption.** A virtual-chunk read can fail with `StorageError: error fetching virtual reference ... connection closed before message completed`; the same read succeeds on retry with nothing changed (verified 5/5 after one such failure). CoastWatch HTTPS is slow and drops connections. `scrape_nc_urls` retries with backoff on the write side; chunk reads have no retry, so a reader just sees the drop.
- **Writable sessions are single-use**: after `session.commit()`, call `repo.writable_session("main")` again before writing more data.
- **A second run into an existing repo needs `mode="w"`.** `vds.vz.to_icechunk(store, group=G)`
  raises `zarr.errors.ContainsGroupError: A group exists in store ... at path 'G'` when the
  group is already there, so a demo notebook that worked once fails the next time against the
  same scratch repo. `to_icechunk(..., group=G, mode="w")` replaces it. Found 2026-09-17 by
  re-running `ocean-heat-test-sc.ipynb` against `test-repo/noaa-ohc`, which still held the
  group from an earlier verification run; the notebook now passes `mode="w"` on the first
  file. `write_group` in the production notebook sidesteps this by skipping groups that
  already exist, which is why the production path never hit it.
- **Variables with different file layouts cannot be merged virtually** — they need separate groups. Here that is why `daily`/`14day_v1`/`14day` are three groups rather than one array.
- **Coordinate repair before writing.** Some CoastWatch files carry all-zero lat/lon grids. `build_grid_template` probes the first files for a valid grid and `make_repair` substitutes it as a `preprocess` hook on `open_virtual_mfdataset`; files that still fail to open are dropped and counted. The same hook strips NaN attributes, which Zarr metadata (JSON) cannot represent.

## Key gotchas (OA indicators / merging one variable per file)

- **`xr.merge` applies `combine_attrs` to *variable* attributes, not just the dataset's.** So
  `combine_attrs="drop"` silently empties every variable's attrs, not only the globals. Use
  `"drop_conflicts"` and clear the per-file globals explicitly (`vds.attrs = {}`) instead.
- **`vz.to_icechunk` defaults to `mode="w-"`**, so re-running a write against a store that already
  has a root group raises `ContainsGroupError` rather than being a no-op. The notebook checks for a
  populated store and skips unless `OVERWRITE` is set.
- **The source coordinates are unusable as delivered.** The files carry phony HDF5 dimension scales
  `dep`/`lat`/`lon` — all zeros, marked "a netCDF dimension but not a netCDF variable" — with the
  real values in separate `depth`/`latitude`/`longitude` variables. xarray hides the phony scales and
  reports `Dimensions without coordinates`, so `sel(lat=...)` does not work on the source at all.
  `swap_dims` promotes the real ones; this is metadata-only, which is all a virtual store can do.
- **Name the coordinates `lat`/`lon`, not `latitude`/`longitude`** — gridlook ranks the short
  spelling above the long one, and variables whose *names contain* `latitude`/`longitude` are hidden
  from its variable picker.
- **gridlook does not need a time dimension.** Every time-specific path in it is gated on a dimension
  literally named `time` and falls through to a no-op, so `(depth, lat, lon)` renders as a regular
  grid with a generic slider. It does require the spatial dims to be the **trailing two** and
  `dimension_names` present in the Zarr metadata.
- **NCEI sends `Access-Control-Allow-Origin: *`** on ranged GETs, where `coastwatch.noaa.gov` sends
  no CORS headers at all. That is the whole reason this viewer draws and the CoastWatch one does not.
  NCEI also serves any User-Agent, unlike CoastWatch.
- The source files are NetCDF-4/HDF5 only, so **`kerchunk` and `scipy` are not needed** here — the
  CoastWatch NetCDF-3 path is what drags those in.

## Manifest splitting (large repos)

For repos with 1000s of time steps, configure manifest splitting to avoid giant manifests at commit time:

```python
config.manifest = icechunk.ManifestConfig(
    splitting=icechunk.ManifestSplittingConfig.from_dict({
        icechunk.ManifestSplitCondition.AnyArray(): {
            icechunk.ManifestSplitDimCondition.DimensionName("time"): 100
        }
    })
)
config.manifest.max_concurrent_manifest_fetches_during_commit = 16
```

## Public Icechunk repos

| Dataset | URL |
|---|---|
| CoastWatch OHC — North Atlantic (2020–present) | `https://data.source.coop/ocean-icechunks/noaa-ohc/na` |
| CoastWatch OHC — North Pacific (2020–present) | `https://data.source.coop/ocean-icechunks/noaa-ohc/np` |
| CoastWatch OHC — South Pacific (2020–present) | `https://data.source.coop/ocean-icechunks/noaa-ohc/sp` |
| GOBAI-O2 v2.3 monthly (2004–2024), materialized | `https://data.source.coop/fish-pace/gobai-o2/monthly` |
| OA indicators, North American margins (climatology), virtual | `https://data.source.coop/ocean-icechunks/oa-indicators/climatology` |

Viewers, and whether each one renders: `claude/notes/viewers.md`.

Each CoastWatch OHC region is a **separate repo** (different lat/lon grids). Every region repo has three groups: `daily` (original `{region}` product, NetCDF-3), `14day_v1` (`{region}14` NetCDF-3 big-endian), `14day` (`{region}14` HDF5 little-endian). The `14day_v1`/`14day` split is at 2025 day 084/085; the `daily`/`14day` split is a variable-set/product-generation difference.

The `noaa-ohc/` **root** also holds five docs files mirrored from git (list and mechanics in
`claude/notes/notebooks.md`); keep them in sync when the git versions change.
