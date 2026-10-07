#!/usr/bin/env bash
# podship restore script. Installed on the server in <podship_home>/lib.
#
#   restore.sh CONF drill [STAMP]
#       Restores the dump into a THROWAWAY postgres container (no network, no
#       ports), compares row counts with the counts taken at backup time and
#       with the live database, and deletes the container. Does not touch the
#       live database. Without STAMP it uses the newest backup.
#
#   restore.sh CONF restore --confirmed NAME (STAMP | --dump FILE | --dir DIR) [--volumes]
#       Replaces the live database. podship asks you to type the project
#       name first and passes it as NAME. Steps:
#         1. takes a fresh backup of the current state;
#         2. stops the app services;
#         3. RENAMES the current database to <db>_before_<time> (no drop);
#         4. creates an empty database and restores the dump;
#         5. starts the services again and waits for the health URL.
#       With --volumes, also replaces the configured Docker volumes with the
#       archives of the backup (the old content is kept as a tar.gz next to
#       them). --dir restores a backup folder copied from another server.
#       To undo: stop the services, swap the database names, start them.
set -euo pipefail

CONF="${1:?usage: restore.sh CONF drill|restore ...}"
MODE="${2:?usage: restore.sh CONF drill|restore ...}"
shift 2
# shellcheck disable=SC1090
source "$CONF"
: "${PROJECT:?}" "${DEST:?}" "${DB_NAME:?}"
LAYOUT_PLAIN="${LAYOUT_PLAIN:-daily}"
DUMP_NAME="${DUMP_NAME:-db.dump}"
COUNTS_NAME="${COUNTS_NAME:-counts.txt}"
DB_SERVICE="${DB_SERVICE:-postgres}"
DB_USER="${DB_USER:-postgres}"
DB_CONTAINER="${DB_CONTAINER:-}"
PG_IMAGE="${PG_IMAGE:-postgres:16-alpine}"
HELPER_IMAGE="${HELPER_IMAGE:-python:3.12-alpine}"
DRILL_TABLES="${DRILL_TABLES:-}"
DRILL_VOLATILE="${DRILL_VOLATILE:-}"
STOP_SERVICES="${STOP_SERVICES:-}"
COMPOSE_SH="${COMPOSE_SH:-}"
HEALTH_URL="${HEALTH_URL:-}"
BACKUP_UNIT="${BACKUP_UNIT:-}"

log() { echo "[restore] $*"; }
_sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
fail() { echo "[restore] ERROR: $*" >&2; exit 1; }

CONFIRMED="" STAMP="" DUMP="" DIR="" WITH_VOLUMES=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirmed) CONFIRMED="${2:?}"; shift ;;
    --dump) DUMP="${2:?--dump needs a file}"; shift ;;
    --dir) DIR="${2:?--dir needs a folder}"; shift ;;
    --volumes) WITH_VOLUMES=1 ;;
    -*) fail "unknown option $1" ;;
    *) STAMP="$1" ;;
  esac
  shift
done

if [[ -n "$DIR" ]]; then
  DUMP="$DIR/$DUMP_NAME"
  log "checking the checksums of $DIR"
  (cd "$DIR" && _sha256 -c --status SHA256SUMS) || fail "SHA-256 checksums do not match"
