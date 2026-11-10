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

## Chunking — will the files need reprocessing? (2026-11-10)

Test file: one day (8 steps) of `roms_hiig_reanalysis`, all four 3-D variables, from ERDDAP
`.nc` (265 MB in 261 s, ~1.0 MB/s), plus the `_ssh` day (1.9 MB in 3 s).

**What ERDDAP gives:** NetCDF-3 classic, `time` a *fixed* dimension (not UNLIMITED). So each
variable is one contiguous, uncompressed block of `(ntime, 36, 195, 295)`, with no
interleaving between variables. It carries over the source's `_ChunkSizes` attribute, but that
attribute describes nothing in this file. ERDDAP renames `lat`/`lon` to
`latitude`/`longitude` (the native names are `lat`/`lon`, which gridlook prefers) and
re-encodes time as seconds since 1970 (natively hours since 2000-01-01).
`_FillValue = 9.96921e36` and `Conventions = "CF-1.6, ACDD-1.3"`. About 10% of the cells are
NaN: by depth level, 56,407 of 57,525 are wet at the surface, 55,377 at level 20 and 211 at
5500 m.

**What the native files have (from THREDDS):** HDF5, chunk `(1, 36, 195, 295)` = 8.3 MB raw.
`salt` shows **two `_FillValue` attributes** in the THREDDS DAS (9.96921e36 and NaN), a
source-metadata quirk to check in the real file.

**Either way, it is one time step per chunk.** That suits maps: gridlook or a forecast map
of one step reads 8.3 MB per variable. It is bad for time series: a point series through the
reanalysis touches all 35,040 chunks, ~290 GB per variable. GOBAI was reprocessed for the
same reason, to `(100, 1, 180, 180)`.

Conclusion:

- **Forecast (and probably the hindcast): no reprocessing.** Use virtual references
  over the native files as they are. People use these as maps, and data arriving daily one
  run at a time cannot be time-chunked anyway.
- **Reanalysis: reprocess if time-series users matter.** It is static and gets used for
  climatologies and point series. A candidate is `(240, 1, 98, 148)`: a month × one level ×
  a quarter of the grid, ~14 MB raw, ~7 MB compressed. A point series then reads 146 chunks,
  ~1 GB, instead of 290 GB. In exchange, one map at one level reads 4 chunks (~28 MB) instead
  of 8.3 MB of a full-depth chunk. Unsettled: whether to also keep a map-chunked copy (2×
  storage), and the exact shape.
- **Virtualizing ERDDAP-downloaded files is possible but pointless.** References can be
  computed (HYCOM-style) into the contiguous blocks at `(1, 36, 195, 295)` or
  `(1, 1, 195, 295)`, but the data would sit uncompressed (~1.9× larger) with the same
  time-series problem. If we download through ERDDAP at all, write compressed Zarr directly.

## Moving the files to object storage (GCS) — estimates

The ~0.8 MB/s above is **THREDDS's per-request cost**: it reads the HDF5, decompresses and
re-encodes as OPeNDAP. A plain file copy (HTTPS `fileServer`, rsync, `gcloud storage cp` run
on their host) skips all of that and is limited by the network. That number has not been
measured; the estimates below are guesses until it is.

Volume (raw float32; roughly half if their files are deflated on disk):

| Set | Raw |
|---|---|
| Reanalysis 2009–2020 | ~1.2 TB |
| Hindcast 2015 → present | ~1.1 TB |
| Forecast, all 651 runs kept with overlaps | ~1.2 TB |
| Forecast, "best" series only | ~0.2 TB |
| 2-D `zeta`, all sets | ~0.1 TB |
| **Total** | **~2.5–3.5 TB** |

| Sustained rate | 1 TB | All (~3 TB) |
|---|---|---|
| 0.8 MB/s (today's OPeNDAP) | ~15 days | ~6 weeks |
| 10 MB/s (slow or shared link) | ~28 h | ~3.5 days |
| 100 MB/s (≈1 Gbps) | ~3 h | ~8–9 h |
| 500 MB/s (10 Gbps, parallel streams) | ~35 min | ~2 h |

UH is on Internet2, so hours to about a day for everything is the plausible range, provided the
copy runs on their host or uses parallel streams. A single trans-Pacific HTTPS stream often
tops out at tens of MB/s.

Routes, easiest first:

1. **They push**: `gcloud storage cp -r` / `rclone` from their server into a bucket we give
   them write access to. One hop, nothing exposed publicly.
2. **Storage Transfer Service, URL list**: needs `fileServer` on, with **public** URLs. GCS
   pulls them in parallel and checks each file's MD5. No VM needed.
3. **We pull from a GCP VM** (US-West) with `aria2c`/`rclone`, 8–16 streams. Ingress is
   free. Do not route through the hub (20 GiB home quota, shared machine).

Cost: ingress free; standard storage ~$20/TB-month (≈$60/month for everything), or nothing
in a NODD bucket.

To turn this table into a real estimate, time one ~2 GB forecast-run file over `fileServer`
(`curl -o /dev/null -w '%{speed_download}'`), or ask their sysadmin for the uplink speed.

## Turning `fileServer` on temporarily — risks

Raised 2026-11-10 as a 2–3 day window for the copy. The risks, roughly by likelihood:

- **Scrapers and bots.** THREDDS servers are crawled heavily, so direct whole-file
  downloads can saturate the link and slow the public forecast service. Mitigations: an
  Apache IP allowlist on `/thredds/fileServer/`, or keep `HTTPServer` out of the public
  catalog. Note that an allowlist is incompatible with route 2, since Google's
  transfer IPs are not fixed; use route 3 from a VM with a static IP instead.
- **Disk I/O contention** with the daily forecast job if the copy runs many streams.
  Cap the concurrency, or copy outside the ~1:30 PM HST update window.
- **Inconsistent copies.** A forecast run being written, or purged by the rolling window,
  during the copy gives a truncated or missing file. Copy completed runs only, and verify
  size/MD5 afterwards.
- **TDS 4.6 is long out of support.** Any extra endpoint on an unpatched server is extra
  attack surface. Their hidden-`location` setting suggests a deliberate policy, and
  `fileServer` URLs reveal the directory layout under the scan root (not absolute paths).
- **A temporary `fileServer` cannot back a virtual store.** Once it is turned off, any
  references into it break. A temporary window means *copy*, then build virtual against
  the bucket (option 1b), never virtual against PacIOOS.

Route 1 (they push) avoids every one of these, which makes it the first thing to ask for.

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
