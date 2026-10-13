#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly COMPOSE_FILE="$PROJECT_DIR/compose.prod.yml"

log() {
    printf '[Foundation] %s\n' "$*"
}

fail() {
    printf '[Foundation] ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 \
        || fail "Required command not found: $1"
}

check_requirements() {
    log "Checking requirements..."

    [[ "$EUID" -eq 0 ]] \
        || fail "This script must run as root"

    [[ -f "$COMPOSE_FILE" ]] \
        || fail "Compose file not found: $COMPOSE_FILE"

    require_command docker

    docker compose version >/dev/null 2>&1 \
        || fail "Docker Compose is not available"

    docker info >/dev/null 2>&1 \
        || fail "Docker daemon is not running"
}

stop_services() {
    log "Stopping Foundation services..."

    docker compose \
        -f "$COMPOSE_FILE" \
        -p foundation \
        stop --timeout 60 \
        || fail "Failed to stop Foundation services"
}

show_status() {
    log "Foundation services status:"

    docker compose \
        -f "$COMPOSE_FILE" \
        -p foundation \
        ps --all
}

main() {
    log "Stopping Foundation infrastructure..."

    check_requirements
    stop_services
    show_status

    log "Foundation shutdown completed."
}

main "$@"
