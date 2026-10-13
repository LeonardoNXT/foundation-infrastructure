#!/usr/bin/env bash
set -euo pipefail

readonly RELEASE_SHA="${1:-}"
readonly STAGING_DIR="${2:-}"

readonly FOUNDATION_ROOT="/opt/foundation"
readonly RELEASES_DIR="$FOUNDATION_ROOT/releases"
readonly RUNTIME_DIR="$FOUNDATION_ROOT/runtime"
readonly CURRENT_LINK="$FOUNDATION_ROOT/current"
readonly LOCK_FILE="$RUNTIME_DIR/deploy.lock"

log() {
    printf '[Foundation Deploy] %s\n' "$*"
}

fail() {
    printf '[Foundation Deploy] ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 \
        || fail "Required command not found: $1"
}

check_requirements() {
    [[ "$EUID" -eq 0 ]] \
        || fail "Deploy must run as root"

    [[ "$RELEASE_SHA" =~ ^[a-f0-9]{40}$ ]] \
        || fail "Invalid release SHA"

    [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]] \
        || fail "Staging directory not found"

    require_command docker
    require_command sha256sum
    require_command flock

    docker compose version >/dev/null 2>&1 \
        || fail "Docker Compose unavailable"

    docker info >/dev/null 2>&1 \
        || fail "Docker daemon unavailable"

    [[ -d "$RELEASES_DIR" ]] \
        || fail "Run bootstrap.sh before deployment"

    install -d -m 0700 "$RUNTIME_DIR"
}

acquire_lock() {
    exec 9>"$LOCK_FILE"

    flock -n 9 \
        || fail "Another deployment is already running"

    log "Deployment lock acquired."
}

verify_artifact() {
    log "Verifying release artifact..."

    (
        cd "$STAGING_DIR"
        sha256sum -c foundation-infra.tar.gz.sha256
    ) || fail "Artifact checksum verification failed"

    [[ -f "$STAGING_DIR/compose.prod.yml" ]] \
        || fail "Missing compose.prod.yml"

    local script

    for script in start.sh load-secrets.sh stop.sh deploy.sh; do
        [[ -f "$STAGING_DIR/scripts/$script" ]] \
            || fail "Missing script: $script"
    done
}

prepare_release() {
    local release_dir="$RELEASES_DIR/$RELEASE_SHA"

    if [[ -e "$release_dir" ]]; then
        fail "Release already exists: $RELEASE_SHA"
    fi

    log "Installing release $RELEASE_SHA..."

    mv -- "$STAGING_DIR" "$release_dir"

    chmod 0755 "$release_dir/scripts/"*.sh
}

start_release() {
    local release_dir="$RELEASES_DIR/$RELEASE_SHA"

    log "Starting release..."

    bash "$release_dir/scripts/start.sh" \
        || fail "Release startup failed"
}

activate_release() {
    local release_dir="$RELEASES_DIR/$RELEASE_SHA"
    local temporary_link="$FOUNDATION_ROOT/.current.next"

    log "Activating verified release..."

    ln -sfn "$release_dir" "$temporary_link"
    mv -Tf "$temporary_link" "$CURRENT_LINK"
}

main() {
    log "Starting Foundation deployment..."

    check_requirements
    acquire_lock
    verify_artifact
    prepare_release
    start_release
    activate_release

    log "Deployment completed successfully."
    log "Active release: $RELEASE_SHA"
}

main "$@"
