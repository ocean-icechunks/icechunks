# NOAA GoMOFS — Icechunk

**[💻 Data access (code)](#how-to-open-it)** · **[📦 Data access (NOAA NODD)](https://noaa-nos-ofs-pds.s3.amazonaws.com/index.html#gomofs/netcdf/)** · **[⚙️ How it was built and is kept current](#how-this-was-built)**

[Icechunk](https://icechunk.io) stores of the **NOAA NOS Gulf of Maine Operational Forecast
System (GoMOFS)**, a ROMS ocean model run four times a day (temperature, salinity, currents
and sea surface height on a 30-level curvilinear grid, 777 × 1173 cells, 700 m), from
**2024-12-09 to the newest forecast**, updated every three hours:

| Store | Icechunk repository | Source files | Time step |
|---|---|---|---|
| **3-D fields** (`timeseries-3d`) | `https://data.source.coop/ocean-icechunks/noaa-gomofs/timeseries-3d` | `fields` | 3-hourly |
| **Surface fields** (`timeseries-2d`) | `https://data.source.coop/ocean-icechunks/noaa-gomofs/timeseries-2d` | `2ds` | hourly |

Each store has **one `time` dimension** holding valid times in increasing order: the
nowcasts of every model cycle, one after another, followed by the newest cycle's forecast
(out to +72 h). Every update replaces that forecast tail with the next cycle's.

These stores are **virtual**: they copy no model output. Icechunk holds Zarr metadata and
byte-range references back to NOAA's NetCDF files in the public `noaa-nos-ofs-pds` bucket
(AWS `us-east-1`), so the stores are small (about 80 MB each) and every read is streamed
from NOAA. That costs one extra step when opening (see [How to open it](#how-to-open-it)),
and it means the stores are only as available as NOAA's bucket.

> **NOAA deletes its oldest GoMOFS files about a day a day.** The stores point at those files,
> so the oldest part of a store stops being readable until the store is rebuilt with a later
> start. Rebuilds are done on purpose before that happens (see
> [Backfills and rebuilds](#backfills-and-rebuilds)), but if you need old data, select the
> period you want and check it reads, and do not assume `2024-12-09` always works.

## View it in a browser

There is no browser viewer for these stores yet.

## How to open it

Requires `icechunk >= 2.3` and `xarray`. The model output lives in NOAA's bucket, outside
these stores, so you must authorize the virtual chunk container at open time. This is the
one non-standard step, and the price of not copying the data. The container is in the saved
repository config, so you do not need to know the bucket name.

> **icechunk 1.x will not work.** `icechunk.http_storage` does not exist in icechunk 1.x
> (it arrived in 2.0), and `icechunk.credentials.HttpAccess` arrived in 2.1. Every icechunk
> 2.x release needs **Python 3.12 or newer**, so on an older Python `pip install icechunk`
> quietly installs 1.1.x, and the code below fails with
> `AttributeError: module 'icechunk' has no attribute 'http_storage'`. Check what you have:
> `python -c "import icechunk; print(icechunk.__version__)"`.

```
pip install "icechunk>=2.3" "xarray>=2026.9" "zarr>=3.4" "dask[array]" numpy matplotlib
```

```python
import icechunk
import numpy as np
import xarray as xr


def open_store(name):
    url = f"https://data.source.coop/ocean-icechunks/noaa-gomofs/{name}"
    repo = icechunk.Repository.open(icechunk.http_storage(url))
    auth = icechunk.containers_credentials(
        {p: icechunk.s3_anonymous_credentials() for p in repo.config.virtual_chunk_containers}
    )
    store = repo.reopen(authorize_virtual_chunk_access=auth).readonly_session("main").store
    return xr.open_zarr(store, consolidated=False, chunks={})   # lazy, dask-backed


ds = open_store("timeseries-3d")          # or "timeseries-2d"
print(ds.time.values[[0, -1]])

# In ROMS the last s_rho index is the surface layer. ``last_cycle`` is the newest model cycle;
# everything after it is forecast.
newest = np.datetime64(ds.attrs["last_cycle"])
ds.temp.sel(time=newest).isel(s_rho=-1).plot.pcolormesh(x="lon_rho", y="lat_rho", cmap="turbo")

# A week of surface temperature at one grid point (NERACOOS buoy B01), nowcast plus forecast.
series = ds.temp.isel(s_rho=-1, eta_rho=679, xi_rho=294).sel(time=slice(newest - np.timedelta64(7, "D"), None))
series.compute().plot()
```

Reading a point series fetches one chunk per time step, so a week takes about 15 seconds.
For the surface store use `temp_sur` (and `salt_sur`, `u_sur`, `v_sur`) instead of `temp.isel(s_rho=-1)`.
A longer notebook with maps and a time series is in
[`noaa_gomofs/notebooks`](https://github.com/ocean-icechunks/noaa_gomofs/tree/main/notebooks).

## About the data

| | `timeseries-3d` | `timeseries-2d` |
|---|---|---|
| Model | ROMS, NOAA NOS Gulf of Maine OFS (GoMOFS) | same |
| Grid | curvilinear, `eta_rho` 777 × `xi_rho` 1173, 30 terrain-following `s_rho` levels | same grid, surface only |
| Time step | 3-hourly | hourly |
| Source files | `gomofs.tHHz.YYYYMMDD.fields.{n,f}NNN.nc` | `gomofs.tHHz.YYYYMMDD.2ds.{n,f}NNN.nc` |
| Time-dependent variables | `temp`, `salt`, `u`, `v`, `w`, `zeta`, `Pair`, `Uwind`, `Vwind`, wet/dry masks | `temp_sur`, `salt_sur`, `u_sur`, `v_sur`, `zeta`, `Tair`, `Pair`, `Uwind`, `Vwind`, wet/dry masks |
| Static variables | 84: coordinates, masks, bathymetry `h`, ROMS parameters | the same 84 |

The model runs at 00, 06, 12 and 18 UTC. Each cycle writes `n` (nowcast) files, which end at
the cycle time, and `f` (forecast) files out to +72 h. The stores use every cycle's nowcast
files, which tile the timeline without overlap, and the forecast of the newest cycle only.

- **Time:** one `time` dimension of valid times (UTC). `ds.attrs["last_cycle"]` is the newest
  model cycle; later times are forecast.
- **Coordinates:** 2-D `lon_rho`/`lat_rho` (and the `u`, `v`, `psi` equivalents). Plotting
  these over a web map needs `cartopy >= 0.26`; 0.23 projects this grid about 32 km too far
  north.
- **Land** is `NaN` in the store; the source files write it as the fill value `1e37` and xarray
  masks it.
- **Source:** `s3://noaa-nos-ofs-pds/gomofs/netcdf/YYYY/MM/DD/` (NOAA Open Data
  Dissemination). Only the file names used since 2024-11 are included; the older
  `nos.gomofs.*` files are ignored.

Reads are slower than from NOAA's native Zarr store of the same model
(`noaa-nodd-kerchunk-pds`, `zarr3/gomofs`). The source NetCDF `temp` variable is stored
**uncompressed** in `(1, 8, 259, 391)` chunks of 3.2 MB each, and a virtual store can only
point at those bytes; the native Zarr store uses zstd with `(1, 8, 195, 294)` chunks, so a
read transfers fewer bytes. What these stores add is a **single, continuous time axis across
all cycles** that stays current, so `xarray` can slice by time without opening thousands of files.

## How this was built

The short version: **the references were computed in parallel on AWS using
[Development Seed's `virtualizarr-data-pipelines`](https://github.com/developmentseed/virtualizarr-data-pipelines)
as the infrastructure, copied to Source Cooperative, and are now kept current by a scheduled
GitHub Actions workflow.** The AWS stack is for the heavy lifting, the workflow for the
routine upkeep, and the same stack is what a rebuild or backfill uses. The code and the full recipe
are in [github.com/ocean-icechunks/noaa_gomofs](https://github.com/ocean-icechunks/noaa_gomofs).

### 1. The first version, and why it was replaced

The first store was a five-day snapshot built by a notebook on a single machine
(`noaa-gomofs-icechunk-sc.ipynb` in this folder). It showed that the approach works, but it covered
only a few days and had no way to roll forward. The aim became the whole archive that uses the
current file names (from 2024-11), with the stores kept up to date as new forecast cycles
appear, in the way NERACOOS/GMRI keep the
[NOAA OISST store](https://github.com/ocean-icechunks/noaa_oisst) current.

### 2. Designing the stores

Local pilots of three days each (scripts in this folder: `build_timeseries.py`, `build_fmrc.py`,
`gomofs_common.py`) settled the layout before any cloud money was spent:

- two stores, because `fields` (3-hourly, 3-D) and `2ds` (hourly, surface) have different output intervals;
- one monotonic `time` dimension per store, built from nowcast files only, with the newest cycle's
  forecast on the end (an alternative layout of forecast cycle × lead time, an FMRC, is planned
  but not built);
- an update procedure (trim the old forecast tail, append the new cycles) checked to give
  exactly the same store as building it in one go.

The pilots also turned up the traps listed under
[Things that went wrong](#things-that-went-wrong), and showed that files with the current names
hold forecasts only from late December 2025 (before that, nowcasts only), which is why the history is
nowcast-only.

### 3. Initializing on AWS

Opening 5,622 `fields` files and 16,866 `2ds` files one after another is slow on one machine,
so the initial build used the AWS infrastructure from Development Seed's
[`virtualizarr-data-pipelines`](https://github.com/developmentseed/virtualizarr-data-pipelines)
(AWS CDK: Step Functions plus Lambda, with the Icechunk repository in S3). Its backfill path:

1. A **partition** step splits the list of source files into partitions of 500, and each partition
   into batches of 10.
2. An **initialize** step creates the Icechunk repository on a `backfill` branch, with every array
   already at its full length and the whole `time` axis written.
3. Up to 50 **worker** Lambdas run at once. Each opens its files with VirtualiZarr and writes each
   file's references into that file's own slot on the `time` axis (`region="auto"`), on a forked
   session so workers never collide.
4. A **reduce** step merges the forks, and a **promote** step merges `backfill` into `main`.

Only the pipeline's *processor* is specific to GoMOFS (which files, which time slot, what to write),
plus small changes to the CDK settings, so the GoMOFS-specific parts are a patch against upstream and
one Python file, both in the [`backfill/`](https://github.com/ocean-icechunks/noaa_gomofs/tree/main/backfill)
folder of `noaa_gomofs`. One deployment builds one store. Measured: `timeseries-3d` took about 14 minutes
and `timeseries-2d` about 73 minutes (about two hours when both ran at once), on 2 GB Lambdas.

The result was written to an S3 bucket, checked (the time axis has uniform spacing, a static variable
reads, a sample of data matches the source file), then **copied to Source Cooperative** with the `repo`
file last so that a half-copied store is never visible, and opened anonymously one more time.

### 4. Keeping it up to date

From then on the AWS stack is not involved. A GitHub Actions workflow in
[`noaa_gomofs`](https://github.com/ocean-icechunks/noaa_gomofs/blob/main/.github/workflows/update.yml)
runs every three hours, as follows (the approach is modelled on the OISST store's):

- It signs in to Source Cooperative by **GitHub OIDC** as a service account trusted for that
  workflow's `source-coop` environment, so no secret or long-lived key is stored anywhere.
- It runs `gomofs update` for each store. The command reads the store's newest cycle
  (`last_cycle`), lists NOAA's cycles after it, appends their nowcast files, **drops the previous
  forecast tail**, and appends the newest cycle's forecast. A newest cycle whose forecast files are
  still arriving is left for the next run, because otherwise its forecast would never be added.
- Every command **diffs the store against NOAA's bucket and does only the missing work**, so a
  failed or skipped run needs no retry (the next one catches up), and a run with nothing to do commits nothing.
- Each store has **exactly one writer**, enforced with a workflow concurrency group.
- Each run ends with `gomofs status`, written to the run's summary: the number of steps, the time
  range, whether the oldest and newest steps can still be read, and a warning as the oldest
  step approaches the age at which NOAA has been deleting files.

### Backfills and rebuilds

The same AWS stack is used whenever a lot has to be computed at once:

- **Rebuild to move the start forward.** This is routine, because NOAA deletes its oldest files
  about a day a day. The stores start about 30 days after the oldest surviving file, so a month of
  deletions is absorbed before the oldest references die; a rebuild is the same procedure as the
  first build with a later start. It is **not automated yet**: `gomofs status` warns about 20 days before
  the oldest step could stop reading, and a person runs the rebuild.
- **Filling a hole.** `gomofs update` reports a gap between the stored cycles and the next one as a
  warning but does not fill it; a gap too old to patch is closed by a rebuild.
- **The planned FMRC stores** (forecast cycle × lead time) would use the same stack with a processor
  whose unit of work is a whole cycle.

Until a rebuild, **the front of the stores keeps moving as NOAA prunes**; the static grid variables come
from the newest file at build time, so they are not affected.

### Things that went wrong

- **Static variables pointed at a file NOAA then deleted.** The first full builds took the static grid
  variables from the oldest file, and NOAA deleted it a day later. They now come from the newest file.
- **Per-file global attributes break the parallel merge.** VirtualiZarr rewrites the root group's
  attributes on every region write, and they differ file to file, so each worker changed the root group
  differently and the merge failed ("Multiple writers updated the same groups"). The processor clears them
  for region writes and writes the root attributes once.
- **Time encoding drift.** xarray picks `days since` or `hours since` per file from the values, which made
  some appended files decode to the wrong time. The encoding is pinned to `hours since 2024-01-01`.
- **A failed first run leaves a `backfill` branch behind**, and a restart then fails with
  `AlreadyExistsError`; clear the repository prefix first.
- **Plotting on a map shifted the model about 23 km north** with `cartopy 0.23` (not with 0.26). The data
  and the coordinates are correct; the projection of a curvilinear grid was wrong.

### What was changed from the source

Only these things:

- the time dimension `ocean_time` is renamed to `time`, and the per-file `ntimes` is dropped;
- the files of all cycles are concatenated into one time axis, so the static variables come from one
  file (the newest at build time) instead of being repeated;
- per-file global attributes are not carried over (the root attributes are those of that one file);
- the time encoding is pinned (above);
- the model output itself is untouched: every value is read from NOAA's file at its original byte range.

### Provenance

Source: NOAA National Ocean Service, Gulf of Maine Operational Forecast System, published in the
public `noaa-nos-ofs-pds` bucket. First built 2026-11-13 and moved to Source Cooperative the same
day; the series starts 2024-12-09 (see the start-date rule above). Built with
`icechunk` 2.3.1, `virtualizarr` 2.8.0, `zarr` 3.4.2 and `xarray` 2026.9.0, on
Development Seed's `virtualizarr-data-pipelines` at commit `bc834d7` with the changes in `noaa_gomofs/backfill`.
The repository's commit messages record every update.

## Reuse and citation

The data are produced by NOAA NOS and released without restriction; cite NOAA NOS / CO-OPS as the
source. These stores are an index over them and hold no data of their own.

## Credits

Source data: NOAA National Ocean Service (NOS) Operational Forecast Systems. The AWS backfill
infrastructure is [Development Seed's `virtualizarr-data-pipelines`](https://github.com/developmentseed/virtualizarr-data-pipelines);
the update workflow follows the approach of the NERACOOS/GMRI
[`noaa_oisst`](https://github.com/ocean-icechunks/noaa_oisst) repository. Built by the
ocean-icechunks community with [VirtualiZarr](https://virtualizarr.readthedocs.io) and
[Icechunk](https://icechunk.io).
