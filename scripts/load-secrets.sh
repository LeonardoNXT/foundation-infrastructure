#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-sa-east-1}"
PARAMETER_PREFIX="/foundation/production"
SECRETS_DIR="/var/lib/foundation/secrets"

umask 077

if [[ "$EUID" -ne 0 ]]; then
    echo "Error: run as root" >&2
    exit 1
fi

install -d -m 0700 "$SECRETS_DIR"

load_parameter() {
    local parameter_name="$1"
    local value

    value="$(aws ssm get-parameter \
        --name "${PARAMETER_PREFIX}/${parameter_name}" \
        --with-decryption \
        --region "$AWS_REGION" \
        --query "Parameter.Value" \
        --output text)" || return 1

    if [[ -z "$value" || "$value" == "None" ]]; then
        echo "Error: empty parameter: $parameter_name" >&2
        return 1
    fi

    printf '%s' "$value"
}

write_secret() {
    local parameter_name="$1"
    local filename="$2"
    local value

    value="$(load_parameter "$parameter_name")" || return 1

    printf '%s' "$value" > "$SECRETS_DIR/$filename"
    chmod 0600 "$SECRETS_DIR/$filename"
}

write_secret "postgres/password" "postgres_password"
write_secret "minio/root-user" "minio_root_user"
write_secret "minio/root-password" "minio_root_password"

redis_password="$(load_parameter "redis/password")"

if [[ "$redis_password" == *$'\n'* || "$redis_password" == *$'\r'* ]]; then
    echo "Error: Redis password contains a newline" >&2
    exit 1
fi

redis_password="${redis_password//\\/\\\\}"
redis_password="${redis_password//\"/\\\"}"

printf 'appendonly yes\nrequirepass "%s"\n' \
    "$redis_password" > "$SECRETS_DIR/redis.conf"

chmod 0600 "$SECRETS_DIR/redis.conf"
unset redis_password

echo "Foundation secrets prepared successfully."