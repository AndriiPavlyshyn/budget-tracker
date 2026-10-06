---
name: db-backup
description: >
  Back up the local dev Postgres database to a gzipped SQL dump on the Desktop
  (~/Desktop/MoneyMatter-backups), which the user then copies to iCloud manually.
  Trigger on "/db-backup", "backup the database", "make a DB backup", "зроби бекап",
  "бекап бд", or before risky operations on local data (restores, mass imports,
  dropping volumes).
---

Create a restorable dump of the local dev database. The dump goes to `~/Desktop/MoneyMatter-backups/`; the user moves it to iCloud Drive themselves – never try to copy it into iCloud.

## Steps

### 1. Run the backup script

```bash
bash .claude/skills/db-backup/backup-db.sh
```

It dumps the `db` service of this checkout's Docker stack (via `scripts/docker-dev.sh`), verifies the gzip and the pg_dump header, and only then moves the file into place as `moneymatter-YYYY-MM-DD_HHMMSS.sql.gz`.

Do not read `.env*` files to get DB credentials – the script expands them inside the container.

### 2. Handle failures – do not improvise

- **`cannot write to …/Desktop/MoneyMatter-backups`** – macOS privacy blocks this terminal from the Desktop. Tell the user to grant access (System Settings → Privacy & Security → Files and Folders → their terminal/IDE → Desktop, then restart the terminal) or to run the script themselves with `! bash .claude/skills/db-backup/backup-db.sh`. If they want a backup right now anyway, offer `BACKUP_DIR=.temp/backups` (gitignored) and tell them where it landed.
- **`db container is not running`** – ask before starting the stack (`npm run docker:dev -- -d`); starting it is not part of a backup.
- Anything else – show the error output and stop.

### 3. Report

Tell the user the file path and size from the script output, and remind them to copy it to iCloud Drive. Old backups are never deleted by this skill – the user manages retention.

## Restore (only when the user asks)

```bash
./scripts/restore-backup.sh ~/Desktop/MoneyMatter-backups/moneymatter-<stamp>.sql.gz
```

This **drops and recreates** the database and asks for interactive confirmation, so the user must run it themselves (`! ./scripts/restore-backup.sh <file>`). Suggest making a fresh backup first.
