#!/usr/bin/env bash
#
# deploy.sh - Deploys one TaskFlow application service on the production VPS.
#
# Called by the CD pipelines of taskflow-api and taskflow-ui over SSH, after
# they have brought this working copy up to date. Also usable by hand.
#
# Usage:
#   ./scripts/deploy.sh <service>
#   ./scripts/deploy.sh <service> --rollback
#
# Deliberately NOT covered here, see issue #21:
#   - updating this repository: the caller runs `git pull --ff-only` BEFORE
#     invoking this script. Bash reads a script incrementally, keeping an offset
#     into the file; a script that replaces itself mid-run resumes at the wrong
#     byte and executes a truncated line instead of failing outright
#   - taskflow-db: never pulled and never recreated. Two separate guarantees,
#     conflated in the first version of this script, which claimed the second
#     while implementing only the first. A `docker compose pull` with no service
#     argument would fetch a new mysql:8.4 patch release whenever one ships:
#     that is what restricting the pull prevents. Independently, `up -d` brings
#     up the services declared in `depends_on` and recreates any whose
#     configuration has drifted from the running container: that is what
#     `--no-deps` prevents. On 18 August 2026 the database was recreated during
#     an application deployment for exactly that reason. See issue #33
#   - starting the database: `--no-deps` also drops the `service_healthy`
#     condition Compose would otherwise wait on, so this script checks the
#     database itself and refuses to deploy against an unhealthy one. It never
#     starts, restarts or repairs it
#   - whole-stack deployment: rebuilding everything happens after an incident or
#     a restore, with someone watching. It is a manual `docker compose up -d`,
#     documented in avancement.md, not a shortcut reachable from a pipeline
#   - health checking: the caller owns it. It queries the public URL through
#     Nginx and TLS, which this script cannot see from inside the VPS
#
# This script causes a short interruption of the named service: `up -d`
# recreates the container. Nothing here is zero-downtime.
#
# Exit codes: 0 success, non-zero failure.

set -euo pipefail

# --- Configuration -----------------------------------------------------------
# Fixed rather than parameterised: this script serves exactly one stack on
# exactly one host, and options nobody sets are options nobody tests.

DEPLOY_DIR="/opt/taskflow"
COMPOSE_FILE="${DEPLOY_DIR}/docker-compose.yml"
ENV_FILE="${DEPLOY_DIR}/.env"

# db/init became part of the deployment path on 17 August 2026. Compose creates
# a missing bind mount source as an empty directory without warning, so a deploy
# from an incomplete working copy would leave the database without its
# healthcheck account on the next rebuild, with no visible error anywhere.
INIT_FILE="${DEPLOY_DIR}/db/init/01-healthcheck-account.sql"

# Only the two application services. taskflow-db is not in this list on purpose.
ALLOWED_SERVICES="taskflow-api taskflow-ui"

# The dependency both application services declare in `depends_on`. Named here
# because this script must observe it, never act on it.
DB_SERVICE="taskflow-db"

# --- Failure handling --------------------------------------------------------
# Installed before the first fallible operation. Output goes to stdout and is
# captured by the calling pipeline; there is no log file on the VPS.

fail() {
    echo "ERROR: $1" >&2
    exit 1
}
trap 'fail "unexpected error on line ${LINENO}"' ERR

usage() {
    echo "Usage: $0 <${ALLOWED_SERVICES// /|}> [--rollback]" >&2
    exit 2
}

# --- Arguments ---------------------------------------------------------------
# A missing service is an invocation mistake, not a request to deploy
# everything. Refusing is the only safe reading.

[ $# -ge 1 ] || usage

SERVICE="$1"
MODE="deploy"

case " ${ALLOWED_SERVICES} " in
    *" ${SERVICE} "*) ;;
    *) echo "ERROR: unknown service '${SERVICE}'" >&2; usage ;;
esac

