#!/usr/bin/env bash
# podship backup script. Installed on the server in <podship_home>/lib.
#
#   backup.sh CONF                        take a backup, encrypt a copy, prune
#   backup.sh CONF --test-retention DIR   print what retention keeps in DIR
#   backup.sh CONF --list                 print "STAMP SIZE ENCRYPTED" lines
#
# CONF is a bash file with the settings (no secrets): see `podship backup
# schedule --dry-run`. Each run writes:
#
#   $DEST/$LAYOUT_PLAIN/<stamp>/
#     $DUMP_NAME      pg_dump -Fc of the database
#     <volume>.tar.zst or .tar.gz   Docker volumes (SQLite files copied with
#                     SQLite's backup API, never with cp)
#     $COUNTS_NAME    rows per table at backup time
#     SHA256SUMS
#   $DEST/$LAYOUT_ENC/<stamp>.tar.age
#     the same files plus the secret files, encrypted with age to the
#     recipients in $RECIPIENTS_FILE (age or SSH public keys)
#
# Retention keeps everything from today and yesterday, plus the newest backup
# of each of the last KEEP_DAYS days, KEEP_WEEKS weeks and KEEP_MONTHS months.
# It prunes only after the new backup is complete.
set -euo pipefail
umask 077

CONF="${1:?usage: backup.sh CONF [--test-retention DIR | --list]}"
shift
# shellcheck disable=SC1090
source "$CONF"

: "${PROJECT:?}" "${DEST:?}" "${DB_NAME:?}"
LAYOUT_PLAIN="${LAYOUT_PLAIN:-plain}"
LAYOUT_ENC="${LAYOUT_ENC:-encrypted}"
DUMP_NAME="${DUMP_NAME:-db.dump}"
COUNTS_NAME="${COUNTS_NAME:-counts.txt}"
SECRETS_NAME="${SECRETS_NAME:-secrets}"
DB_SERVICE="${DB_SERVICE:-postgres}"
DB_USER="${DB_USER:-postgres}"
DB_CONTAINER="${DB_CONTAINER:-}"
TZ_LOCAL="${TZ_LOCAL:-UTC}"
KEEP_DAYS="${KEEP_DAYS:-14}" KEEP_WEEKS="${KEEP_WEEKS:-8}" KEEP_MONTHS="${KEEP_MONTHS:-6}"
COMPRESS="${COMPRESS:-zstd}"
HELPER_IMAGE="${HELPER_IMAGE:-python:3.12-alpine}"
VOLUMES="${VOLUMES:-}"
SECRET_FILES="${SECRET_FILES:-}"
RECIPIENTS_FILE="${RECIPIENTS_FILE:-}"
MIN_TABLES="${MIN_TABLES:-1}"
PATTERN='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{4}$'

log() { echo "[backup] $*"; }
fail() { echo "[backup] ERROR: $*" >&2; exit 1; }

# --- retention ---------------------------------------------------------------
# Portable: bash 3.2 and BSD tools (macOS) as well as GNU (Linux).
_sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

# Reads stamps (one per line) and writes the ones to keep. TODAY (YYYY-MM-DD)
# can be set for tests.
keep_stamps() {
  local today="${TODAY:-$(TZ=$TZ_LOCAL date +%F)}"
  grep -E "$PATTERN" | sort -r | awk -v today="$today" \
    -v kd="$KEEP_DAYS" -v kw="$KEEP_WEEKS" -v km="$KEEP_MONTHS" '
    # Days since 1970-01-01 for a civil date.
    function dfc(y, m, d,   era, yoe, doy, doe) {
      y -= (m <= 2)
      era = int((y >= 0 ? y : y - 399) / 400)
      yoe = y - era * 400
      doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
      doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
      return era * 146097 + doe - 719468
    }
    # ISO 8601 week, like 2026-W41.
    function isoweek(y, m, d,   n, wd, thu, ty) {
      n = dfc(y, m, d)
      wd = ((n % 7) + 7 + 4) % 7; if (wd == 0) wd = 7
      thu = n - wd + 4
      ty = y
      if (thu < dfc(y, 1, 1)) ty = y - 1
      else if (thu >= dfc(y + 1, 1, 1)) ty = y + 1
      return sprintf("%04d-W%02d", ty, int((thu - dfc(ty, 1, 1)) / 7) + 1)
    }
    BEGIN { split(today, t, "-"); recent = dfc(t[1] + 0, t[2] + 0, t[3] + 0) - 1 }
    {
      s = $0; d = substr(s, 1, 10)
      y = substr(d, 1, 4) + 0; m = substr(d, 6, 2) + 0; dd = substr(d, 9, 2) + 0
      if (dfc(y, m, dd) >= recent) keep[s] = 1
      w = isoweek(y, m, dd); mo = substr(d, 1, 7)
      if (!(d in days) && nd < kd) { days[d] = 1; nd++; keep[s] = 1 }
      if (!(w in weeks) && nw < kw) { weeks[w] = 1; nw++; keep[s] = 1 }
      if (!(mo in months) && nm < km) { months[mo] = 1; nm++; keep[s] = 1 }
    }
    END { for (s in keep) print s }' | sort
}

