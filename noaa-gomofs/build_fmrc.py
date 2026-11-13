#!/usr/bin/env python
"""Build or update a GoMOFS FMRC store: dims ``time`` (forecast cycle) x ``step`` (lead).

    python build_fmrc.py 3d --dest local:/path --start 2026-11-08 --end 2026-11-10
    python build_fmrc.py 2d --dest sc:                     # update: everything newer than the store

``3d`` = the ``fields`` files (3-hourly), ``2d`` = the ``2ds`` files (hourly).  Each cycle is
appended along ``time``; ``time`` is the forecast reference time (the cycle time) and ``step``
the forecast period from it.  A cycle with any file missing is skipped and reported.
"""
import argparse
import datetime as dt

import xarray as xr

import gomofs_common as g

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
ap.add_argument("variant", choices=g.FAMILIES)
ap.add_argument("--dest", required=True)
ap.add_argument("--start", type=dt.date.fromisoformat, default=None,
                help="first day (default: day of the newest cycle in the store, or 2024-11-07)")
ap.add_argument("--end", type=dt.date.fromisoformat, default=None, help="last day (default: today, UTC)")
ap.add_argument("--batch", type=int, default=4, help="cycles per commit (default 4 = one day)")
args = ap.parse_args()

name = f"fmrc-{args.variant}"
repo = g.open_repo(args.dest, name)
empty = len(list(repo.ancestry(branch="main"))) <= 1
last = None
if not empty:
    ro = repo.readonly_session("main").store
    last = xr.open_zarr(ro, consolidated=False, chunks=None).time.values.max()
    last = dt.datetime.utcfromtimestamp(int(last) / 1e9)
start = args.start or (last.date() if last else g.FIRST_DAY)
end = args.end or dt.datetime.now(dt.timezone.utc).date()

cycles, partial = g.list_cycles(args.variant, start, end)
cycles = {c: r for c, r in cycles.items() if last is None or c > last}
for c, r in partial.items():
    print(f"skipping incomplete cycle {c:%Y-%m-%d %Hz}: {len(r)}/{g.FAMILIES[args.variant]['per_cycle']} files")
print(f"{name}: {len(cycles)} new cycles ({start} -> {end}), store {'empty' if empty else 'last ' + str(last)}")

registry = g.make_registry()
todo = sorted(cycles)
for i in range(0, len(todo), args.batch):
    chunk = todo[i:i + args.batch]
    session = repo.writable_session("main")
    for cyc in chunk:
        ds = g.fmrc_dataset(cyc, cycles[cyc], registry)
        if empty:
            ds.vz.to_icechunk(session.store)
            empty = False
        else:
            g.for_append(ds, "time").vz.to_icechunk(session.store, append_dim="time")
    snap = session.commit(f"FMRC {args.variant}: cycles {chunk[0]:%Y-%m-%d %Hz} .. {chunk[-1]:%Y-%m-%d %Hz}")
    print(f"committed {snap} ({chunk[-1]:%Y-%m-%d %Hz})", flush=True)