if [ $# -ge 2 ]; then
    [ "$2" = "--rollback" ] || usage
    MODE="rollback"
fi

[ $# -le 2 ] || usage

# One rollback reference per service. A single shared path would let a UI
# deployment overwrite the API's restore point.
ROLLBACK_FILE="/tmp/taskflow-deploy-rollback-${SERVICE}.env"

# --- Preflight ---------------------------------------------------------------
# Checked in both modes: a rollback that runs from an incomplete working copy
# is as dangerous as a deployment that does.

[ -f "${COMPOSE_FILE}" ] || fail "docker-compose.yml not found at ${COMPOSE_FILE}"
[ -f "${ENV_FILE}" ]     || fail ".env not found at ${ENV_FILE}"
[ -f "${INIT_FILE}" ]    || fail "database init script not found at ${INIT_FILE}"

cd "${DEPLOY_DIR}"
# No -f and no --env-file: Compose already resolves both from the working
# directory. Passing them again is noise that can drift out of sync.

# --- Database dependency -----------------------------------------------------
# Reports the health status of the database container, or `absent` when there is
# no such container. `docker inspect` fails on an unknown container and returns
# an empty string for one without a healthcheck; both land on `absent`, which is
# the right reading for a dependency this script cannot rely on.

db_health() {
    local status
    status="$(docker inspect "${DB_SERVICE}" --format='{{.State.Health.Status}}' 2>/dev/null)" \
        || status=""
    printf '%s' "${status:-absent}"
}

# --- Rollback ----------------------------------------------------------------

if [ "${MODE}" = "rollback" ]; then
    echo "Rolling back ${SERVICE} ..."

    # Observed, never enforced. A rollback runs when production is already
    # broken, and every added condition is one more way not to recover. A
    # restored container waiting for its database is a better outcome than a
    # refused rollback leaving the failing version in place; Hikari reopens its
    # connections on its own once the database returns. The state is printed so
    # that whoever reads these logs does not go looking elsewhere.
    DB_STATUS="$(db_health)"
    if [ "${DB_STATUS}" != "healthy" ]; then
        echo "NOTICE: ${DB_SERVICE} is '${DB_STATUS}', rolling back anyway."
    fi

    if [ ! -f "${ROLLBACK_FILE}" ]; then
        echo "No rollback reference for ${SERVICE}, nothing to restore."
        exit 0
    fi

    # `set -u` aborts on an undefined variable, so the default is set before
    # sourcing rather than after.
    PREVIOUS_IMAGE=""
    # shellcheck source=/dev/null
    source "${ROLLBACK_FILE}"

    if [ -z "${PREVIOUS_IMAGE}" ]; then
        echo "No previous image recorded for ${SERVICE}, cannot roll back."
        echo "This is the expected state on a first deployment."
        exit 0
    fi

    # The tag reference the compose file resolves for this service. This is the
    # one legitimate use of Config.Image: as the retag TARGET. Reading it as the
    # restore SOURCE is the bug this script exists to remove, since `latest`
    # already points at the new image by the time a rollback runs.
    RETAG_REF="$(docker inspect "${SERVICE}" --format='{{.Config.Image}}')" \
        || fail "cannot read the image reference of ${SERVICE}"

    docker image inspect "${PREVIOUS_IMAGE}" >/dev/null 2>&1 \
        || fail "recorded image ${PREVIOUS_IMAGE} is no longer present on this host"

    echo "Restoring ${PREVIOUS_IMAGE} as ${RETAG_REF}"
    docker compose stop "${SERVICE}"
    docker tag "${PREVIOUS_IMAGE}" "${RETAG_REF}"
    docker compose up -d "${SERVICE}"

    echo "Rollback complete: ${SERVICE} runs ${PREVIOUS_IMAGE}"
    exit 0
fi

# --- Deploy ------------------------------------------------------------------

echo "Deploying ${SERVICE} ..."

# Enforced here, unlike in rollback mode. `--no-deps` below removes the
# `service_healthy` condition Compose would have waited on, so nothing else
# guarantees the database is reachable when the container starts. Deploying
# against an unhealthy database would leave the application unable to open its
# connection pool, with a green pipeline until the caller's health check times
# out three minutes later. Checked before anything is pulled or written.
DB_STATUS="$(db_health)"
[ "${DB_STATUS}" = "healthy" ] \
    || fail "${DB_SERVICE} is '${DB_STATUS}', expected 'healthy'. Deployment refused."

# Immutable local image ID of the running container. {{.Image}} returns the
# sha256 of the image the container was created from, which keeps pointing at
# the old image after `latest` has moved. {{.Config.Image}} returns the tag
# instead, and restoring a tag that already resolves to the new image is a
# silent no-op. `|| echo ""` keeps a first deployment, with no container yet,
# from aborting under `set -e`.
PREVIOUS_IMAGE="$(docker inspect "${SERVICE}" --format='{{.Image}}' 2>/dev/null || echo "")"

# Variable name written here must match the one read after `source` above.
# Shell variables are case sensitive.
printf 'PREVIOUS_IMAGE=%s\n' "${PREVIOUS_IMAGE}" > "${ROLLBACK_FILE}"
echo "Rollback reference: ${PREVIOUS_IMAGE:-<none, first deployment>}"

# Explicit guard rather than relying on `set -e` alone: it turns a registry
# error into a labelled failure in the pipeline logs. A refused pull followed by
# a no-op `up -d` and an unconditional success message is how a green build once
# left production running the previous image.
echo "Pulling ${SERVICE} ..."
if ! docker compose pull "${SERVICE}"; then
    echo "Deployment aborted: docker compose pull was refused by the registry." >&2
    echo "Check the ghcr.io credentials on this host (docker login ghcr.io)." >&2
    exit 1
fi

# Recreates the container only if the resolved image changed. `--no-deps`
# restricts the action to this service: without it, Compose brings up everything
# in `depends_on` and recreates any container whose configuration has drifted
# from the compose file, which is how the production database came to be
# recreated during an application deployment on 18 August 2026.
#
# The consequence is that a change to the taskflow-db service in the compose
# file will never reach production through a deployment. That is deliberate, and
# it means such a change must be applied by hand, knowingly, with a manual dump
# taken first. The procedure is in avancement.md.
docker compose up -d --no-deps "${SERVICE}"

echo "Deployment of ${SERVICE} completed, health verification is the caller's."
exit 0