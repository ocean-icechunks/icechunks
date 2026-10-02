# Handoff — icechunks

Rolling state for this repo. Orientation only: the open threads below are a record of what
is unfinished, not a task list.

## Where things stand (2026-09-19)

Three datasets built, published and documented on Source Cooperative — each with a README,
its own `requirements.txt`, its notebooks mirrored to its store root, and a gridlook viewer —
plus a README and viewer for a fourth store that someone else builds.

| Dataset | Store | Kind | Viewer |
|---|---|---|---|
| CoastWatch OHC | `ocean-icechunks/noaa-ohc/{na,np,sp}` | virtual | CORS-blocked at the source; draws with a CORS extension — Eli, 2026-09-19 |
| GOBAI-O2 v2.3 monthly | `fish-pace/gobai-o2/monthly` | materialized | renders — confirmed by Eli |
| OA indicators | `ocean-icechunks/oa-indicators/climatology` | virtual | renders — confirmed by Eli, 2026-09-18 |
| NOAA OISST v2.1 | `ocean-icechunks/noaa-oisst/oisst.icechunk` | **not ours** — built by NERACOOS/GMRI; `daily` virtual, `monthly` materialized | renders in an ordinary browser — Eli, 2026-09-19 |

- **CoastWatch OHC** — three repos, one per region grid, three groups each (`daily`,
  `14day_v1`, `14day`), covering 2020-04-30 → 2026-08-26. The only **growing** source here,
  and so the only one needing an update pipeline; see Open threads.
- **GOBAI-O2 v2.3** — arrived 2026-09-17 from `nmfs-opensci/gobai-rfrom-icechunks`. Finished
  archive version, static. [notes/gobai-o2-monthly.md](notes/gobai-o2-monthly.md)
- **OA indicators** — NCEI accession 0270962, built in PR #24. Twelve NetCDFs merged into one
  flat group of 72 variables; 84 objects and 35 kB referencing 82 MB left at NCEI. Finished
  accession, static. [notes/oa-indicators.md](notes/oa-indicators.md)

