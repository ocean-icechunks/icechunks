# Getting the PacIOOS model files onto Source Cooperative

> Snapshot of the Claude Doc <https://claude.ai/artifact/4Nqhx91MozRLbfjYXmfpP7> as of
> 2026-11-10 (rev 10), before Eli's edits. The doc is the live copy that goes to PacIOOS;
> this file is the repo record. Background and measurements: `pacioos-roms.md`.

Nov 10, 2026 · Eli Holmes

## Summary

The five Hawaiʻi model archives total about 5 TB, and copying them straight from the PacIOOS server takes one to two days. That fits the 8-day goal with room to spare.

| Dataset | What it is | Years | Estimated size |
| --- | --- | --- | --- |
| ROMS reanalysis | Ocean currents, temperature, salinity (finished product) | 2009–2020 | 1.2 TB |
| ROMS hindcast | Same variables, data-assimilating, 3-day runs | 2015–now | 1.1 TB or more |
| ROMS forecast | Same variables, one 7-day run per day | 2025–now | 1.2 TB |
| ROMS sea surface height | 2-D companion files for the three above | as above | 0.1 TB |
| WRF wind and weather | One ~7-day run per day | 2010–now | 0.9 TB |
| WW3 waves | One 7.5-day run per day | 2011–now | 0.5 TB |
| **Total** | | | **about 5 TB** |

| Copy speed | Time for 5 TB |
| --- | --- |
| 100 MB/s (a typical UH server on a 1 Gbps link) | about 14 hours |
| 50 MB/s (busy or shared link) | about 28 hours |
| 1 MB/s (through the public THREDDS/ERDDAP pages, as measured) | about 2 months |

The sizes are worked out from the data's dimensions, without compression. If the files on disk are compressed, the real total is smaller. The copy has to be made from the server itself: the public web pages repackage the data as they send it, which is why they are about 100 times slower.

## What we are doing

We copy the original NetCDF files, unchanged, to Source Cooperative, a free public cloud archive for open data. Eli then builds an Icechunk index next to them. The index is a small catalog that lets people open the whole archive as one dataset in Python or a browser, reading straight from the cloud copy.

- **Nothing is reformatted.** The index points into the original files byte for byte, so they must not be changed after they are uploaded.
- **Downloads move off PacIOOS.** Users read from Source Cooperative, not from the PacIOOS server.
- **Old forecasts are kept.** The THREDDS server keeps the ROMS forecast only from 2025 on; the cloud copy becomes the long-term archive.

## The plan

For the 8-day deadline, Eli does the first copy herself from a login on the PacIOOS server. Later, PacIOOS uploads the new daily files on its own.

| Route | Who runs the copy | What PacIOOS provides | When |
| --- | --- | --- | --- |
| **A. Eli copies (recommended now)** | Eli, logged in to the PacIOOS server | A read-only login | First copy, within 8 days |
| B. PacIOOS runs Eli's script | PacIOOS staff | Someone to run one command | Fallback if a login is not possible |
| C. PacIOOS uploads on its own | PacIOOS staff, daily | A Source Cooperative account | After the first copy |

Route A puts the least work on PacIOOS: one account, then Eli does the rest. Route B avoids an account but needs a staff member's time each day the copy runs. Route C is the end goal; it needs a few more sign-up steps, so it can wait until after the deadline.

Proposed schedule (drawn as a timeline in the doc):

| Step | Dates (2026) |
| --- | --- |
| PacIOOS sets up the login | Nov 10 to Nov 12 |
| Look at files, test one | Nov 12 |
| Full copy (1 to 2 days) | Nov 13 to Nov 15 |
| Check copies, build index | Nov 16 to Nov 17 |
| Deadline | Nov 18 |

The copy itself needs one to two days; the extra day absorbs a slow link or a restart.

## Route A: what PacIOOS needs to do

PacIOOS sets up one login; Eli handles everything after that.

