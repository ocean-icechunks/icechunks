# The env the notebooks need, and the env they have

## icechunk 2.x is Python >= 3.12 only

Every icechunk 2.x release on PyPI — 2.0.0 through 2.2.1 — is published with
`requires_python = ">=3.12"`. There are no 3.11 wheels and no sdist fallback that
builds on 3.11.

The JupyterLab image (`/srv/conda/envs/notebook`) is currently **Python 3.11.14**,
and `icechunk` is not installed in it. The production run of 2026-08-26 was on
Python 3.12 — its stored warnings carry
`/srv/conda/envs/notebook/lib/python3.12/site-packages/...` paths, while the same
env today is `.../python3.11/...`. So the image moved *backwards* a minor version
at some point between the build and 2026-09-17.

Consequence: **`pip install "icechunk>=2.1"` in the current image resolves to
nothing** — pip reports no matching distribution, because the only versions it can
see for 3.11 are the 1.1.x line. The install line in AGENTS.md is correct about
what is needed and silently wrong about whether it will work here.

**A 3.12 venv works, and this is the recipe** (verified 2026-09-17 by running
`ocean-heat-test-sc.ipynb` end to end):

```bash
/srv/conda/bin/python3.12 -m venv /path/to/venv      # NOT /usr/bin/python3.12
/path/to/venv/bin/pip install --no-cache-dir -r coastwatch-heat-content/requirements.txt \
    nbconvert ipykernel
/path/to/venv/bin/python -m ipykernel install --prefix=/path/to/venv --name venv312
JUPYTER_PATH=/path/to/venv/share/jupyter /path/to/venv/bin/jupyter nbconvert \
    --to notebook --execute --ExecutePreprocessor.kernel_name=venv312 \
    --output /somewhere/out.ipynb coastwatch-heat-content/ocean-heat-test-sc.ipynb
```

Use `--no-cache-dir`, or clean up after. **pip's wheel cache is what fills the home
quota**, and on this hub that failure is disguised: every write to `/home/jovyan` starts
returning `No space left on device` — `git checkout` cannot create `.git/index.lock`, a
one-byte `echo x > file` fails — while `df` cheerfully reports 109 GB free and 3 % of
inodes used. `df` shows the *export's* totals (`10.100.33.250:/prod/eeholmes`), not the
per-user quota, so a full quota and a healthy disk look identical to it. Building the venv
above pulled ~370 MB of wheels into `~/.cache/pip` and tipped the quota over mid-session
on 2026-09-17; `rm -rf ~/.cache/pip` restored writes immediately.

So either install with `--no-cache-dir`, or run `pip cache purge` (or `rm -rf
~/.cache/pip`) as soon as the venv is built. Do not go looking for a full disk: if writes
to home fail while `df` shows free space, it is the quota, and the cache is the first
place to look. `~/.cache` also accumulates `pre-commit` (~100 MB) and `uv`/`virtualenv`
trees worth clearing.

Two traps in that recipe:

- **`/usr/bin/python3.12` cannot make a venv here** — it has no `ensurepip`
  ("On Debian/Ubuntu systems, you need to install the python3-venv package"). Use
  `/srv/conda/bin/python3.12`, which is 3.12.12 and does have it.
- **Run the notebook from `coastwatch-heat-content/`**, not from a copy elsewhere. It
  does `sys.path.insert(0, '..')` to find `icechunk_utils.py` at the repo root, so a copy
  executed in a scratch directory fails with `ModuleNotFoundError: icechunk_utils`. That
  is the notebook working as designed, not a bug.

So "unrunnable" is a statement about the *kernel* env, not about the machine. The other
options, in order: check whether the image has been bumped back to 3.12 (`python -V`
settles it), or pin to `icechunk>=1.1,<2` — the last is **not** advisable, since the
notebooks use 2.x APIs and the published repos were written by 2.x. Do not "fix" this by
relaxing the bound in `requirements.txt` to whatever installs.

Resolved versions in that venv ran far ahead of the floors in `requirements.txt` —
icechunk 2.2.1, virtualizarr 2.7.3, zarr 3.4.0, xarray 2026.7.0, obstore 0.11.1,
pandas 3.0.5 — and everything worked. That is the evidence for keeping lower bounds and
no lock file.

## Four dependencies the docs never mentioned

`NetCDF3Parser` (the `daily` and `14day_v1` groups) reaches
`kerchunk.netCDF3.NetCDF3ToZarr`, which subclasses `scipy.io._netcdf.netcdf_file`.
So the NetCDF-3 path needs **kerchunk and scipy**, neither of which appears in the
notebook imports or in AGENTS.md's pip line. It has never been noticed because the
JupyterLab image ships both. On a bare env, the two NetCDF-3 groups fail with
kerchunk's "pip/conda install scipy" hint while the HDF5 group works fine — which
looks like a data problem and is not one.

Running the notebook in a clean venv turned up two more of the same kind, invisible in the
JupyterLab image because it ships them:

- **`aiohttp`** — kerchunk reads source headers through fsspec's `HTTPFileSystem`, which is
  async. Without it the first file to be virtualized raises `HTTPFileSystem requires
  "requests" and "aiohttp" to be installed`. `requests` alone is not enough, despite the
  message naming it.
- **`dask`** — the read path in both READMEs is `xr.open_zarr(..., chunks={})`, which raises
  `chunk manager 'dask' is not available` without it. A reader following our own
  instructions after `pip install -r requirements.txt` would have hit that.

All four are now in `requirements.txt` with the reasoning inline. The general lesson: this
image is a generous environment, so anything it happens to ship is invisible until someone
installs only what we declare.

## Verifying a published repo without icechunk

Since the kernel env currently cannot import icechunk at all, repo-existence checks
go over plain HTTPS — see [verifying-published-repos.md](verifying-published-repos.md).
