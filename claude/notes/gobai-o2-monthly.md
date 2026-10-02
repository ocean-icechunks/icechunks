# GOBAI-O2 monthly — what the cleanup found

The store (`fish-pace/gobai-o2/monthly`, materialized) was built 2026-08-06 and is static:
v2.3 is a finished archive version, so there is no update pipeline to write. A later GOBAI
version would be a new store. What follows is worth knowing before touching it or writing a
similar one.

- **The validation was vacuous.** The reopen cell rebound `ds` from the source to the
  published dataset, so every assertion after it compared the store with itself. Renamed to
  `published`. Look for this shape in any notebook that validates in place.
- **Never sample a contiguous, uncompressed source through dask chunks.** 81 scattered
  points read at `chunks=(14, 2, 73, 120)` took 11m41s; `chunks=None` for the sample took
  the whole notebook to 57 s. The source has no chunks, so every dask chunk is thousands of
  strided range requests.
- **NCEI's download button is broken, the data is not.** `/archive/accession/download/…`
  302-loops; the archive filesystem path under `/data/oceans/archive/arc0207/0259304/5.5/`
  serves the 12 GB file directly and honours range requests, so `engine="netcdf4"` with a
  `#mode=bytes` suffix streams it.
- **A metadata-only fix to a published store is cheap.** The `license` attribute said
  CC BY 4.0; GOBAI-O2 is CC0 1.0. `zarr.open_group(session.store, mode="r+").attrs.put(...)`
  plus a commit rewrote no chunks — snapshot `3A41NX29VSPEXA94ES9G`.
- An aborted `Repository.create` had left an empty repo at the `gobai-o2/` **root** prefix
  (repo + one snapshot + one transaction, no refs). Deleted. Watch for this whenever a
  prefix is corrected after a first create.

## Build record

Materialized store at `fish-pace/gobai-o2/monthly`, built 2026-08-06: snapshot
`8DKFSNN3G386BXJS8X6G`, tag `v2.3`, 12,858 objects, 5.59 GB, chunks `(14, 2, 73, 120)`.
Snapshot `3A41NX29VSPEXA94ES9G` (2026-09-17) is the metadata-only `license` fix to CC0 1.0.
The notebook arrived from `nmfs-opensci/gobai-rfrom-icechunks` on 2026-09-17; its first commit
here is the unmodified original, so the 2026-08-06 build outputs are in the history.

## Gotchas

Moved here from `AGENTS.md` on 2026-10-02.

- **NCEI's landing-page download button is broken** — `/archive/accession/download/0259304` 302-loops.
  The archive filesystem path works and honours range requests:
  `https://www.ncei.noaa.gov/data/oceans/archive/arc0207/0259304/5.5/data/0-data/GOBAI-O2-v2.3.nc`
  (12,207,313,813 bytes). Do not conclude NCEI is down from the button alone.
- **`engine="netcdf4"` plus a `#mode=bytes` URL suffix streams the source**, no download. h5netcdf
  cannot do this. Opening takes ~6 s, one `(lat, lon)` plane ~1 s.
- **Never sample a contiguous, uncompressed source through dask chunks.** Comparing 81 scattered
  points with the source opened at `chunks=(14, 2, 73, 120)` took **11m41s**, because each point
  drags in a whole chunk and a chunk is thousands of strided range requests. Re-opening the source
  with `chunks=None` for the sample made the same notebook run take **57 s**.
- **The `license` attribute was wrong in the first build** (CC BY 4.0). GOBAI-O2 ships CC0 1.0;
  NCEI distributes the text as `GOBAI-O2-v2.3-license.txt` beside the data. Fixed by opening a
  writable session, `zarr.open_group(...).attrs.put(...)` and committing — a metadata-only commit
  rewrites no chunks and takes seconds.
- **Longitudes run 20.5 → 379.5**, not 0–360. That is the source grid; it is kept as is.
