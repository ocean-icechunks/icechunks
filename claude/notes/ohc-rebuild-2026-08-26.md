# The OHC rebuild run of 2026-08-26

What `coastwatch-heat-content/ocean-heat-production-sc.ipynb` did when it was run
against the re-pointed destination. Recorded here because the run's own outputs are
the only record of it, and because a future session will want the numbers without
re-reading an 8,000-line notebook diff.

## Outcome

All three regions created fresh and all nine groups committed. Snapshot IDs:

| Region | `daily` | `14day_v1` | `14day` |
|---|---|---|---|
| na | `MTX96KFAXWK8YAA3Q7D0` | `QYPAXMCF02RPMMT4W34G` | `PD810W3C6EZ7V5Y5094G` |
| np | `4NTNW1MBNBQJ8T9RK9RG` | `9ZQWP771C8674RN5CDK0` | `F29D3QM6P7G56RH3ZMYG` |
| sp | `4KBSV8WSD3KVSG5M0A00` | `JJF5SHVNEEZ11EQTWJH0` | `MCV4SVX7J65PRQ15DY2G` |

Grids, which are why the regions cannot share a repo:

- na — lat 0.0..60.0 (241), lon -100.0..0.0 (401)
- np — lat 0.0..60.0 (241), lon 100.0..280.0 (721)
- sp — lat -60.0..0.0 (241), lon 130.0..290.0 (641)

## Budget a full rebuild at ~2.5 hours

Per-group open times from the run: na 1835s / 428s / 1797s, np 658s / 243s / 1208s,
sp 861s / 232s / 1211s — about 2h21m of wall clock, and the na `daily` group alone
is half an hour. The notebook prints "Time remaining on token" at each region; it
started with 11:56 left and finished with roughly 9h30m, so a `--duration 1d` token
is ample and a short one is not. Do not start a rebuild on a token about to expire —
a group that dies mid-write leaves the repo without that group's commit.

## The corrupt-file drops are source-side

`open_region` opens each source file and drops the ones that fail, printing a count:
na `14day` dropped 6, np `daily` dropped 1, np `14day_v1` dropped 21, everything else
zero. This is why the region time-step counts do not match the file counts the scrape
cell reports (na `14day`: 513 files scraped, 507 steps written).

**This is deliberate, not a bug to chase.** The bad files are in the CoastWatch
archive. The verification cells assert the codec boundary and variable sets *after*
the drops, and they passed. If a future run shows a large jump in drops for a group
that was previously clean, that is worth investigating; the standing counts above are
not.

## What went wrong around the run, rather than in it

The run succeeded on 2026-08-26 and then nothing was committed for three weeks. The
work looked unfinished from `main` — CLAUDE.md said "in progress", the notebook on
`main` had no outputs — while the repos had in fact been live the whole time. PR #12
committed the executed notebook for exactly this reason. If a production notebook is
run, commit it the same day; the outputs are the build log.

## Coverage as built

First built under `fish-pace/coastwatch/ocean-heat/{na,np,sp}` (PRs #3–#6); the destination
re-point to `ocean-icechunks/noaa-ohc` landed in PR #8. The 2026-08-26 rebuild executed
`ocean-heat-production-sc.ipynb` end to end, committed all nine groups, and passed the
boundary / variable-set / codec-homogeneity assertions.

2020-04-30 → 2026-08-26, from the executed notebook's outputs:

| Region | `daily` | `14day_v1` | `14day` | Corrupt files dropped |
|---|---|---|---|---|
| na | 1357 | 430 | 507 | 6 (`14day`) |
| np | 1356 | 390 | 513 | 1 (`daily`), 21 (`14day_v1`) |
| sp | 1349 | 411 | 513 | none |

Corrupt source files are dropped by design (`open_region` counts them); the per-region counts
differ because the bad files are in the source archive, not in our handling of it.
