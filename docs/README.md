# Documentation

**Current** — kept up to date; trust these.

| Document | About |
|---|---|
| `../README.md` | What is in the repository, how to run, check and deploy it. |
| `STATUS.md` | What is built and deployed, what is not, and the gotchas learned along the way. |
| `../archive/KAMAL_DEPLOY.md` | Deploying the app (backup, deploy, migrate, rollback, staging). |
| `../station/README.md` | The player service: how it works, deploy, settings, testing. |
| `../library_tools/staging/README.md` | The staging harness (production-copy database, tests, end-to-end scripts). |
| `../library_tools/README.md` | Library maintenance tools. |

**Reference** (`reference/`) — describe parts of the system that still exist. Checked against the
code on 2026-11-26 (except `UI_DESIGN_PASS.md`, which is a to-do list); the code is still the authority.

| Document | About |
|---|---|
| `archive_api.md` | The `/api/v1` API: authentication, songs, playlists, jukeboxes and stations, speaker playback, guest endpoints. |
| `BULK_OPERATIONS_AND_API.md` | The Bulk Operations page (CSV import/export, bulk delete) and bulk upload. |
| `INTAKE.md` | The Drop Box: how dropped files, folders and archives are sorted, identified, tagged and imported. |
| `SONG_PROCESSING_SYSTEM.md` | How uploaded audio is tagged, the processing statuses, the Maintenance page. |
| `PUNDIT_AUTHORIZATION.md` | Roles and who may do what (Pundit policies and controller checks). |
| `USER_MANAGEMENT.md` | Accounts, login, admin user management, email. |
| `THEMING.md` | Themes: colours, the generated CSS, managing themes. |
| `THEME_ASSETS.md` | Theme logos, icons and images. |
| `UI_DESIGN_PASS.md` | Design items not built yet. |

**History** (`history/`) — plans, summaries and notes for work that is finished or was dropped
(the standalone slave jukeboxes and their replication, PowerSync, Bucardo, the JWT plan, the
pre-Kamal deployment guides, early setup guides, old READMEs). The code those describe was
removed on 2026-11-25; it is in git at the tag `pre-jukebox-removal`.

Also there: the design and research records behind what was built (`ajb_design.md` for the
jukebox, `HEADLESS_JUKEBOX_RESEARCH.md` for the speaker player), and `DIRECT_UPLOAD_GUIDE.md` and
`UPLOAD_METHODS_COMPARISON.md` for upload paths that no longer exist.

Kept for the record; nothing in there describes how the system works today.
