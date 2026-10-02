# Notebooks

Moved here from `AGENTS.md` (then `CLAUDE.md`) on 2026-10-02 to keep that file under
Antigravity's 24 KB rule limit. The safety-relevant summary stays there.

## Inventory (`gobai-o2-monthly/`)

One notebook, `gobai-o2-monthly-icechunk-sc.ipynb`, mirrored to the `gobai-o2/` root along with its
README and `requirements.txt`. It is guarded by two flags, both `False` in the committed copy:
`RUN_WRITE` (open credentials and rebuild the store) and `RUN_MIRROR` (upload the docs). With both
off it runs end to end with no credentials and writes nothing — opens the source, builds the
metadata and encoding, skips the write, then validates the published store against the source. The
committed outputs are from exactly that run (2026-09-17, 57 s, clean Python 3.12 venv).

## Inventory (`coastwatch-heat-content/`)

All three notebooks read the same source — NOAA CoastWatch OHC over HTTPS.

| Notebook | Icechunk destination | Mirrored to Source Coop? |
|---|---|---|
| `ocean-heat-test-local.ipynb` | Local filesystem — minimal proof of concept, no credentials needed | yes |
| `ocean-heat-test-sc.ipynb` | Source Coop — minimal proof of concept | **no, git only** |
| `ocean-heat-production-sc.ipynb` | Source Coop (`ocean-icechunks/noaa-ohc/{na,np,sp}`) | yes |

`ocean-heat-test-sc.ipynb` stays in git only: it needs write credentials, so it is no use
to a reader who just found the stores, and `ocean-heat-test-local.ipynb` shows the same
steps with none. It writes to `ocean-icechunks/test-repo/noaa-ohc` (the scratch repo at
<https://source.coop/ocean-icechunks/test-repo>), never to the published prefix, and its
clear cell is guarded by both a `RUN_CLEAR` flag and a `PROTECTED` set that refuses any
prefix holding a published archive. It carries no saved outputs by design — it is a
template of the steps. Last run end to end on 2026-09-17 (five files, five commits, reopened
and read back) in a clean 3.12 venv.

`ocean-heat-test-local.ipynb`, by contrast, **does** carry its outputs: it needs no
credentials and writes only to a local directory, so its committed run is the cheapest proof
that the whole virtual pattern works. Re-executed 2026-09-17 in the same clean venv — three
2026 files virtualized and appended in about 1 s each, then `ohc` read back through its
virtual references. The local repo it writes (`coastwatch-ohc-http-icechunk-demo/`) is
gitignored.

## The `noaa-ohc/` root mirror

The `noaa-ohc/` **root** (alongside the `na/`/`np/`/`sp/` repo subfolders) also holds the human-facing docs, mirrored from git: `README.md`, `requirements.txt`, `icechunk_utils.py`, `ocean-heat-production-sc.ipynb` and `ocean-heat-test-local.ipynb` — five files, **not** `ocean-heat-test-sc.ipynb` (see the inventory above). These are reference/reproducibility copies; keep them in sync when the git versions change. The last cell of `ocean-heat-production-sc.ipynb` uploads the set; `icechunk_utils.py` comes from the repo root via `../`, flattened onto the destination root by `path.name`, while `requirements.txt` now sits beside the notebooks. The `viewer/` prefix alongside them is the gridlook build, published by `publish_viewer.py`, and is not part of the notebook's mirror set.
