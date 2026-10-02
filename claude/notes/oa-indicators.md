# OA indicators — what the build found

Built 2026-09-17 in PR #24. A **virtual** store at
`ocean-icechunks/oa-indicators/climatology`, snapshot `3VZQ6VDVY2644RZ9M0Z0`, from NCEI
accession 0270962. That accession ships one NetCDF per indicator; twelve are merged into one
flat group of 72 variables on `(depth 14, lat 76, lon 141)`. The whole store is **84 objects
and 35 kB** referencing 82 MB that stays at NCEI. No time dimension — it is a climatology,
and the accession is finished, so there is no update pipeline to write.

Merging one variable per file into a single store had no precedent here; CoastWatch splits
*into* groups because of codec differences, which is the opposite problem.

Further detail is in AGENTS.md under "Key gotchas (OA indicators…)". The ones that cost time:

- **`xr.merge` applies `combine_attrs` to *variable* attributes, not just the dataset's.** So
  `combine_attrs="drop"` silently empties every variable's attrs. It looked like virtualizarr
  losing metadata and was not. Use `"drop_conflicts"` and clear the per-file globals by hand.
- **The source coordinates were unusable, not merely untidy.** Phony all-zero HDF5 dimension
  scales `dep`/`lat`/`lon`, with the real values in separate variables. xarray reports
  `Dimensions without coordinates`, so `sel(lat=...)` did not work on the source at all.
  `swap_dims` fixes it as metadata, which is all a virtual store can do.
- **CF compliance here was substantive.** `units` was `"N/A"` on every dimensionless field and
  `"degrees Celsius"` on temperature; `standard_name` held free text. Real CF standard names
  exist for only six of the twelve indicators — checked against the table, and **none
  invented** for saturation states, the Revelle factor, hydrogen ion content or carbonate per
  unit mass.
- **`vz.to_icechunk` defaults to `mode="w-"`**, so re-running a write raises
  `ContainsGroupError` rather than being a no-op. The notebook skips a populated store unless
  `OVERWRITE` is set. The same trap bit `ocean-heat-test-sc.ipynb`, fixed there with
  `mode="w"`.
- **NCEI sends `Access-Control-Allow-Origin: *`** where `coastwatch.noaa.gov` sends none.
  That, and nothing else, is why this viewer draws and the OHC one does not — see
  [viewers.md](viewers.md).

**Confirmed 2026-09-18:** the viewer renders. Transport was verified from here on the build
date (content types, `application/wasm`, CORS on both hosts) and Eli then opened it in a
browser. There is no browser on the hub, so that division — transport here, rendering with
Eli — remains the norm; this is simply a case where both halves are done.

The pair of results was worth more than the store. This viewer drawing while the CoastWatch
one does not, from the same repository host, is the two-host CORS model confirmed with a
diagnosable symptom: coordinates are real chunks in the repository and render, science arrays
are virtual and do not. Both are now cited in the `virtual-icechunk` skill (PR #13 there),
which had been asserting the opposite.
