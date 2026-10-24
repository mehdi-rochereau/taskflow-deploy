#!/usr/bin/env bash
#
# prune-images.sh - Removes TaskFlow images no longer needed on the production VPS.
#
# Runs unattended from a systemd timer. Reads the Docker daemon, decides what to
# keep, and deletes the rest. Never touches a running container and never pulls.
#
# Why this exists: every deployment moves the `latest` tag onto a new image and
# leaves its predecessor untagged. Measured on 24 October 2026: eighty-six
# images for four running containers, 16.68 GB of which nearly all reclaimable.
# Saturation would surface as a failing `docker compose pull` whose apparent
# cause has nothing to do with the real one. See issue #52.
#
# Why NOT a bare `docker image prune`: deploy.sh records the immutable image id
# of the running container in /tmp/taskflow-deploy-rollback-<service>.env, and
# the pull that follows moves `latest` onto the new image. The recorded one
# therefore becomes untagged, which is exactly what a dangling prune deletes.
# The rollback would then exit on `recorded image is no longer present on this
# host`, and the defect would only surface at rollback time, which is the worst
# possible moment.
#
# Why NOT inside deploy.sh: that script deploys a service, one responsibility.
# A prune there would also be traversed in rollback mode, on a recovery path
# that must carry as few operations as possible, and a destructive operation on
# the critical path of a deployment can make a healthy deployment fail.
#
# Usage:
#   ./scripts/prune-images.sh
#   ./scripts/prune-images.sh --dry-run
#
# Exit codes: 0 success, non-zero failure.

set -euo pipefail

# --- Configuration -----------------------------------------------------------
# Fixed rather than parameterised: this script serves exactly one stack on
# exactly one host, and options nobody sets are options nobody tests.

SERVICES="taskflow-api taskflow-ui"
ROLLBACK_GLOB="/tmp/taskflow-deploy-rollback-*.env"

# Generations kept per service BEYOND the running image and the rollback
# reference. One, as a safety net: the automatic rollback only ever goes back a
# single step, and recovering further means pulling a sha-<commit> tag from the
# registry rather than relying on a surviving local image. Costs roughly 800 MB
# on a disk with 53 GB free.
KEEP_EXTRA=1

# --- Failure handling --------------------------------------------------------
# Installed before the first fallible operation. Output goes to the journal;
# there is no log file on the VPS.

fail() {
    echo "ERROR: $1" >&2
    exit 1
}
trap 'fail "unexpected error on line ${LINENO}"' ERR

usage() {
    echo "Usage: $0 [--dry-run]" >&2
    exit 2
}

# --- Arguments ---------------------------------------------------------------

