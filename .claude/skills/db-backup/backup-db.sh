#!/usr/bin/env bash
#
# Dump the dev Postgres database to a gzipped plain-SQL file.
#
# The output format matches what scripts/restore-backup.sh consumes, so a dump
# made here restores with:
#   ./scripts/restore-backup.sh ~/Desktop/MoneyMatter-backups/<file>.sql.gz
#
# Usage (from anywhere inside the repo):
#   bash .claude/skills/db-backup/backup-db.sh            # → ~/Desktop/MoneyMatter-backups
#   BACKUP_DIR=/some/dir bash .claude/skills/db-backup/backup-db.sh
#
# The dump is written to a temp file next to the target and only renamed into
# place after gzip integrity passes, so an interrupted run never leaves a
# truncated file that looks like a valid backup.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-$HOME/Desktop/MoneyMatter-backups}"

# Route through docker-dev.sh so the dump targets THIS checkout's stack
# (its compose project name), not whichever stack owns the default `dev` name.
compose() {
  bash "$ROOT/scripts/docker-dev.sh" "$@"
}

if ! mkdir -p "$BACKUP_DIR" 2>/dev/null || ! [[ -w "$BACKUP_DIR" ]]; then
  echo "error: cannot write to $BACKUP_DIR" >&2
  echo "On macOS this usually means the terminal lacks Desktop access:" >&2
  echo "  System Settings → Privacy & Security → Files and Folders → <your terminal> → Desktop" >&2
  echo "Or pick another folder: BACKUP_DIR=/path bash $0" >&2
  exit 1
fi

if ! compose ps --status running db 2>/dev/null | grep -q db; then
  echo "error: the db container is not running. Start the stack with: npm run docker:dev" >&2
  exit 1
fi

STAMP="$(date +%Y-%m-%d_%H%M%S)"
TARGET="$BACKUP_DIR/moneymatter-$STAMP.sql.gz"
TMP="$TARGET.partial"
trap 'rm -f "$TMP"' EXIT

# $POSTGRES_USER / $POSTGRES_DB are single-quoted so they expand inside the
# container, where compose sets them – no credentials are read on the host.
compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' | gzip -9 > "$TMP"

gzip -t "$TMP"
# `head` closes the pipe early and gunzip dies of SIGPIPE, which pipefail would
# report as a failure – so read the header with pipefail off.
HEADER="$(set +o pipefail; gunzip -c "$TMP" | head -c 4096)"
if [[ "$HEADER" != *"PostgreSQL database dump"* ]]; then
  echo "error: dump does not look like a pg_dump output, keeping nothing" >&2
  exit 1
fi

mv "$TMP" "$TARGET"
trap - EXIT

echo "Backup written: $TARGET ($(du -h "$TARGET" | cut -f1))"
