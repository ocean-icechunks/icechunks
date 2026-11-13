# NOAA GoMOFS — Icechunk

**[💻 Data access (code)](#how-to-open-it)** · **[📦 Data access (NOAA NODD)](https://noaa-nos-ofs-pds.s3.amazonaws.com/index.html#gomofs/netcdf/)**

> **Update 2026-11-13.** The five-day snapshot described below was replaced by two stores that roll forward
> automatically: `ocean-icechunks/noaa-gomofs/timeseries-3d` (3-hourly) and `timeseries-2d` (hourly), kept up to date
> by <https://github.com/ocean-icechunks/noaa_gomofs>, which also documents how they were initialized. This notebook
> and the scripts here (`build_timeseries.py`, `build_fmrc.py`, `gomofs_common.py`) are the earlier local builders.

An [Icechunk](https://icechunk.io) store of the **NOAA NOS Gulf of Maine Operational
Forecast System (GoMOFS)** — a ROMS ocean model run four times a day, with temperature,
salinity, currents and sea surface height on a 30-level curvilinear grid
(777 × 1173 cells, 3-hourly output). This store covers the **last five days of nowcasts plus
the newest forecast cycle's ~3-day forecast**.

```
https://data.source.coop/ocean-icechunks/noaa-gomofs
```

This store is **virtual**: it holds Zarr metadata and byte-range references, and no array
data at all. Every data read goes back to NOAA's public `noaa-nos-ofs-pds` bucket
(AWS `us-east-1`), so the store is only as available as that bucket is.

What it adds over the source archive is that ~60 single-time NetCDF files become **one
dataset along `ocean_time`**, so `xarray` can slice by time without opening every file.

**It is a snapshot, not a live feed.** The notebook that builds it has no update step, so
the store covers the window it was built for and does not roll forward by itself. The
current window is in the latest commit message and in `ocean_time`.

There is no browser viewer for this store yet.

## How to open it

> **icechunk 1.x will not work.** `icechunk.http_storage` does not exist in icechunk 1.x
> (it arrived in 2.0), and `icechunk.credentials.HttpAccess` arrived in 2.1. Every icechunk
> 2.x release needs **Python 3.12 or newer**, so on an older Python `pip install icechunk`
> quietly installs 1.1.x, and the code below fails with
> `AttributeError: module 'icechunk' has no attribute 'http_storage'`. Check what you have:
> `python -c "import icechunk; print(icechunk.__version__)"`.

```
pip install "icechunk>=2.3" "xarray>=2026.9" "zarr>=3.4" "dask[array]" numpy
```

```python
import icechunk
import xarray as xr

repo = icechunk.Repository.open(
    icechunk.http_storage("https://data.source.coop/ocean-icechunks/noaa-gomofs")
)

# The arrays live in NOAA's bucket, outside the store, so authorize the virtual chunk
# container at open time. This is the one non-standard step for a virtual store; the
# container is in the saved config, so you do not need to know the bucket name.
auth = icechunk.containers_credentials(
    {p: icechunk.s3_anonymous_credentials() for p in repo.config.virtual_chunk_containers}
)
store = repo.reopen(authorize_virtual_chunk_access=auth).readonly_session("main").store

ds = xr.open_zarr(store, consolidated=False, chunks={})
print(ds.ocean_time.values[[0, -1]])

# In ROMS the last s_rho index is the surface layer.
sst = ds.temp.isel(s_rho=-1, ocean_time=-1)
sst.plot.pcolormesh(x="lon_rho", y="lat_rho", cmap="turbo")
```

## About the data

| | |
|---|---|
| Model | ROMS, NOAA NOS Gulf of Maine OFS (GoMOFS) |
| Grid | curvilinear, `eta_rho` 777 × `xi_rho` 1173, 30 terrain-following `s_rho` levels |
| Time step | 3-hourly, `ocean_time` |
| Coverage | the last 5 days of nowcasts, then the newest cycle's forecast (to +72 h) |
| Variables | `temp`, `salt`, `u`, `v`, `w`, `zeta`, wind and pressure forcing, plus the grid, masks and ROMS parameters |
| Source | `s3://noaa-nos-ofs-pds/gomofs/netcdf/YYYY/MM/DD/` (NOAA Open Data Dissemination) |

Surface layer is the **last** `s_rho` index. Land is `NaN` in the store; the source files
write it as the fill value `1e37` and xarray masks it.

Reads are slower than from NOAA's native Zarr store of the same model
(`noaa-nodd-kerchunk-pds`, `zarr3/gomofs`). The source NetCDF `temp` variable is stored
**uncompressed** in `(1, 8, 259, 391)` chunks of 3.2 MB each, and a virtual store can only
point at those bytes; the native Zarr store uses zstd with `(1, 8, 195, 294)` chunks, so a
read transfers fewer bytes. Measurements are in `claude/notes/noaa-gomofs.md` in the repository.

## How this was built

[`gomofs-icechunk-sc.ipynb`](gomofs-icechunk-sc.ipynb) builds it with
[VirtualiZarr](https://virtualizarr.readthedocs.io):

1. List the last `DAYS` days of `*.fields.*.nc` in the source bucket. Keep every nowcast
   file (`n003`, `n006` of each cycle, which tile a continuous 3-hourly series) and the
   forecast files (`f003`–`f072`) of the newest cycle only.
2. `open_virtual_dataset` each file with `HDFParser`, loading only `ocean_time`.
3. `xr.concat` along `ocean_time` with `data_vars="minimal"`, `coords="minimal"`,
   `compat="override"`, so the ~85 static variables come from the first file instead of being
   repeated along time.
4. Write with `ds.vz.to_icechunk`, with a virtual chunk container for
   `s3://noaa-nos-ofs-pds/`.

### What was changed from the source

Nothing in the data or metadata. The only transformation is concatenation along
`ocean_time`; static variables take the first file's references.

### Provenance

Source: NOAA National Ocean Service, Gulf of Maine Operational Forecast System, published in
the public `noaa-nos-ofs-pds` bucket. Built with `icechunk` 2.3.1, `virtualizarr` 2.8.0,
`zarr` 3.4.2, `xarray` 2026.9.0. The first snapshot was committed 2026-11-11 from the
2026-11-11 12z cycle.

## Reuse and citation

The data are produced by NOAA NOS and released without restriction; cite
NOAA NOS / CO-OPS as the source. This store is an index over them and holds no data of its
own.

## Credits

Source data: NOAA National Ocean Service (NOS) Operational Forecast Systems.
Store built by the ocean-icechunks community with
[VirtualiZarr](https://virtualizarr.readthedocs.io) and [Icechunk](https://icechunk.io).
