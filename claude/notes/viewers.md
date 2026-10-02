# The gridlook viewers

One `publish_viewer.py` builds gridlook once and publishes a copy beside each store. The
store lives in the URL *fragment*, which the host never sees, so a single build serves any
store. `PRODUCTS` is the only place a viewer is configured.

| Viewer | Prefix | Renders? |
|---|---|---|
| GOBAI-O2 | `fish-pace/gobai-o2/viewer/` | yes — Eli confirmed in a browser |
| OA indicators | `ocean-icechunks/oa-indicators/viewer/` | yes — Eli confirmed in a browser (2026-09-18) |
| CoastWatch OHC | `ocean-icechunks/noaa-ohc/viewer/` | metadata only in an ordinary browser — see CORS below; draws with a CORS extension (Eli, 2026-09-19) |
| NOAA OISST | `ocean-icechunks/noaa-oisst/viewer/` | yes, no extension — Eli, 2026-09-19. The store is not ours |

## CORS is the thing that decides whether a virtual store draws

A **materialized** store needs CORS on one host. A **virtual** store needs it on two,
because metadata comes from the repository and data from wherever the referenced bytes
live. That single difference explains every viewer above:

- `data.source.coop` — `access-control-allow-origin: *`, `Range` honoured, on GET and
  preflight. Never the problem.
- `www.ncei.noaa.gov` — sends `Access-Control-Allow-Origin: *` on ranged GETs. So the OA
  viewer draws — confirmed by Eli in a browser on 2026-09-18, not merely predicted from the
  headers. A plain `Range: bytes=a-b` is CORS-safelisted, so no preflight is involved; that
  also means a host can look bare on the preflight and still serve a browser perfectly well,
  so read the ranged GET as the verdict.

  This is the first virtual store here confirmed to render end to end, across two hosts. It
  and the CoastWatch row below are now cited in the `virtual-icechunk` skill, which until
  2026-09-18 told agents that no virtual store had ever rendered in a browser.
- `coastwatch.noaa.gov` — serves ranged GETs (206, `Accept-Ranges: bytes`) and sends **no**
  `Access-Control-Allow-Origin`, on the GET or the preflight. The OHC viewer therefore loads
  metadata and coordinates, which are real chunks in the repo, and the browser blocks every
  science array.

Enforcement is in the browser, not the page, so nothing published can waive it — a CORS
extension is a local override that cannot be shipped. The OHC viewer is published anyway at
Eli's call: it renders for anyone running such an extension, and is in place for the day
CoastWatch sends the header (one Apache directive, no rebuild — the manifests do not change).
The alternative, proxying the source and rebuilding every store against the proxy prefix,
means re-serving NOAA bytes through infrastructure we would have to run.

- `noaa-cdr-sea-surface-temp-optimum-interpolation-pds.s3.amazonaws.com` (OISST) — an S3
  bucket with a CORS configuration (`AllowedOrigin *`, readable at `/?cors`), so the OISST
  viewer draws. The references there are `s3://` URLs; icechunk-js rewrites them to HTTPS.

## What `publish_viewer.py` guards against

All four viewers were rebuilt on 2026-09-19 from gridlook `b3c42b1` (114 files, 24.8 MB);
the OA viewer prefix holds 102 objects.

- **A stale gridlook checkout.** `build()` fetches and exits if `~/gridlook` is behind its
  remote (`--allow-stale` overrides); `build-info.json` records `gridlook_behind_remote` and
  the Node version.
- **No default store.** With no `#…` fragment gridlook opens its hard-coded demo (an OGS
  Mediterranean store, `DEFAULT_DATASET` in `HashGlobeView.vue`). `write_default_store` injects a one-line script into the published
  `index.html` that sets the hash to the product's first store. Build output only; the
  lasting fix belongs in the gridlook fork.
- **A missing `catalog`.** One `--dist` is reused across products, so a product without one
  publishes whatever the dist last held.
- **Per-store `variables`.** A store entry may override the product's list: noaa-oisst's
  `daily` group has `sst` where `monthly` has `sst_mean`.

## Rebuilt 2026-09-19: what went wrong with the first builds

- **Stale clone.** All 2026-09-17 builds came from `~/gridlook` at `2649e66`, 98 commits
  behind `eeholmes/gridlook` — no log10 transform, no swatch fix, no CORS pop-up. The clone is
  per machine and that work was done on another hub. `publish_viewer.py` now fetches and
  refuses a checkout behind its remote. `~/gridlook-xl` is old and irrelevant.
- **Wrong default.** No `#…` fragment means gridlook's hard-coded demo dataset.
  `write_default_store` injects a default hash into the published `index.html`.
