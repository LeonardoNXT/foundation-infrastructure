#!/usr/bin/env bash

set -euo pipefail

FOUNDATION_ROOT="/opt/foundation"
FOUNDATION_INFRA="$FOUNDATION_ROOT/infra"
FOUNDATION_RELEASES="$FOUNDATION_ROOT/releases"
FOUNDATION_RUNTIME="$FOUNDATION_ROOT/runtime"

log() {
    echo "[BOOTSTRAP] $1"
}

fail() {
    echo "[ERROR] $1" >&2
    exit 1
}

check_root() {
    if (( EUID != 0 )); then
        fail "Bootstrap must run as root"
    fi
}

check_operating_system() {
    [[ -f /etc/os-release ]] ||
        fail "Cannot identify operating system"

    # shellcheck source=/dev/null
    source /etc/os-release

    if [[ "${ID:-}" != "amzn" || "${VERSION_ID:-}" != "2023" ]]; then
        fail "Amazon Linux 2023 is required"
    fi

    log "Amazon Linux 2023 detected"
}

detect_architecture() {
    case "$(uname -m)" in
        aarch64)
            ARCH="aarch64"
            COMPOSE_ARCH="aarch64"
            ;;
        x86_64)
            ARCH="x86_64"
            COMPOSE_ARCH="x86_64"
            ;;
        *)
            fail "Unsupported architecture: $(uname -m)"
            ;;
    esac

    log "Architecture detected: $ARCH"
}

install_dependencies() {
    log "Installing system dependencies"

    dnf install -y \
        git \
        tar \
        gzip \
        unzip \
        curl
}

install_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log "Installing Docker"
        dnf install -y docker
    else
        log "Docker already installed"
    fi

    systemctl enable --now docker
    systemctl is-active --quiet docker ||
        fail "Docker service is not running"

    log "Docker service ready"
}

install_compose() {
    if docker compose version >/dev/null 2>&1; then
        log "Docker Compose already installed"
        return 0
    fi

    log "Installing Docker Compose V2"

    local version="v2.39.4"
    local plugin_dir="/usr/local/lib/docker/cli-plugins"
    local plugin_path="$plugin_dir/docker-compose"

    mkdir -p "$plugin_dir"

    curl -fL --retry 3 \
        "https://github.com/docker/compose/releases/download/${version}/docker-compose-linux-${COMPOSE_ARCH}" \
        -o "$plugin_path"

    chmod 755 "$plugin_path"

    docker compose version >/dev/null 2>&1 ||
        fail "Docker Compose installation failed"

    log "Docker Compose ready"
}

install_aws_cli() {
    if command -v aws >/dev/null 2>&1; then
        if aws --version 2>&1 | grep -q "aws-cli/2"; then
            log "AWS CLI V2 already installed"
            return 0
        fi
    fi

    log "Installing AWS CLI V2"

    local temp_dir
    temp_dir="$(mktemp -d)"

    curl -fL --retry 3 \
        "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" \
        -o "$temp_dir/awscliv2.zip"

    unzip -q "$temp_dir/awscliv2.zip" -d "$temp_dir"

    "$temp_dir/aws/install" \
        --bin-dir /usr/local/bin \
        --install-dir /usr/local/aws-cli \
        --update

    rm -rf "$temp_dir"

    aws --version ||
        fail "AWS CLI installation failed"

    log "AWS CLI V2 ready"
}

prepare_directories() {
    log "Preparing Foundation directories"

    mkdir -p \
        "$FOUNDATION_INFRA" \
        "$FOUNDATION_RELEASES" \
        "$FOUNDATION_RUNTIME"

    chmod 755 "$FOUNDATION_ROOT"
    chmod 755 "$FOUNDATION_INFRA"
    chmod 755 "$FOUNDATION_RELEASES"
    chmod 700 "$FOUNDATION_RUNTIME"

    log "Foundation directories prepared"
}

main() {
    check_root

    log "Starting Foundation bootstrap"

    check_operating_system
    detect_architecture
    install_dependencies
    install_docker
    install_compose
    install_aws_cli
    prepare_directories

    log "Bootstrap completed successfully"
}

main "$@"