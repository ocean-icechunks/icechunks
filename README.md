# icechunks — various

Jupyter notebooks that publishocean datasets as
**[Icechunk](https://icechunk.io) repositories** on
[Source Cooperative](https://source.coop), anonymously readable with `xarray`.

Three datasets, built two different ways:

- **NOAA CoastWatch Ocean Heat Content**, in `coastwatch-heat-content/` — **virtual
  references**. The source NetCDF/HDF5 files stay at CoastWatch and Icechunk stores only
  Zarr metadata plus byte-range pointers back to them, via
  [VirtualiZarr](https://virtualizarr.readthedocs.io). Nothing copies the science arrays,
  so a store of a multi-terabyte archive is megabytes of metadata.
- **GOBAI-O2 v2.3 monthly**, in `gobai-o2-monthly/` — **materialized**. Real Zarr v3
  chunks written with `Dataset.to_zarr`, self-contained and independent of the source.
  Its source is one 12 GB contiguous, uncompressed NetCDF at NCEI with no chunk
  boundaries worth referencing, which is exactly the case where virtualizing buys nothing.
- **Ocean acidification indicators, North American margins**, in `oa-indicators/` —
  **virtual references**. NCEI ships one NetCDF per indicator; this merges twelve of them
  into a single store of 72 variables on one grid. The whole store is 35 kB of metadata
  pointing at 82 MB that stays at NCEI.

A fourth directory documents a store this repository does not build:

- **NOAA OISST v2.1**, in `noaa-oisst/` — a **README and a viewer only**. The store at
  `ocean-icechunks/noaa-oisst` is built and updated about daily by NERACOOS / GMRI
  ([ocean-icechunks/noaa_oisst](https://github.com/ocean-icechunks/noaa_oisst)): a virtual
  `daily` group referencing NOAA's Climate Data Record files on AWS, and a materialized
  `monthly` group of statistics.

## The published stores

Public, anonymously readable, no account needed:

| Dataset | Icechunk repository | Kind |
|---|---|---|
| CoastWatch OHC — North Atlantic | `https://data.source.coop/ocean-icechunks/noaa-ohc/na` | virtual |
| CoastWatch OHC — North Pacific | `https://data.source.coop/ocean-icechunks/noaa-ohc/np` | virtual |
| CoastWatch OHC — South Pacific | `https://data.source.coop/ocean-icechunks/noaa-ohc/sp` | virtual |
| GOBAI-O2 v2.3 monthly, 2004–2024 | `https://data.source.coop/fish-pace/gobai-o2/monthly` | materialized |
| OA indicators, North American margins | `https://data.source.coop/ocean-icechunks/oa-indicators/climatology` | virtual |

All three have a **browser viewer** — [gridlook](https://github.com/eeholmes/gridlook),
published beside the data by `publish_viewer.py`. The store to open lives in the URL
fragment, so one build serves any store, and a group is just the last path segment:

- **GOBAI-O2** — [open `oxy` on the globe](https://data.source.coop/fish-pace/gobai-o2/viewer/index.html#icechunk+https://data.source.coop/fish-pace/gobai-o2/monthly::varname=oxy).
  No install, no account, nothing to configure.
- **CoastWatch OHC** — [open the North Atlantic on the globe](https://data.source.coop/ocean-icechunks/noaa-ohc/viewer/index.html#icechunk+https://data.source.coop/ocean-icechunks/noaa-ohc/na/::px=0::py=0::alt=95910936::lat=25.0562::lon=-47.2424::dimIndices_time=0),
  **but the data will not draw in an ordinary browser**. These stores are virtual, so the
  science arrays come from `coastwatch.noaa.gov`, which sends no CORS headers and is
  therefore blocked by the browser. It renders with a CORS-disabling browser extension;
  see [the viewer section of its README](coastwatch-heat-content/README.md#view-it-in-a-browser).
  Nothing on our side can fix this — only CoastWatch serving the header would.
- **OA indicators** — [open aragonite saturation state on the globe](https://data.source.coop/ocean-icechunks/oa-indicators/viewer/index.html#icechunk+https://data.source.coop/ocean-icechunks/oa-indicators/climatology::varname=OmegaA_an::px=0::py=0::alt=95910936::lat=48::lon=-110::dimIndices_depth=0).
  Also a virtual store, but this one *does* draw: `www.ncei.noaa.gov` sends
  `Access-Control-Allow-Origin: *` where CoastWatch sends nothing. The **Depth** slider
  moves through the 14 levels.

Each CoastWatch region is a separate repository — the three use different lat/lon grids
and cannot share a virtual array. Each holds three groups (`daily`, `14day_v1`, `14day`)
covering different generations and encodings of the product.

Full documentation of each dataset, and how to read it, is in the product README —
**[`coastwatch-heat-content/README.md`](coastwatch-heat-content/README.md)**,
**[`gobai-o2-monthly/README.md`](gobai-o2-monthly/README.md)** and
**[`oa-indicators/README.md`](oa-indicators/README.md)** — each of which is also
published alongside its store.

## Quick start

> **icechunk 1.x will not work.** `icechunk.http_storage` does not exist in icechunk 1.x
> (it arrived in 2.0), and `icechunk.credentials.HttpAccess` arrived in 2.1. Every icechunk
> 2.x release needs **Python 3.12 or newer**, so on an older Python `pip install icechunk`
> quietly installs 1.1.x, and the code below fails with
> `AttributeError: module 'icechunk' has no attribute 'http_storage'`. Check what you have:
> `python -c "import icechunk; print(icechunk.__version__)"`.

```python
import icechunk
import xarray as xr

url = "https://data.source.coop/ocean-icechunks/noaa-ohc/na"
repo = icechunk.Repository.open(icechunk.http_storage(url))

# The arrays live at CoastWatch, outside the store, so authorize the virtual
# chunk container at open time — this is the one non-standard step.
auth = {p: icechunk.credentials.HttpAccess for p in repo.config.virtual_chunk_containers or []}
store = repo.reopen(authorize_virtual_chunk_access=auth).readonly_session("main").store

ds = xr.open_zarr(store, group="14day", consolidated=False, chunks={})
print(ds)
```

A materialized store needs no such authorization — the chunks are inside it:

```python
url = "https://data.source.coop/fish-pace/gobai-o2/monthly"
repo = icechunk.Repository.open(icechunk.http_storage(url))
ds = xr.open_zarr(repo.readonly_session("main").store, consolidated=False, chunks={})
print(ds)
```

## Repository layout

```text
coastwatch-heat-content/
  README.md                        data documentation, mirrored to the stores
  ocean-heat-test-local.ipynb      minimal proof of concept, writes locally, no credentials
  ocean-heat-test-sc.ipynb         minimal proof of concept, writes to Source Cooperative
  ocean-heat-production-sc.ipynb   the full pipeline that built all three region stores
  requirements.txt                 dependency floors for those notebooks
gobai-o2-monthly/
  README.md                        data documentation, mirrored to the store
  gobai-o2-monthly-icechunk-sc.ipynb   the pipeline that built the GOBAI-O2 store
  requirements.txt                 dependency floors for that notebook
oa-indicators/
  README.md                        data documentation, mirrored to the store
  oa-indicators-icechunk-sc.ipynb  the pipeline that built the OA-indicators store
  requirements.txt                 dependency floors for that notebook
icechunk_utils.py                  Source Cooperative credential and repo helpers
publish_viewer.py                  builds gridlook and publishes it beside a store
claude/                            working notes for AI coding agents
```

## Installing

Each pipeline declares its own floors, because they need different things — the
CoastWatch notebooks pull in VirtualiZarr, kerchunk and obstore, and the GOBAI-O2
notebook needs none of them:

```bash
pip install -r coastwatch-heat-content/requirements.txt   # CoastWatch (virtual)
pip install -r gobai-o2-monthly/requirements.txt          # GOBAI-O2 monthly (materialized)
pip install -r oa-indicators/requirements.txt             # OA indicators (virtual)
```

**Python 3.12 or newer is required** — every `icechunk` 2.x release is published
`requires_python = ">=3.12"`. Use pip, not conda; the environment will not solve.

Reading the published stores needs only `icechunk` and `xarray`. Re-running the CoastWatch
write notebooks additionally needs Source Cooperative write credentials, so for most
readers they are read-along references. `gobai-o2-monthly-icechunk-sc.ipynb` is the
exception: it runs end to end with no credentials and writes nothing unless you set
`RUN_WRITE = True`.

## Related

- **[`virtual-icechunk` skill](https://github.com/ocean-icechunks/ocean-icechunks-skills)** — shared
  guidance for building, validating and auditing virtual Icechunk stores.
- Sibling repositories apply the same pattern to NOAA CEFI, PACE, RFROM / GOBAI HR and
  Copernicus GlobColour data. In particular
  [`nmfs-opensci/gobai-rfrom-icechunks`](https://github.com/nmfs-opensci/gobai-rfrom-icechunks)
  publishes RFROM and **GOBAI HR** — a different, weekly, higher-resolution GOBAI product
  on NOAA NODD, not to be confused with the GOBAI-O2 v2.3 monthly store here.

## Reuse and citation

**Code.** Released under [Apache License 2.0](LICENSE). Use it, copy it, adapt it, and
redistribute it, commercially or not — you do not need to credit us, cite us, or ask
permission. (Apache-2.0 asks that you keep the license and copyright notice with copies you
redistribute; we ask for nothing beyond that.)

**Data.** None of the data is ours, and each dataset carries its own terms — follow the
source, not this repository:

- **CoastWatch OHC** — the stores contain no science arrays at all, only references to
  files hosted by NOAA CoastWatch. The Satellite Ocean Heat Content Suite is produced by
  USDOC/NOAA/NESDIS/OSPO with the University of Miami / Rosenstiel School. See the
  [product page](http://www.ospo.noaa.gov/Products/ocean/ocean_heat.html) and the
  [Credits](coastwatch-heat-content/README.md#credits) section of its documentation.
- **GOBAI-O2 v2.3** — released by its authors under CC0 1.0, so no legal obligation to
  cite; scholarly practice still asks that you do. Citations are in
  [`gobai-o2-monthly/README.md`](gobai-o2-monthly/README.md#reuse-and-citation).
- **OA indicators** — again the store holds no science arrays, only references to NCEI's
  files. NCEI states no use restrictions for accession 0270962; please cite it. The
  citation is in [`oa-indicators/README.md`](oa-indicators/README.md#reuse-and-citation).
