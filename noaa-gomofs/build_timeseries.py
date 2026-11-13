#!/usr/bin/env python
"""Build or update a GoMOFS monotonic-time store: one ``time`` dimension, valid times.

    python build_timeseries.py 3d --dest local:/path --start 2026-11-08 --end 2026-11-10
    python build_timeseries.py 3d --dest sc:               # update

Every cycle contributes its nowcast files (they tile the timeline without overlap); the newest
cycle also contributes its forecast.  An update trims the previous forecast tail (everything
after the previous newest cycle time) and appends the new cycles, so the store always ends with
the latest forecast.  The newest cycle time is kept in the root group attribute ``last_cycle``.
"""
import argparse
import datetime as dt

import numpy as np
import xarray as xr
import zarr

import gomofs_common as g

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
ap.add_argument("variant", choices=g.FAMILIES)
ap.add_argument("--dest", required=True)
ap.add_argument("--start", type=dt.date.fromisoformat, default=None)
ap.add_argument("--end", type=dt.date.fromisoformat, default=None)
ap.add_argument("--batch", type=int, default=400, help="files per commit")
args = ap.parse_args()

name = f"timeseries-{args.variant}"
repo = g.open_repo(args.dest, name)
empty = len(list(repo.ancestry(branch="main"))) <= 1
last = None
if not empty:
    root = zarr.open_group(repo.readonly_session("main").store, mode="r")
    last = dt.datetime.fromisoformat(root.attrs["last_cycle"])
start = args.start or (last.date() if last else g.FIRST_DAY)
end = args.end or dt.datetime.now(dt.timezone.utc).date()

cycles, partial = g.list_cycles(args.variant, start, end, need_forecast=False)
cycles = {c: r for c, r in cycles.items() if last is None or c > last}
for c, r in partial.items():
    print(f"skipping incomplete cycle {c:%Y-%m-%d %Hz}: {len(r)}/{g.FAMILIES[args.variant]['per_cycle']} files")
if not cycles:
    raise SystemExit("nothing new")
newest = max(cycles)
if last is not None and min(cycles) - last != dt.timedelta(hours=6):
    print(f"WARNING: gap between stored cycle {last} and {min(cycles)}: the series will have a hole")

registry = g.make_registry()
rows = g.timeseries_rows(args.variant, cycles)
print(f"{name}: {len(cycles)} new cycles, {len(rows)} files")

session = repo.writable_session("main")
if not empty:                                   # drop the old forecast tail
    times = xr.open_zarr(session.store, consolidated=False, chunks=None).time.values
    keep = int(np.searchsorted(times, np.datetime64(last), side="right"))
    grp = zarr.open_group(session.store, mode="r+")
    for _, arr in grp.arrays():
        dims = arr.metadata.dimension_names or ()
        if "time" in dims:
            shape = list(arr.shape)
            shape[dims.index("time")] = keep
            arr.resize(tuple(shape))
    print(f"trimmed {len(times) - keep} forecast steps")

for i in range(0, len(rows), args.batch):
    part = rows[i:i + args.batch]
    ds = g.timeseries_dataset(part, registry)
    if empty:
        ds.vz.to_icechunk(session.store)
        empty = False
    else:
        g.for_append(ds, "time").vz.to_icechunk(session.store, append_dim="time")
    if i + args.batch < len(rows):
        session.commit(f"series {args.variant}: files up to {part[-1][0]:%Y-%m-%d %H}Z")
        session = repo.writable_session("main")
    print(f"  {min(i + args.batch, len(rows))}/{len(rows)} files", flush=True)

zarr.open_group(session.store, mode="r+").attrs["last_cycle"] = newest.isoformat()
snap = session.commit(f"series {args.variant}: cycles through {newest:%Y-%m-%d %Hz}")
print("committed", snap)
