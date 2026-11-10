#!/usr/bin/env bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
: "${DB_MYSQL_ROOT_PASSWORD:?}" "${DB_MYSQL_PASSWORD:?}" "${DB_POSTGRES_PASSWORD:?}"
# Restricted password alphabet avoids ambiguous URI/DSN parsing in this lab.
for v in DB_MYSQL_ROOT_PASSWORD DB_MYSQL_PASSWORD DB_POSTGRES_PASSWORD; do
  [[ "${!v}" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo "Use alphanumeric lab passwords"; exit 1; }
done
STATE_DIR="${STATE_DIR:-$PWD/state}"
mkdir -p "$STATE_DIR" backups
# Prevent concurrent local migrations as well as concurrent GitHub jobs.
LOCK_DIR="$STATE_DIR/migration.lock"
mkdir "$LOCK_DIR" 2>/dev/null || { echo "Migration is already running"; exit 1; }
trap 'rmdir "$LOCK_DIR"' EXIT
legacy() { docker compose -p shvedov-mm -f legacy/docker-compose.yml "$@"; }
prod() { docker compose -p shvedov-mm -f docker-compose.prod.yml "$@"; }
wait_api() {
  for ((i=0;i<120;i++)); do
    if curl --fail --silent http://localhost:8065/api/v4/system/ping >/dev/null; then return; fi
    sleep 3
  done
  echo "Mattermost did not become healthy"; return 1
}
if [[ ! -f "$STATE_DIR/.migration_completed" ]]; then
  # Stop writes before backup and keep the source volume for recovery.
  legacy up -d --wait mysql
  legacy stop mattermost
  legacy exec -T mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysqldump --default-character-set=utf8mb4 -u root --single-transaction --no-tablespaces mattermost' > "backups/mysql-$(date +%Y%m%d-%H%M%S).sql"
  test -s "$(ls -t backups/mysql-*.sql | head -1)"
  legacy exec -T mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql --default-character-set=utf8mb4 -N -u root mattermost -e "SELECT Id,Message FROM Posts ORDER BY Id"' > "$STATE_DIR/posts-before.tsv"
  test -s "$STATE_DIR/posts-before.tsv" || { echo "Create test posts before migration"; exit 1; }
  prod up -d --wait postgres
  # Recreate only the target schema on an interrupted migration; MySQL stays intact.
  prod exec -T postgres psql -v ON_ERROR_STOP=1 -U mmuser -d mattermost -c 'DROP SCHEMA IF EXISTS public CASCADE; DROP SCHEMA IF EXISTS mattermost CASCADE; CREATE SCHEMA public AUTHORIZATION mmuser; ALTER ROLE mmuser SET search_path TO public;'
  # Create the native PostgreSQL schema for the SOURCE version first.
  docker run --rm --platform linux/amd64 --network shvedov_mm_net \
    -e MM_SQLSETTINGS_DRIVERNAME=postgres \
    -e "MM_SQLSETTINGS_DATASOURCE=postgres://mmuser:${DB_POSTGRES_PASSWORD}@postgres:5432/mattermost?sslmode=disable" \
    mattermost/mattermost-team-edition:9.5.0 /mattermost/bin/mattermost db migrate
  docker run --rm --network shvedov_mm_net --platform "${PGLOADER_PLATFORM:-linux/amd64}" \
    -v "$STATE_DIR:/state" "${MIGRATION_IMAGE:-shvedov-migration-tools:1.0}" migration-assist pgloader \
    --mysql="mmuser:${DB_MYSQL_PASSWORD}@tcp(mysql:3306)/mattermost" \
    --postgres="postgres://mmuser:${DB_POSTGRES_PASSWORD}@postgres:5432/mattermost?sslmode=disable" \
    --remove-null-chars --output /state/migration.load
  chmod 600 "$STATE_DIR/migration.load"
  docker run --rm --network shvedov_mm_net --platform "${PGLOADER_PLATFORM:-linux/amd64}" \
    -v "$STATE_DIR/migration.load:/home/migration/migration.load:ro" \
    "${MIGRATION_IMAGE:-shvedov-migration-tools:1.0}" pgloader --on-error-stop /home/migration/migration.load
  # v0.0.2 generator quotes the complete schema list as one identifier; normalize it.
  prod exec -T postgres psql -v ON_ERROR_STOP=1 -U mmuser -d mattermost -c 'ALTER ROLE mmuser SET search_path TO public;'
  docker run --rm --network shvedov_mm_net --platform "${PGLOADER_PLATFORM:-linux/amd64}" \
    "${MIGRATION_IMAGE:-shvedov-migration-tools:1.0}" migration-assist postgres post-migrate \
    "postgres://mmuser:${DB_POSTGRES_PASSWORD}@postgres:5432/mattermost?sslmode=disable"
  # Compare all post IDs and texts before starting the target app.
  prod exec -T postgres psql -U mmuser -d mattermost -At -F $'\t' -c 'SELECT id,message FROM public.posts ORDER BY id' > "$STATE_DIR/posts-after.tsv"
  diff -u "$STATE_DIR/posts-before.tsv" "$STATE_DIR/posts-after.tsv"
  # Do not set the final success marker until the upgraded application passes.
  prod up -d --remove-orphans
  wait_api
  curl --fail --silent http://localhost:8065/ >/dev/null
  touch "$STATE_DIR/.migration_completed"
  echo "Migration verified; marker committed"
else
  echo "Migration already completed: skipping backup and pgloader"
  prod up -d --remove-orphans
  wait_api
fi
prod ps