all_stamps() {
  (ls -1 "$1/$LAYOUT_PLAIN" 2>/dev/null; ls -1 "$1/$LAYOUT_ENC" 2>/dev/null | sed 's/\.tar\.age$//') |
    grep -E "$PATTERN" | sort -u || true
}

prune() {
  local dir="$1" dry="${2:-}" keep s
  keep=$(all_stamps "$dir" | keep_stamps)
  for s in $(all_stamps "$dir"); do
    if grep -qx "$s" <<<"$keep"; then
      [[ -n "$dry" ]] && echo "keep $s"
    elif [[ -n "$dry" ]]; then
      echo "delete $s"
    else
      log "retention: delete $s"
      rm -rf -- "${dir:?}/$LAYOUT_PLAIN/$s" "${dir:?}/$LAYOUT_ENC/$s.tar.age"
    fi
  done
  return 0
}

if [[ "${1:-}" == "--test-retention" ]]; then
  prune "${2:?--test-retention needs a directory}" dry
  exit 0
fi

if [[ "${1:-}" == "--list" ]]; then
  for s in $(all_stamps "$DEST"); do
    size=-
    [[ -d "$DEST/$LAYOUT_PLAIN/$s" ]] && size=$(du -sh "$DEST/$LAYOUT_PLAIN/$s" | cut -f1)
    enc=no
    [[ -f "$DEST/$LAYOUT_ENC/$s.tar.age" ]] && enc=yes
    echo "$s $size $enc"
  done
  exit 0
fi

# --- backup ------------------------------------------------------------------
db_container() {
  if [[ -n "$DB_CONTAINER" ]]; then echo "$DB_CONTAINER"; return; fi
  docker ps -q --filter "label=com.docker.compose.project=$PROJECT" \
    --filter "label=com.docker.compose.service=$DB_SERVICE" | head -1
}

# A lock that works without flock (macOS): a directory with the owner pid.
LOCK="/tmp/podship-backup-$PROJECT.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  if kill -0 "$(cat "$LOCK/pid" 2>/dev/null)" 2>/dev/null; then
    fail "another backup of $PROJECT is running"
  fi
  rm -rf "$LOCK"; mkdir "$LOCK"
fi
echo $$ >"$LOCK/pid"

if [[ -n "$RECIPIENTS_FILE" ]]; then
  [[ -s "$RECIPIENTS_FILE" ]] || fail "the recipients file $RECIPIENTS_FILE is missing or empty"
  command -v age >/dev/null || fail "age is not installed (apt install age)"
fi
case "$COMPRESS" in
  zstd) command -v zstd >/dev/null || fail "zstd is not installed"; EXT=tar.zst ;;
  gzip) EXT=tar.gz ;;
  *) fail "COMPRESS must be zstd or gzip" ;;
esac

PG=$(db_container)
[[ -n "$PG" ]] || fail "no running container for service $DB_SERVICE of project $PROJECT"

mkdir -p "$DEST/$LAYOUT_PLAIN" "$DEST/$LAYOUT_ENC"
chmod 700 "$DEST" "$DEST/$LAYOUT_PLAIN" "$DEST/$LAYOUT_ENC"
# One backup per minute: if this minute is taken (a restore right after a
# backup), wait for the next one.
for _ in $(seq 15); do
  STAMP=$(TZ=$TZ_LOCAL date +%Y-%m-%dT%H%M)
  OUT="$DEST/$LAYOUT_PLAIN/$STAMP"
  [[ -e "$OUT" || -e "$DEST/$LAYOUT_ENC/$STAMP.tar.age" ]] || break
  sleep 5
done
[[ -e "$OUT" ]] && fail "$OUT already exists"
TMP=$(mktemp -d "$DEST/.in-progress-$STAMP.XXXX")
VTMP=""
trap 'rm -rf -- "$TMP" "$LOCK" ${VTMP:+"$VTMP"}' EXIT

log "stamp $STAMP"

# 1. Database. pg_dump runs inside the container and takes a consistent
#    snapshot without blocking anyone.
log "pg_dump of $DB_NAME"
docker exec "$PG" pg_dump -U "$DB_USER" -Fc "$DB_NAME" >"$TMP/$DUMP_NAME"
[[ -s "$TMP/$DUMP_NAME" ]] || fail "the dump is empty"
tables=$(docker exec -i "$PG" pg_restore --list <"$TMP/$DUMP_NAME" | grep -c ' TABLE DATA ') ||
  fail "pg_restore cannot read the dump"
[[ "$tables" -ge "$MIN_TABLES" ]] || fail "the dump has only $tables tables with data"
log "dump: $(du -h "$TMP/$DUMP_NAME" | cut -f1), $tables tables with data"

