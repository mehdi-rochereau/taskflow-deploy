#!/usr/bin/env bash
#
# backup-db.sh - Automated logical backup of the TaskFlow production database.
#
# Runs unattended from a systemd timer, as user mehdi, owner of both the .env
# and the secret file it reads. Produces one dump per run in /home/mehdi/backups,
# verifies it, prunes its own dumps older than the retention window, and pushes
# a notification if anything fails.
#
# Deliberately NOT covered here, see issue #17:
#   - off-site copy: dumps stay on the VPS disk, an accepted trade-off
#   - compression, encryption at rest, checksums
#
# Exit codes: 0 success, non-zero failure. Every failure path notifies.

set -euo pipefail

# --- Configuration -----------------------------------------------------------
# Paths and identifiers are fixed rather than parameterised: this script serves
# exactly one stack on exactly one host, and options nobody sets are options
# nobody tests.

ENV_FILE="/opt/taskflow/.env"
# Same file Docker Compose mounts into taskflow-db and taskflow-api as a secret.
# Reading it here rather than duplicating the value into the .env keeps a single
# source: a rotation touches one file and every consumer follows. See issue #38.
SECRET_FILE="/home/mehdi/secrets/mysql_password"
BACKUP_DIR="/home/mehdi/backups"
CONTAINER="taskflow-db"
DB_NAME="taskflow"
RETENTION_DAYS=7

# Automated dumps carry their own prefix so that pruning can never reach the
# manual dumps taken by hand before a risky operation.
PREFIX="taskflow-auto"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
TARGET="${BACKUP_DIR}/${PREFIX}_${STAMP}.sql"
TMP="${TARGET}.part"

# --- Notification ------------------------------------------------------------
# ntfy is the only alert channel. A scheduled job has nobody watching its
# terminal: without a push, a broken backup stays broken silently.

notify_failure() {
    local reason="$1"
    # Missing topic must not abort the script: the backup outcome matters more
    # than the notification. It is logged instead.
    if [ -z "${NTFY_TOPIC:-}" ]; then
        echo "WARN: NTFY_TOPIC unset, cannot notify" >&2
        return 0
    fi
    curl -s --max-time 10 \
        -H "Title: TaskFlow backup FAILED" \
        -H "Priority: high" \
        -H "Tags: rotating_light" \
        -d "${reason}" \
        "https://ntfy.sh/${NTFY_TOPIC}" >/dev/null || \
        echo "WARN: notification could not be sent" >&2
}

# Any unexpected exit lands here. The trap is installed before the first
# fallible operation so that no failure can slip through unreported.
fail() {
    local msg="$1"
    echo "ERROR: ${msg}" >&2
    rm -f "${TMP}"          # a failed dump always leaves a truncated file behind
    notify_failure "${msg}"
    exit 1
}
trap 'fail "unexpected error on line ${LINENO}"' ERR

# --- Credentials -------------------------------------------------------------
# The password comes from the secret file, the rest from the .env. Sourcing the
# .env wholesale would pull every variable of the stack into this process
# environment for no reason: read_env takes the two .env keys actually needed.

read_env() {
    local key="$1" line
    line="$(grep -m1 "^${key}=" "${ENV_FILE}")" || return 1
    printf '%s' "${line#*=}"
}

[ -r "${ENV_FILE}" ]    || fail "cannot read ${ENV_FILE}"
[ -r "${SECRET_FILE}" ] || fail "cannot read ${SECRET_FILE}"

NTFY_TOPIC="$(read_env NTFY_TOPIC)" || NTFY_TOPIC=""
DB_USER="$(read_env DB_USERNAME)" || fail "DB_USERNAME missing from ${ENV_FILE}"
# $(< file) rather than $(cat file): no subprocess, and command substitution
# strips trailing newlines, so a file written with a stray line break still
# yields the exact password. A single parasitic byte here would produce an
# authentication failure whose cause is hard to spot.
MYSQL_PWD="$(< "${SECRET_FILE}")"
[ -n "${MYSQL_PWD}" ] || fail "${SECRET_FILE} is empty"
export MYSQL_PWD
# MYSQL_PWD is passed to docker by NAME, never as -p<value>: command-line
# arguments are world-readable in /proc for the lifetime of the process.

# --- Preflight ---------------------------------------------------------------

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

docker inspect -f '{{.State.Running}}' "${CONTAINER}" 2>/dev/null | grep -q true \
    || fail "container ${CONTAINER} is not running"

# --- Dump --------------------------------------------------------------------
# Options are identical to the manual procedure verified on 15 August 2026,
# documented in docs/04-securite/DATABASE_CREDENTIAL_ROTATION.md step 1:
#   --single-transaction  consistent snapshot without locking, production keeps
#                         serving throughout
#   --no-tablespaces      skips the InnoDB tablespace listing, which needs the
#                         server-wide PROCESS privilege the application account
#                         does not have and must not be granted
#   --routines --triggers --events
#                         mysqldump omits all three by default; a dump without
#                         them looks complete and is not

docker exec -i -e MYSQL_PWD "${CONTAINER}" \
    mysqldump -u "${DB_USER}" --single-transaction --no-tablespaces \
    --routines --triggers --events "${DB_NAME}" \
    > "${TMP}" \
    || fail "mysqldump exited non-zero"

# --- Verification ------------------------------------------------------------
# Three checks, same as the manual procedure. A dump that fails any of them is
# discarded rather than kept: a bad backup that looks like a good one is worse
# than no backup at all.

[ -s "${TMP}" ] || fail "dump is empty"

tail -1 "${TMP}" | grep -q '^-- Dump completed on' \
    || fail "dump is truncated, trailer missing"

DUMPED_TABLES="$(grep -c '^CREATE TABLE' "${TMP}")"
LIVE_TABLES="$(docker exec -i -e MYSQL_PWD "${CONTAINER}" \
    mysql -u "${DB_USER}" -N -e \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';")"

[ "${DUMPED_TABLES}" = "${LIVE_TABLES}" ] \
    || fail "table count mismatch: ${DUMPED_TABLES} dumped, ${LIVE_TABLES} live"

# Only a fully verified dump earns its final name. Anything watching this
# directory can therefore trust every file it finds there.
mv "${TMP}" "${TARGET}"
chmod 600 "${TARGET}"

# --- Retention ---------------------------------------------------------------
# -name restricts pruning to this script's own output. The manual dumps taken
# before risky operations use a different prefix and are never touched.

PRUNED="$(find "${BACKUP_DIR}" -maxdepth 1 -type f \
    -name "${PREFIX}_*.sql" -mtime "+${RETENTION_DAYS}" -print -delete | wc -l)"

echo "backup OK: ${TARGET} (${LIVE_TABLES} tables, ${PRUNED} old dump(s) pruned)"
exit 0