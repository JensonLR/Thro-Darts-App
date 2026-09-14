#!/bin/sh
# serve   — the HTTP API (default)
# migrate — bring the database to this image's version and exit (the release step)
set -e
case "${1:-serve}" in
  serve)   exec java -XX:MaxRAMPercentage=75 -cp "/app/lib/*" thro.api.http.MainKt ;;
  migrate) exec java -cp "/app/lib/*" thro.api.MigrateKt ;;
  *) echo "unknown command: $1 (serve|migrate)" >&2; exit 2 ;;
esac