docker exec -i "$PG" psql -U "$DB_USER" -d "$DB_NAME" -Atq -F ' ' >"$TMP/$COUNTS_NAME" <<'SQL' ||
select format('select %L, count(*) from %I.%I', tablename, schemaname, tablename)
from pg_tables where schemaname = 'public' order by tablename \gexec
SQL
  fail "cannot count rows"

# 2. Volumes. Each entry is name|volume|sqlite files (comma)|files (comma).
FILES=("$DUMP_NAME" "$COUNTS_NAME")
for entry in $VOLUMES; do
  IFS='|' read -r vname vol sqlite files <<<"$entry"
  log "volume $vol → $vname.$EXT"
  docker volume inspect "$vol" >/dev/null 2>&1 || fail "no Docker volume $vol"
  VTMP=$(mktemp -d "/tmp/podship-volume-$vname.XXXX")
  chmod 777 "$VTMP"
  mkdir -p "$TMP/$vname"
  # SQLite files: copy with the backup API, as the file owner, so the daemon
  # never finds -wal/-shm files it cannot open.
  for db in ${sqlite//,/ }; do
    owner=$(docker run --rm -v "$vol:/v:ro" "$HELPER_IMAGE" stat -c '%u:%g' "/v/$db")
    docker run --rm -i --network none --user "$owner" \
      -v "$vol:/v" -v "$VTMP:/out" "$HELPER_IMAGE" python - "$db" <<'PY'
import sqlite3, sys
name = sys.argv[1]
src = sqlite3.connect("/v/" + name, timeout=30)
dst = sqlite3.connect("/out/" + name.replace("/", "_"))
src.backup(dst)
ok = dst.execute("pragma integrity_check").fetchone()[0]
dst.close(); src.close()
if ok != "ok":
    sys.exit("integrity_check: " + ok)
PY
    mv "$VTMP/${db//\//_}" "$TMP/$vname/"
  done
  # Other files: the listed ones, or the whole volume minus SQLite files.
  excludes=""
  for db in ${sqlite//,/ }; do excludes="$excludes --exclude=./$db --exclude=./$db-wal --exclude=./$db-shm"; done
  if [[ -n "$files" ]]; then
    for f in ${files//,/ }; do
      docker run --rm -v "$vol:/v:ro" "$HELPER_IMAGE" sh -c "test -e /v/$f && tar -C /v -cf - ./$f || true" |
        tar -x -C "$TMP/$vname" 2>/dev/null || true
    done
  else
    # shellcheck disable=SC2086
    docker run --rm -v "$vol:/v:ro" "$HELPER_IMAGE" tar -C /v $excludes -cf - . | tar -x -C "$TMP/$vname"
  fi
  if [[ "$COMPRESS" == zstd ]]; then
    tar -C "$TMP" -cf - "$vname" | zstd -q -19 -o "$TMP/$vname.$EXT"
  else
    tar -C "$TMP" -czf "$TMP/$vname.$EXT" "$vname"
  fi
  rm -rf -- "$TMP/$vname" "$VTMP"
  VTMP=""
  FILES=("${FILES[@]}" "$vname.$EXT")
done

(cd "$TMP" && _sha256 "${FILES[@]}" >SHA256SUMS)
FILES=("${FILES[@]}" SHA256SUMS)

# 3. Encrypted package: the same files plus the secret files. The plain
#    copy of the secrets lives only in the 0700 temp dir; it is never printed.
if [[ -n "$RECIPIENTS_FILE" ]]; then
  log "encrypting the off-site copy"
  mkdir -p "$TMP/package/$STAMP/$SECRETS_NAME"
  for f in "${FILES[@]}"; do cp "$TMP/$f" "$TMP/package/$STAMP/"; done
  for entry in $SECRET_FILES; do
    IFS='|' read -r src name <<<"$entry"
    [[ -f "$src" ]] && cp "$src" "$TMP/package/$STAMP/$SECRETS_NAME/$name"
  done
  tar -C "$TMP/package" -cf - "$STAMP" | age -R "$RECIPIENTS_FILE" -o "$TMP/$STAMP.tar.age"
  [[ -s "$TMP/$STAMP.tar.age" ]] || fail "the encrypted package is empty"
  rm -rf -- "$TMP/package"
  mv "$TMP/$STAMP.tar.age" "$DEST/$LAYOUT_ENC/$STAMP.tar.age"
else
  log "no recipients: no encrypted copy"
fi

# 4. Publish only when everything above worked.
mkdir "$OUT"
for f in "${FILES[@]}"; do mv "$TMP/$f" "$OUT/"; done
log "done: $OUT ($(du -sh "$OUT" | cut -f1))"

# 5. Retention.
prune "$DEST"
log "on disk: $(ls -1 "$DEST/$LAYOUT_PLAIN" | wc -l) backups, $(du -sh "$DEST" | cut -f1)"
echo "PODSHIP_BACKUP_STAMP=$STAMP"