- **No catalog for gobai-o2**, so its picker listed 70 demo datasets; with a shared `--dist`
  it could have been another product's stores. Every product needs a `catalog`.
- **Caching.** After republishing, the old page can persist in a browser for hours: Source
  Cooperative does not echo `Cache-Control` for `index.html`, and serves JS with
  `max-age=14400`. curl the server, then hard-reload. A self-refresh check against
  `build-info.json` was offered to Eli and not taken up.

## Link the repository root, not a group

`…/noaa-ohc/na/` is the whole link. gridlook's `splitIcechunkStoreAndGroup` walks a URL back
segment by segment until one opens as a repository root, then offers the groups
(`daily`/`14day_v1`/`14day`) and their variables as dropdowns. Naming a group or a `varname`
only freezes a choice the viewer already presents — which is why OHC has three links and not
thirty-six.

CLAUDE.md used to claim the opposite, that groups meant a link needed more than a store URL.
That was wrong and is corrected; do not re-derive it.

OISST is the exception: its two groups are different products with different variable names,
so each group is its own store entry with its own `variables` (`.../oisst.icechunk/daily`,
`.../oisst.icechunk/monthly`) and gridlook resolves the group from the path.

`variables` in `PRODUCTS` is therefore optional. `gobai-o2` sets it because its README offers
a link per variable; `noaa-ohc` does not.

## The catalog is `catalog-extended.json`, and it goes in the build output

`HashGlobeView.vue` sets `DEFAULT_CATALOG = "static/catalog-extended.json"`.
`static/catalog.json` is **never read** unless a link passes `::catalog=<url>` — editing it
changes nothing on screen.

gridlook ships 70 unrelated demo datasets in the extended file, so `write_catalog` in
`publish_viewer.py` writes a product-specific replacement **into the dist** at publish time,
driven by the `catalog` key in `PRODUCTS`. Never into the gridlook checkout: that would bake
one product's catalog into every other product's viewer and stamp the build
`gridlook_dirty`, leaving the published copy matching no commit. A catalog entry's `url`
becomes the location hash verbatim, so it carries the camera with it.

## Camera state

`px`, `py`, `alt`, `lat`, `lon` and `dimIndices_<dim>` ride in the same fragment — see
`STORE_PARAM_MAPPING` in gridlook's `paramStore.ts`. Stores covering different parts of the
globe need different centres; `_OHC_BASINS` holds the three CoastWatch ones.

Dragging the globe rewrites the address bar, so **a good opening view is obtained by
positioning and copying, not by computing one.** `alt` especially: `95910936` frames a basin
100° wide in longitude, and nothing here can check what a wider one needs.

## Other gridlook facts worth keeping

- **No time dimension is required**, but every time path is gated on a dim literally named
  `time`. Spatial dims must be the trailing two, and `dimension_names` must be in the Zarr
  metadata. It ranks the coordinate name `lat` above `latitude`, which is why the OA store
  uses the short spelling.
- **Build with `vite build --sourcemap false` and a capped heap.** `npm run build` adds
  `vue-tsc` and source maps and gets OOM-killed on a small machine.
- **README nav rows are plain markdown links, not centered HTML.** GitHub allows
  `<p align="center">`, but Source Cooperative renders the README through its own pipeline
  and serves the raw file as plain text, so HTML is a gamble in two places out of three.
- Node: gridlook's `package.json` asks for Node >= 24.16; the 2026-09-17 build ran fine on
  the image's Node 20.19.6. Build with `vite build --sourcemap false` and a capped heap —
  `npm run build` adds `vue-tsc` and source maps and gets OOM-killed on a small machine.

## Source Cooperative as a static host

What Source Cooperative does and does not do for a static site (checked 2026-09-17):

- **CORS is wide open** — `access-control-allow-origin: *`, all headers exposed, `Range`
  honoured, on GET and on the OPTIONS preflight. A viewer served anywhere can read a store.
- **Content types are served as uploaded, never inferred.** An upload without
  `ContentType` comes back `binary/octet-stream`, and a browser refuses an ES module or a
  wasm blob served that way. `publish_viewer.py` sets the type for every extension.
- **No directory index.** `…/viewer/` returns **400**; links must name `index.html`.
- **The edge 403s the default `Python-urllib` User-Agent.** Any check from Python has to
  send its own; `curl` and boto3 are unaffected. This looks exactly like a permissions
  failure and is not one.
- `Cache-Control` is accepted on upload but not echoed back on GET.

Two details from the old CLAUDE.md section: `mode: "no-cors"` is no workaround, since it
returns an opaque response the page may not read; and Source Cooperative drops the
`Cache-Control: no-cache` uploaded with `index.html` and sends only `Last-Modified`, which is
why browsers cache the page heuristically.
