# Verifying a published Icechunk repo without icechunk installed

The JupyterLab base env does **not** have `icechunk` (see AGENTS.md "Required
packages" — pip, never conda, or the env will not solve). So a session that wants to
confirm a published repo exists cannot just call `icechunk.Repository.open`, and
installing a package is a poor reason to answer a one-line status question.

Source Cooperative serves the bucket over plain S3-style HTTPS, so list the prefix:

```bash
curl -s "https://data.source.coop/ocean-icechunks?list-type=2&prefix=noaa-ohc/na/&delimiter=/"
```

A healthy Icechunk repo answers with a `repo` object (the persisted config, ~1 KB)
plus `chunks/`, `manifests/`, `snapshots/`, `transactions/` and `overwritten/`
prefixes. Drop `/na/` for the prefix root to see which mirrored docs actually landed.

Two things this avoids getting wrong:

- **There is no `config.yaml`.** Probing for one — or for `refs/branch.main/ref.json` —
  returns 404 on a perfectly healthy repo. The config lives in the object literally
  named `repo`. A 404 on a guessed path proves nothing; list the prefix instead.
- **A repo that opens is not a repo that reads.** The write path returning "committed"
  and the anonymous read path working are different claims. Listing the prefix
  confirms the objects are public, which is the part a reader depends on.

For the real read test — that virtual chunk references resolve back to CoastWatch —
icechunk is genuinely needed, along with `authorize_virtual_chunk_access` at open
time; build the 3.12 venv in [environment.md](environment.md) when it is worth it. (It
was: that is how the anonymous read path was confirmed on 2026-09-17.) The published repos have `save_config()` applied, so anonymous reopeners pick
up the `VirtualChunkContainer` without passing config themselves.

Related gotcha already in AGENTS.md, worth not re-learning: a wrong anonymous read
URL raises `RepositoryNotFoundError` **deterministically**, and the URL must include
the bucket (`.../ocean-icechunks/noaa-ohc/na`). It is not a flaky gateway, so do not
add retries around it.
