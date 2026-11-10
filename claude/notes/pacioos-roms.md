# PacIOOS ROMS Hawaiʻi — feasibility probe

Research only (2026-11-10); nothing built yet. Eli is working with the PacIOOS folks, so
access routes other than their public servers are on the table, including handing them a
script to run on their own files.

Source page: <https://www.pacioos.hawaii.edu/currents/model-hawaii/#access>. The page's
dataset id is `roms_hiig` (hidden `<input id="asset">`; its Access tab is filled by JS).

## Probe etiquette

About 30 small requests and two single-time-step downloads (~8 MB each), with sleeps between
them. No throttling or errors seen. Keep later probes this gentle: the server is the same one
that serves PacIOOS's public forecast.

## The datasets

Server: `pae-paha.pacioos.hawaii.edu` — ERDDAP 2.29.0 and THREDDS (TDS) 4.6 behind
Apache 2.4.29. ERDDAP's `sourceUrl` for each is THREDDS OPeNDAP, so ERDDAP is a proxy here.

Shared grid: 195 lat × 295 lon (≈4 km; lat 17.018–23.982, lon −163.831 to −152.519),
36 depth levels (0.25–5500 m), 3-hourly. Already **regular lat/lon on z-levels** — not
native ROMS s-coordinates or a curvilinear grid. 3-D variables `temp salt u v`; the
`*_ssh` sibling of each dataset carries `zeta` (2-D). A `mask` (lat, lon) is also present.

| ERDDAP id | What | Coverage (2026-11-10) | Steps | Raw size, 3-D vars |
|---|---|---|---|---|
| `roms_hiig` | 7-day forecast, daily runs (FMRC "best") | 2025-01-01 → +7 days | 5,473 | ~180 GB |
| `roms_hiig_assim` | 3-day data-assimilating hindcast (FMRC "best") | 2015-04-12 → present | 33,228 | ~1.1 TB |
| `roms_hiig_reanalysis` (v2.0) | reanalysis, finished | 2009-01-01 → 2020-12-28 | 35,040 | ~1.16 TB |

Per time step, one 3-D variable is 8.28 MB raw (float32), so the four together come to ~33 MB.
Other regions use the same naming (`roms_marig` Guam, `roms_samoa`, `roms_wpac`,
`roms_hiomsg` Oʻahu south shore, each with `_assim`/`_ssh` variants); not probed.

The forecast archive is **rolling**: the `history` attribute records the start date being
moved forward (2015-04-15 → 2023-01-01 → 2025-01-01). An Icechunk store would become the
only long-term archive of past forecasts.

## Can the NetCDFs be reached directly? No — not from outside

- `/thredds/ncml/...` returns `location="Not provided because of security concerns."`
  for both a forecast run and the reanalysis: the file paths are hidden on purpose.
- No catalog declares an `HTTPServer` service, only OPeNDAP, NCSS, WMS, WCS, ISO, NcML.
  `/thredds/fileServer/` → 404, `/thredds/fileServer/roms_hiig/` → 400.
- The FMRC's `files/` catalog → 404. Its `runs/` catalog lists 651 daily runs
  (`ROMS_Hawaii_Regional_Ocean_Model_RUN_<date>T00:00:00Z`, 2025-01-01 → 2026-11-09),
  each 57 steps (7 days + the initial step), ≈1.9 GB raw of 3-D variables.
- ERDDAP `files/roms_hiig/` → 404.

So the CoastWatch-style virtual pattern is closed unless PacIOOS changes something.

What THREDDS does reveal (`.das`, `_ChunkSizes`): the source files are **NetCDF-4/HDF5
chunked one time step per chunk**, `(1, 36, 195, 295)` for 3-D and `(1, 195, 295)` for
`zeta`; time is chunked 1024. Whether they are deflated is not visible from TDS 4.6.

## Throughput through the public services

| Path | One step of `temp` (8.3 MB) |
|---|---|
| ERDDAP `griddap/...nc` | 11.4 s (~0.7 MB/s) |
| THREDDS OPeNDAP `.dods` | 9.8 s (~0.8 MB/s) |
| THREDDS NCSS | 404 for the reanalysis |

At ~0.8 MB/s a terabyte is ~15 days of one stream. A gobai-rfrom style backfill (download
from ERDDAP → process → upload) of the reanalysis or hindcast would be 2–3 weeks of
continuous load on their server. A daily forecast increment (8 new steps ≈ 265 MB, ~5–6
min) is fine.

ERDDAP sends `Access-Control-Allow-Origin: *`; THREDDS CORS not checked.

ERDDAP-generated `.nc` files are **NetCDF-3 classic** (contiguous, uncompressed), so a file
downloaded from ERDDAP does not carry the source's HDF5 chunking.

Compression of one `temp` step (10% NaN land): zlib 1.39×, blosc-zstd+shuffle 1.94×,
plus rounding to 0.001 °C 2.2×. A materialized reanalysis would be ~550–600 GB.

## Options, best first

1. **PacIOOS exposes the files** (no download through OPeNDAP):
   - (a) enable `HTTPServer` on THREDDS → virtual store against their server, exactly the
     CoastWatch pattern. Store is MB; every read hits their server.
   - (b) they copy the NetCDFs to a bucket (Source Cooperative, or NODD as for
     gobai-rfrom) → virtual store against the bucket. One-time ~1 TB for the reanalysis.
2. **PacIOOS runs a script on their side** that writes Zarr/Icechunk to Source
   Cooperative from local files — modelled on the GOBAI-O2 notebook.
3. **Forecast as a daily append** — by us through OPeNDAP or by a step in their forecast
   job. Icechunk versioning suits it: tag each run so past forecasts stay readable.
4. Order: reanalysis (static) → hindcast → forecast.

## Questions for PacIOOS

- Are the files on disk the same z-level regular-grid product THREDDS serves, or does
  THREDDS/NcML reshape native ROMS output?
- File sizes and compression; file granularity (per run? per day? per year for the
  reanalysis?).
- Would they accept 1a or 1b? Any usage policy or rate limit?
- For the forecast "best" series, which run should win where runs overlap?
