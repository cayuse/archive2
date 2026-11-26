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

**Reference** (`reference/`) — describe parts of the system that still exist, written when those
parts were built. Not reviewed line by line since; check against the code before relying on a detail.

| Document | About | Written |
|---|---|---|
| `ajb_design.md` | The jukebox (AJB): design. | 2025-10 |
| `archive_api.md` | API specification. | 2025-09 |
| `BULK_OPERATIONS_AND_API.md`, `DIRECT_UPLOAD_GUIDE.md` | Bulk upload and direct upload. | 2025-07 |
| `SONG_PROCESSING_SYSTEM.md` | How uploaded audio is processed. | 2025-07 |
| `PUNDIT_AUTHORIZATION.md`, `USER_MANAGEMENT.md` | Roles and authorization. | 2025-07 |
| `THEMING.md`, `THEMING_GUIDE.md`, `THEME_ASSETS.md` | Themes. | 2025-07 |
| `HEADLESS_JUKEBOX_RESEARCH.md` | Research behind the AirPlay player. | 2026-11 |
| `UI_DESIGN_PASS.md` | Design items not built yet. | 2026-11 |

**History** (`history/`) — plans, summaries and notes for work that is finished or was dropped
(the standalone slave jukeboxes and their replication, PowerSync, Bucardo, the JWT plan, the
pre-Kamal deployment guides, early setup guides, old READMEs). The code those describe was
removed on 2026-11-25; it is in git at the tag `pre-jukebox-removal`. Kept for the record; nothing
in there describes how the system works today.
