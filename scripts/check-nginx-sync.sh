#!/bin/bash
# Compare the versioned Nginx configuration with what is deployed on the server.
#
# Nginx does not read this repository. Every file under nginx/ is copied to
# /etc/nginx by hand, so the two drift apart the first time a fix is applied hot
# on the server, or the first time a copy silently fails. A copy that lies is
# worse than no copy: it gives the false assurance that restoring from the
# repository would bring production back.
#
# This is not a theoretical risk. During the deployment of issue #49 a failed
# git fetch let the copy commands run against stale files, nginx -t validated an
# unchanged configuration, and the deployment had every appearance of success.
# This script is what catches that.
#
# Run it from the repository root, on the server:
#   cd /opt/taskflow && ./scripts/check-nginx-sync.sh
#
# Exit code 0 means the two match, 1 means they do not. Nothing is written and
# nothing is reloaded: this script only ever reads.
#
# What it does NOT cover, deliberately, and what has to be checked by hand:
#   - /etc/nginx/nginx.conf, a dpkg conffile that is not versioned here. See
#     nginx/NGINX_CONF_CHANGES.md and `nginx -T | grep ssl_protocols`.
#   - the absence of the /etc/nginx/sites-enabled/default symlink, issue #37.
#     An absence cannot be versioned.
#   - which files are symlinked into sites-enabled. A vhost present in
#     sites-available and never enabled matches this check and serves nothing.
set -euo pipefail

# Resolve the repository root from this script's own location, so the script
# works regardless of the directory it is invoked from.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${REPO_ROOT}/nginx"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "ERROR: ${SOURCE_DIR} not found. Run this from the taskflow-deploy working copy."
    exit 1
fi

# Each versioned directory and the /etc/nginx directory it mirrors. The vhost
# names are listed one by one rather than globbed: sites-available also holds
# the Debian default file, which is not ours and must not be reported as an
# unexpected extra.
declare -a PAIRS=(
    "${SOURCE_DIR}/snippets/taskflow-acme.conf|/etc/nginx/snippets/taskflow-acme.conf"
    "${SOURCE_DIR}/snippets/taskflow-proxy.conf|/etc/nginx/snippets/taskflow-proxy.conf"
    "${SOURCE_DIR}/snippets/taskflow-security-headers.conf|/etc/nginx/snippets/taskflow-security-headers.conf"
    "${SOURCE_DIR}/snippets/taskflow-tls.conf|/etc/nginx/snippets/taskflow-tls.conf"
    "${SOURCE_DIR}/conf.d/10-hardening.conf|/etc/nginx/conf.d/10-hardening.conf"
    "${SOURCE_DIR}/sites-available/00-catch-all|/etc/nginx/sites-available/00-catch-all"
    "${SOURCE_DIR}/sites-available/taskflow|/etc/nginx/sites-available/taskflow"
    "${SOURCE_DIR}/sites-available/api-taskflow|/etc/nginx/sites-available/api-taskflow"
)

DIVERGENCES=0

for pair in "${PAIRS[@]}"; do
    src="${pair%%|*}"
    dst="${pair##*|}"

    if [ ! -f "$src" ]; then
        echo "MISSING IN REPO   ${src}"
        DIVERGENCES=$((DIVERGENCES + 1))
        continue
    fi

    if [ ! -f "$dst" ]; then
        echo "MISSING ON SERVER ${dst}"
        DIVERGENCES=$((DIVERGENCES + 1))
        continue
    fi

    # diff -q reports only whether the files differ. sudo is needed because the
    # /etc/nginx copies are owned by root; the repository copies are not.
    if ! sudo diff -q "$src" "$dst" > /dev/null 2>&1; then
        echo "DIVERGENT         ${dst}"
        DIVERGENCES=$((DIVERGENCES + 1))
    fi
done

echo ""

if [ "$DIVERGENCES" -eq 0 ]; then
    echo "OK: the ${#PAIRS[@]} versioned files match what is deployed."
    echo "Not covered by this check: nginx.conf, the default symlink, and which"
    echo "vhosts are enabled. See the header of this script."
    exit 0
fi

echo "${DIVERGENCES} divergence(s) found."
echo "Inspect one with: sudo diff <repo file> <server file>"
exit 1