elif [[ -z "$DUMP" ]]; then
  [[ -n "$STAMP" ]] || STAMP=$(ls -1 "$DEST/$LAYOUT_PLAIN" 2>/dev/null | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{4}$' | sort | tail -1)
  [[ -n "$STAMP" ]] || fail "no backups in $DEST/$LAYOUT_PLAIN"
  DIR="$DEST/$LAYOUT_PLAIN/$STAMP"
  DUMP="$DIR/$DUMP_NAME"
  [[ -f "$DUMP" ]] || fail "no $DUMP"
  log "checking the checksums of $STAMP"
  (cd "$DIR" && _sha256 -c --status SHA256SUMS) || fail "SHA-256 checksums do not match"
fi
[[ -s "$DUMP" ]] || fail "the dump $DUMP is empty or missing"

db_container() {
  if [[ -n "$DB_CONTAINER" ]]; then echo "$DB_CONTAINER"; return; fi
  docker ps -q --filter "label=com.docker.compose.project=$PROJECT" \
    --filter "label=com.docker.compose.service=$DB_SERVICE" | head -1
}

# Does table $1 match one of the bash patterns in $2?
matches() {
  local t="$1" pat
  for pat in $2; do
    # shellcheck disable=SC2053
    [[ "$t" == $pat ]] && return 0
  done
  return 1
}

count_rows() { # count_rows <psql command...>: prints "table rows"
  "$@" -Atq -F ' ' <<'SQL'
select format('select %L, count(*) from public.%I', tablename, tablename)
from pg_tables where schemaname = 'public' order by 1 \gexec
SQL
}

drill() {
  name="podship-drill-$PROJECT-$(date +%Y%m%d%H%M%S)"
  trap 'docker rm -f -v "$name" >/dev/null 2>&1 || true' EXIT
  log "throwaway container $name (no network, no ports)"
  docker run -d --name "$name" --network none --memory 512m \
    -e POSTGRES_HOST_AUTH_METHOD=trust "$PG_IMAGE" >/dev/null
  # While it initializes, postgres listens only on the socket; TCP on
  # 127.0.0.1 means it is really up.
  for _ in $(seq 60); do
    docker exec "$name" pg_isready -q -h 127.0.0.1 -U postgres && break
    sleep 1
  done
  docker exec "$name" pg_isready -q -h 127.0.0.1 -U postgres || fail "the throwaway postgres did not start"
  docker exec "$name" psql -q -h 127.0.0.1 -U postgres -c "create database \"$DB_NAME\"" >/dev/null 2>&1 || true

  log "pg_restore of $DUMP"
  local t0=$SECONDS
  docker exec -i "$name" pg_restore -h 127.0.0.1 -U postgres -d "$DB_NAME" --no-owner --exit-on-error <"$DUMP" ||
    fail "pg_restore failed"
  log "restored in $((SECONDS - t0)) s"

  local restored live pg
  restored=$(count_rows docker exec -i "$name" psql -h 127.0.0.1 -U postgres -d "$DB_NAME")
  pg=$(db_container)
  live=""
  [[ -n "$pg" ]] && live=$(count_rows docker exec -i "$pg" psql -U "$DB_USER" -d "$DB_NAME")

  local fails=0 compared=0 t n at_backup now mark
  printf '%-52s %10s %10s %10s\n' TABLE RESTORED AT_BACKUP LIVE_NOW
  while read -r t n; do
    [[ -z "$t" ]] && continue
    if [[ -n "$DRILL_TABLES" ]] && ! matches "$t" "$DRILL_TABLES"; then continue; fi
    compared=$((compared + 1))
    at_backup=$(awk -v t="$t" '$1==t {print $2}' "${DIR:-/nonexistent}/$COUNTS_NAME" 2>/dev/null || true)
    now=$(awk -v t="$t" '$1==t {print $2}' <<<"$live")
    mark=""
    if [[ -n "$at_backup" && "$at_backup" != "$n" ]]; then
      if matches "$t" "$DRILL_VOLATILE"; then mark="  (changed during the backup)"
      else mark="  <-- DOES NOT MATCH"; fails=$((fails + 1)); fi
    fi
    [[ -z "$mark" && -n "$now" && "$now" != "$n" ]] && mark="  (changed live after the backup)"
    printf '%-52s %10s %10s %10s%s\n' "$t" "$n" "${at_backup:--}" "${now:--}" "$mark"
  done <<<"$restored"
  [[ $fails -eq 0 ]] || fail "$fails tables do not match the backup counts"
  log "drill OK: $compared tables match backup ${STAMP:-$DUMP}"
}

restore() {
  [[ "$CONFIRMED" == "$PROJECT_NAME" ]] || fail "confirmation missing: pass --confirmed $PROJECT_NAME"
  [[ -x "$COMPOSE_SH" ]] || fail "no current release ($COMPOSE_SH)"

  log "1/5 backup of the current state"
  if [[ -n "$BACKUP_UNIT" ]] && command -v systemctl >/dev/null 2>&1 && systemctl cat "$BACKUP_UNIT.service" >/dev/null 2>&1; then
    systemctl start "$BACKUP_UNIT.service" || fail "the backup of the current state failed; stopping"
  else
    "$(dirname "$0")/backup.sh" "$CONF" || fail "the backup of the current state failed; stopping"
  fi

  local services before pg
  services="$STOP_SERVICES"
  if [[ -z "$services" ]]; then
    services=$("$COMPOSE_SH" config --services | grep -vx "$DB_SERVICE" | tr '\n' ' ')
  fi
  before="${DB_NAME}_before_$(date +%Y%m%d%H%M%S)"
  log "2/5 stopping $services"
  # shellcheck disable=SC2086
  "$COMPOSE_SH" stop $services

  pg=$(db_container)
  [[ -n "$pg" ]] || fail "the database container is not running"
  log "3/5 the current database becomes $before"
  docker exec -i "$pg" psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 \
    -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$DB_NAME' and pid <> pg_backend_pid();" \
    -c "alter database \"$DB_NAME\" rename to \"$before\";" \
    -c "create database \"$DB_NAME\";"

  log "4/5 pg_restore"
  if ! docker exec -i "$pg" pg_restore -U "$DB_USER" -d "$DB_NAME" --no-owner --exit-on-error <"$DUMP"; then
    echo "[restore] pg_restore failed. To go back: rename $before to $DB_NAME and run: $COMPOSE_SH up -d --force-recreate $services" >&2
    exit 1
  fi

  if [[ -n "$WITH_VOLUMES" ]]; then
    [[ -n "$DIR" ]] || fail "--volumes needs a backup folder (a stamp or --dir)"
    for entry in ${VOLUMES:-}; do
      IFS='|' read -r vname vol _sqlite _files owner <<<"$entry"
      arc=""
      for ext in tar.zst tar.gz; do [[ -f "$DIR/$vname.$ext" ]] && arc="$DIR/$vname.$ext"; done
      [[ -n "$arc" ]] || { log "no archive for volume $vname; kept"; continue; }
      log "volume $vol ← $(basename "$arc")"
      if [[ "$vol" == /* ]]; then mkdir -p "$vol"; else docker volume create "$vol" >/dev/null; fi
      keep="$(dirname "$DUMP")/$vname-before-$(date +%Y%m%d%H%M%S).tar.gz"
      docker run --rm -v "$vol:/v" "$HELPER_IMAGE" tar -C /v -czf - . >"$keep" || true
      case "$arc" in
        *.zst) zstd -dc "$arc" ;;
        *) gzip -dc "$arc" ;;
      esac | docker run --rm -i -v "$vol:/v" "$HELPER_IMAGE" sh -c "tar -x -C /v --strip-components=1${owner:+ && chown -R $owner /v}"
    done
  fi

  log "5/5 starting $services"
  # shellcheck disable=SC2086
  "$COMPOSE_SH" up -d --no-build --force-recreate $services
  if [[ -n "$HEALTH_URL" ]]; then
    for _ in $(seq 30); do
      if curl -fsS -o /dev/null --max-time 5 "$HEALTH_URL"; then
        log "done; $HEALTH_URL answers. The old database is $before."
        return 0
      fi
      sleep 4
    done
    fail "$HEALTH_URL does not answer; check the logs"
  fi
  log "done. The old database is $before."
}

case "$MODE" in
  drill) drill ;;
  restore) restore ;;
  *) fail "unknown mode $MODE" ;;
esac