- **NOAA OISST** — README and viewer only (PR #30, 2026-09-19); the store is Alex Kerney's
  (`ocean-icechunks/noaa_oisst`) and updates about daily. Never write under
  `noaa-oisst/oisst.icechunk/`. Two problems found while documenting it were reported as
  ocean-icechunks/noaa_oisst#2: `daily/time` is 16,452 one-value chunks (a 7 s open), and the
  `monthly` metadata is copied from `daily` (wrong `long_name`s, `valid_max` not rescaled for
  `err_*`/`ice_*`, no group attributes). PR #31 (2026-09-19) corrected the README's claim that
  every monthly variable uses `scale_factor` 0.01 — `err_*` and `ice_*` use 0.001 — and the
  corrected README was re-mirrored and checked by checksum.

**Before running anything:** the kernel env is Python 3.11 and `icechunk` 2.x requires
>= 3.12, so it cannot be installed there. A 3.12 venv works — recipe and traps in
[notes/environment.md](notes/environment.md). Build venvs in the scratchpad and install with
`--no-cache-dir`: `~` has a 20 GiB quota and little headroom
([notes/home-quota.md](notes/home-quota.md)).

## Working principles

- **The notebook outputs *are* the build log.** No separate log exists. Commit executed
  production notebooks; an uncommitted or stripped run erases the record of that build.
- **Verify the destination, not just the notebook.** "Committed" means the write path
  returned, not that the public read path works —
  [notes/verifying-published-repos.md](notes/verifying-published-repos.md).
- **Verify transport here, rendering with Eli.** There is no browser on the hub. Check status
  codes, content types and CORS, then ask.
- **Mirror only from merged `main`**, then check by checksum. Uploading from a branch is how
  the published copies drift.
- **This image ships more than we declare.** Anything that must work for a stranger gets
  tested in a clean venv, not in the kernel env.
- **Nothing copies array bytes.** Every pipeline but GOBAI-O2 is virtual references into
  files that stay at the source.
- **Use `git worktree` for anything substantial.** Concurrent sessions share this checkout.
- **Store READMEs use the standard format, and carry the "icechunk 1.x will not work" note**
  — both described in AGENTS.md under "Store READMEs".
- **Rebuild viewers only from a current gridlook, and expect to hard-reload.** AGENTS.md,
  "The browser viewer", and [notes/viewers.md](notes/viewers.md).

## Recently shipped (2026-09-17, PRs #12–#19, #23–#26)

A full repo audit and its fixes; GOBAI-O2 moved in and made reproducible; the OA-indicators
store built; viewers published for all three products; CoastWatch brought up to the same
standard (README, per-product `requirements.txt`, notebooks verified by running them in a
clean venv). Two notebook bugs were found that way — a vacuous validation in the GOBAI
notebook, and `ocean-heat-test-sc.ipynb` failing on any re-run until the first write was
given `mode="w"`.

## Recently shipped (2026-09-19, PRs #28–#31)

All viewers rebuilt from a current gridlook after the 2026-09-17 builds turned out to be 98
commits stale; `publish_viewer.py` gained the stale-checkout guard, the default-store script,
a catalog for gobai-o2 and per-store variables. Every README got the "icechunk 1.x will not
work" note. The three README mirrors, stale since the move to `ocean-icechunks/icechunks`,
were refreshed and checked by checksum (READMEs only — the other mirrored files were not
compared). NOAA OISST got a README and a viewer.

## Open threads

- Watch ocean-icechunks/noaa_oisst#2 for the maintainers' reply; if the store is fixed, the
  OISST README's caveats and its 7 s open time need revisiting and re-mirroring. Eli's
  cross-repo to-do list from 2026-09-19 is in `~/hycom/claude/notes/todo.md`.
- **`git pull` fails in this checkout** with "Cannot rebase onto multiple branches"; use
  `git fetch origin && git merge --ff-only origin/main`. Cause not investigated.

- **Auto-update pipeline for CoastWatch — undesigned, and the only substantial work left.**
  `write_group` skips groups that already exist, but nothing appends *new time steps* to an
  existing group. Until that path and a trigger exist the stores stay frozen at the last
  manual run and drift behind the archive.
- **`np` and `sp` viewer links share `na`'s `alt`** and may open too tight. Needs two numbers
  from a browser: drag each globe, copy the URL, update `_OHC_BASINS` in `publish_viewer.py`.
- **The docs mirror has no committed tooling.** The only committed path is the last cell of
  `ocean-heat-production-sc.ipynb`, which means a 2.5-hour rebuild first, so 2026-09-17's
  mirrors used a throwaway scratchpad script. Worth a committed `mirror_docs.py` beside
  `publish_viewer.py`. That cell also passes **no `ContentType`**, and Source Cooperative
  serves types as uploaded — a full rebuild could downgrade all five files to
  `binary/octet-stream`.
  The README mirrors went stale once already (the move to `ocean-icechunks/icechunks`) and
  were refreshed by hand on 2026-09-19 with another throwaway script — the second call on
  that missing tooling.
- **Cosmetic:** the production notebook's kernel metadata records Python 3.11.14 (from being
  opened, not run); the test notebooks say 3.12.12, which is the truthful one.
- `ocean-icechunks/test-repo/{noaa-ohc,oa-indicators}` hold objects from verification runs,
  deliberately left as worked examples.

## Notes

- [environment.md](notes/environment.md) — the 3.12 venv recipe and its traps
- [home-quota.md](notes/home-quota.md) — the 20 GiB quota, how to measure it, what fills it
- [verifying-published-repos.md](notes/verifying-published-repos.md) — checking a store over HTTPS
- [viewers.md](notes/viewers.md) — gridlook, CORS on two hosts, catalogs, camera state, Source Cooperative hosting
- [notebooks.md](notes/notebooks.md) — what each notebook does, what is mirrored, last runs
- [gobai-o2-monthly.md](notes/gobai-o2-monthly.md) — what that cleanup found
- [oa-indicators.md](notes/oa-indicators.md) — what that build found
- [ohc-rebuild-2026-08-26.md](notes/ohc-rebuild-2026-08-26.md) — the CoastWatch rebuild record
