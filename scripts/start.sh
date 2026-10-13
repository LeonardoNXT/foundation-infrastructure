#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly COMPOSE_FILE="$PROJECT_DIR/compose.prod.yml"
readonly SECRETS_DIR="/var/lib/foundation/secrets"

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

    [[ -f "$SCRIPT_DIR/load-secrets.sh" ]] \
        || fail "load-secrets.sh not found"

    require_command docker
    require_command aws

    docker compose version >/dev/null 2>&1 \
        || fail "Docker Compose is not available"

    docker info >/dev/null 2>&1 \
        || fail "Docker daemon is not running"
}

load_secrets() {
    log "Loading secrets from AWS Parameter Store..."

    bash "$SCRIPT_DIR/load-secrets.sh" \
        || fail "Failed to load secrets"

    local secret

    for secret in \
        postgres_password \
        redis.conf \
        minio_root_user \
        minio_root_password
    do
        [[ -s "$SECRETS_DIR/$secret" ]] \
            || fail "Missing or empty secret file: $secret"
    done

    log "Secret files prepared."
}

load_configuration() {
    log "Loading PostgreSQL configuration..."

    POSTGRES_USER="$(aws ssm get-parameter \
        --name "/foundation/production/postgres/user" \
        --with-decryption \
        --region "${AWS_REGION:-sa-east-1}" \
        --query "Parameter.Value" \
        --output text)" \
        || fail "Failed to load PostgreSQL user"

    POSTGRES_DB="$(aws ssm get-parameter \
        --name "/foundation/production/postgres/database" \
        --with-decryption \
        --region "${AWS_REGION:-sa-east-1}" \
        --query "Parameter.Value" \
        --output text)" \
        || fail "Failed to load PostgreSQL database"

    [[ -n "$POSTGRES_USER" && "$POSTGRES_USER" != "None" ]] \
        || fail "Invalid PostgreSQL user"

    [[ -n "$POSTGRES_DB" && "$POSTGRES_DB" != "None" ]] \
        || fail "Invalid PostgreSQL database"

    export POSTGRES_USER POSTGRES_DB

    log "PostgreSQL configuration loaded."
}

validate_compose() {
    log "Validating Docker Compose configuration..."

    docker compose \
        -f "$COMPOSE_FILE" \
        config --quiet \
        || fail "Invalid Docker Compose configuration"
}

verify_services() {
    log "Verifying Foundation containers..."

    local service
    local container_id
    local status
    local health
    local attempt
    local ready

    for service in postgres redis minio kafka; do
        container_id="$(docker compose \
            -f "$COMPOSE_FILE" \
            -p foundation \
            ps -q "$service")"

        [[ -n "$container_id" ]] \
            || fail "Container not found: $service"

        ready=false

        for ((attempt = 1; attempt <= 30; attempt++)); do
            status="$(docker inspect \
                --format '{{.State.Status}}' "$container_id")"

            health="$(docker inspect \
                --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
                "$container_id")"

            if [[ "$status" == "running" && \
                  ( "$health" == "healthy" || "$health" == "none" ) ]]; then
                ready=true
                break
            fi

            if [[ "$status" == "exited" || "$status" == "dead" ]]; then
                fail "Service $service stopped unexpectedly"
            fi

            sleep 2
        done

        [[ "$ready" == true ]] \
            || fail "Service $service did not become ready"

        log "$service: running (health: $health)"
    done
}

start_services() {
    log "Starting Foundation services..."

    docker compose \
        -f "$COMPOSE_FILE" \
        -p foundation \
        up -d \
        || fail "Failed to start Foundation services"
}

show_status() {
    log "Foundation services status:"

    docker compose \
        -f "$COMPOSE_FILE" \
        ps
}

main() {
    log "Starting Foundation infrastructure..."

    check_requirements
    load_secrets
    load_configuration
    validate_compose
    start_services
    verify_services
    show_status

    log "Foundation startup completed."
}

main "$@"