- [ ] **Create a login for Eli** on a machine that can read the model files. It needs read-only access to the model data folders and nothing else. Eli sends a public SSH key, so no password is shared.
- [ ] **Tell Eli the folder paths** for the ROMS, WW3 and WRF files.
- [ ] **Check that the machine can reach the internet over HTTPS** (port 443) to `data.source.coop`. Some servers block outgoing connections.
- [ ] **Agree a speed cap and quiet hours** (see Ground rules below).
- [ ] **Set an end date** for the login, for example two weeks after the copy finishes.
- [ ] If UH IT requires it, **sponsor a guest account**. Eli is at the University of Washington and NOAA, so she has no UH account.

What Eli does from that login:

1. Looks at the files: their sizes, and how they are stored inside. This settles the size estimates above.
2. Copies one file to Source Cooperative to test the route.
3. Runs the full copy with `rclone`, a widely used copy tool. It is a single program file in her own folder, so nothing is installed on the server. It resumes after a dropped connection and checks every file arrived intact.
4. Uses temporary Source Cooperative keys that expire after about a day. She creates them on her own computer, so no long-lived password sits on the PacIOOS machine.

## Route B: PacIOOS runs Eli's script

If a login is not possible, Eli sends a short script and a key file, and a PacIOOS staff member runs one command.

- **No Source Cooperative account needed.** Eli creates the temporary key file on her side and sends it privately. The script reads it.
- **The key expires after about a day.** If the copy is not finished, Eli sends a fresh key file and the same command picks up where it stopped.
- **The script only reads PacIOOS files.** It copies them out with `rclone` and never changes or deletes anything on the server.
- **What staff need:** a terminal on the machine with the files, the folder paths, and about 15 minutes to start the copy and check on it.

The key file grants write access to the project on Source Cooperative while it is valid, so keep it private and delete it when the copy is done.

## Route C, the end goal: PacIOOS uploads its own new files

Once the archive is in place, the only ongoing job is copying each day's new model runs, about 3 GB a day in total. That takes a minute or two and can be the last step of the existing daily forecast job.

1. A PacIOOS staff member signs up at [Source Cooperative](https://source.coop) and Eli adds them to the project with upload rights.
2. They install Source Cooperative's command-line login tool, which hands out temporary upload keys.
3. The daily job runs the same `rclone` copy as Route A, which sends only the files not yet uploaded.

The one awkward step is the login tool's sign-in: it opens a web page, which a server with no browser cannot show. Eli will work through it with PacIOOS after the deadline; it is not needed for the first copy.

## Ground rules

The copy must not slow the public forecast service, so it runs under these limits.

- **Speed cap.** The copy runs at a fixed limit, for example half the server's network speed. PacIOOS picks the number.
- **Quiet hours.** No copying while the daily forecast is being produced and published (around 1:30 PM HST). PacIOOS confirms the hours.
- **Read-only.** Nothing on the PacIOOS server is changed, moved or deleted.
- **Finished files only.** A forecast run still being written is skipped and picked up on the next pass.
- **Checked copies.** Every file is compared with the original after upload.
- **Account removed afterwards.** The login ends on the agreed date.

## Questions for PacIOOS

- [ ] Which machine holds the files, and what are the folder paths?
- [ ] How big is each folder on disk? A `du -sh` per folder replaces the estimates above.
- [ ] How fast is that machine's network connection, and may it connect out to `data.source.coop`?
- [ ] What speed cap and quiet hours should the copy keep to?
- [ ] Route A or Route B?
- [ ] Should every past forecast run be copied, or only the series the website shows?

## Not yet tested

- Uploading to Source Cooperative with `rclone`, including files of about 2 GB. The first day starts with a one-file test.
- Whether a one-day key lasts through each copy session. If not, the copy pauses and resumes with a new key.
- The sizes, which were worked out from the public metadata, not from the files themselves.