DRY_RUN=0
if [ $# -ge 1 ]; then
    [ "$1" = "--dry-run" ] || usage
    DRY_RUN=1
fi
[ $# -le 1 ] || usage

# --- Preflight ---------------------------------------------------------------

command -v docker >/dev/null 2>&1 || fail "docker is not available"
docker info >/dev/null 2>&1 || fail "cannot reach the Docker daemon"

# --- What must survive -------------------------------------------------------
# Three independent sets, union of which is never deleted.

KEEP_FILE="$(mktemp)"
trap 'rm -f "${KEEP_FILE}"' EXIT

# 1. Every image a container was created from, running or stopped. {{.Image}}
#    gives the immutable id, not the tag, which is what every comparison below
#    uses.
docker ps -a --format '{{.ID}}' | while read -r container; do
    docker inspect "${container}" --format '{{.Image}}' 2>/dev/null || true
done >> "${KEEP_FILE}"

# 2. Every rollback reference deploy.sh has written. The glob may match nothing
#    on a host that has never deployed, which is not an error.
#    These files live in /tmp, which systemd clears on reboot: after a reboot a
#    rollback already exits with `No rollback reference`, independently of this
#    script. Known behaviour, see issue #52.
for ref in ${ROLLBACK_GLOB}; do
    [ -f "${ref}" ] || continue
    # The file holds a single PREVIOUS_IMAGE=<id> line. Read rather than sourced:
    # this script has no business executing the contents of a file in /tmp.
    sed -n 's/^PREVIOUS_IMAGE=//p' "${ref}" >> "${KEEP_FILE}"
done

# 3. Every image still carrying a tag of one of the two repositories, plus the
#    KEEP_EXTRA most recent untagged ones per service. Attribution of an
#    untagged image relies on the OCI source label that docker/metadata-action
#    writes at build time, verified present on 24 October 2026. Without it the
#    only alternative would be sorting by date across both services, which two
#    consecutive deployments of the same service would get wrong.
for service in ${SERVICES}; do
    repo="ghcr.io/mehdi-rochereau/${service}"
    source_url="https://github.com/mehdi-rochereau/${service}"

    # Tagged images of this repository, whatever the tag.
    docker images "${repo}" --format '{{.ID}}' >> "${KEEP_FILE}"

    # Untagged images attributed to this service, newest first, capped.
    #
    # Collected into a variable first, then filtered. A `while` piped into
    # `head` dies on SIGPIPE when head exits early, which pipefail reports as a
    # failure and the ERR trap turns into an abort. Same trap documented twice
    # in the CD workflow of taskflow-ui.
    #
    # The if/fi rather than `[ ... ] && echo`: the latter exits 1 whenever the
    # test fails, which is most iterations, and under set -e the last command of
    # a loop body exiting non-zero is enough to trigger the trap.
    DANGLING="$(docker images --filter dangling=true --format '{{.ID}}')"
    MATCHED=""
    while read -r id; do
        [ -n "${id}" ] || continue
        label="$(docker image inspect "${id}" \
            --format '{{index .Config.Labels "org.opencontainers.image.source"}}' 2>/dev/null || true)"
        if [ "${label}" = "${source_url}" ]; then
            MATCHED="${MATCHED}${id}"$'\n'
        fi
    done <<< "${DANGLING}"
    printf '%s' "${MATCHED}" | head -n "${KEEP_EXTRA}" >> "${KEEP_FILE}"
done

# Image ids appear in several forms: a full sha256:<64> from docker inspect, a
# short 12-character id from docker images. Everything is normalised to the
# short form before comparison, or the two would never match.
normalise() {
    sed 's/^sha256://' | cut -c1-12 | sort -u
}

KEEP="$(normalise < "${KEEP_FILE}")"

# --- What goes ---------------------------------------------------------------
# Every TaskFlow image, tagged or not, minus everything above. Images that are
# neither tagged by us nor labelled as ours are left alone: mysql:8.4 and any
# base layer are none of this script's business.

CANDIDATES="$(
    {
        for service in ${SERVICES}; do
            docker images "ghcr.io/mehdi-rochereau/${service}" --format '{{.ID}}'
        done
        docker images --filter dangling=true --format '{{.ID}}' | while read -r id; do
            label="$(docker image inspect "${id}" \
                --format '{{index .Config.Labels "org.opencontainers.image.source"}}' 2>/dev/null || true)"
            case "${label}" in
                https://github.com/mehdi-rochereau/taskflow-*) echo "${id}" ;;
            esac
        done
    } | normalise
)"

# comm needs both sides sorted, which normalise guarantees.
DOOMED="$(comm -23 <(printf '%s\n' "${CANDIDATES}") <(printf '%s\n' "${KEEP}"))"

if [ -z "${DOOMED}" ]; then
    echo "Nothing to prune: $(printf '%s\n' "${KEEP}" | wc -l) image(s) kept."
    exit 0
fi

COUNT="$(printf '%s\n' "${DOOMED}" | wc -l)"

if [ "${DRY_RUN}" -eq 1 ]; then
    echo "Dry run, ${COUNT} image(s) would be removed:"
    printf '%s\n' "${DOOMED}" | while read -r id; do
        docker images --format '{{.ID}}  {{.Repository}}:{{.Tag}}  {{.Size}}  {{.CreatedSince}}' \
            | grep "^${id}" || echo "${id}"
    done
    echo "Kept: $(printf '%s\n' "${KEEP}" | wc -l) image(s)."
    exit 0
fi

# --- Removal -----------------------------------------------------------------
# One call per image rather than one batched call: a single refusal, typically
# an image still referenced by something this script did not anticipate, must
# not abort the whole run. Failures are counted and reported, never hidden.
#
# Here-string and not a pipe. A while fed by a pipe runs in a subshell, and
# every counter incremented inside it is lost on exit. Same trap documented in
# the CD workflow of taskflow-ui.

REMOVED=0
REFUSED=0
while read -r id; do
    [ -n "${id}" ] || continue
    if docker image rm "${id}" >/dev/null 2>&1; then
        REMOVED=$((REMOVED + 1))
    else
        echo "NOTICE: docker refused to remove ${id}, left in place"
        REFUSED=$((REFUSED + 1))
    fi
done <<< "${DOOMED}"

KEPT="$(printf '%s\n' "${KEEP}" | wc -l)"
echo "Prune complete: ${REMOVED} removed, ${REFUSED} refused, ${KEPT} image(s) kept."
docker system df
exit 0