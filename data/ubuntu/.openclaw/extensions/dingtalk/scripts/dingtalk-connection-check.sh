#!/usr/bin/env bash

set -euo pipefail

DEFAULT_CONFIG="$HOME/.openclaw/openclaw.json"
CLIENT_ID=""
CLIENT_SECRET=""
CONFIG_PATH=""
ACCOUNT_ID=""
TIMEOUT="10"
JSON_OUTPUT="false"

usage() {
    cat <<'EOF'
Usage:
  bash scripts/dingtalk-connection-check.sh --client-id <id> --client-secret <secret>
  bash scripts/dingtalk-connection-check.sh --config <openclaw.json>
  bash scripts/dingtalk-connection-check.sh --config <openclaw.json> --account-id <id>

Options:
  --client-id       Explicit DingTalk client ID
  --client-secret   Explicit DingTalk client secret
  --config          Path to openclaw.json (default: ~/.openclaw/openclaw.json)
  --account-id      Optional DingTalk account ID under channels.dingtalk.accounts
  --timeout         Request timeout seconds (default: 10)
  --json            Pretty-print sanitized JSON if jq is available
  --help            Show this help

Resolution order:
  1. explicit --client-id/--client-secret
  2. --config path
  3. default ~/.openclaw/openclaw.json

Notes:
- The script inherits proxy settings from environment variables: HTTP_PROXY / HTTPS_PROXY / NO_PROXY.
- For corporate environments, ensure WebSocket/WSS proxies support Upgrade semantics when later testing stream connections.
EOF
}

mask_value() {
    local value="${1:-}"
    if [ -z "$value" ]; then
        printf '%s\n' ""
        return
    fi
    local length=${#value}
    if [ "$length" -le 8 ]; then
        printf '%s\n' "***"
        return
    fi
    printf '%s...%s\n' "${value:0:4}" "${value:length-4:4}"
}

require_python3() {
    if ! command -v python3 >/dev/null 2>&1; then
        printf '%s\n' "python3 is required for JSON parsing in this script." >&2
        exit 1
    fi
}

resolve_from_config() {
    local config_path="$1"
    local account_id="$2"

    python3 - "$config_path" "$account_id" <<'PY'
import json
import os
import sys

config_path = os.path.expanduser(sys.argv[1])
account_id = sys.argv[2]

if not os.path.exists(config_path):
    print(json.dumps({"ok": False, "error": f"Config file not found: {config_path}"}))
    raise SystemExit(0)

with open(config_path, "r", encoding="utf-8") as fh:
    raw = json.load(fh)

dingtalk = ((raw.get("channels") or {}).get("dingtalk") or {})
selected = dingtalk
source = "default"

if account_id:
    accounts = dingtalk.get("accounts") or {}
    if account_id not in accounts:
        print(json.dumps({
            "ok": False,
            "error": f"Account ID '{account_id}' not found under channels.dingtalk.accounts",
        }))
        raise SystemExit(0)
    selected = accounts[account_id] or {}
    source = f"account:{account_id}"

client_id = selected.get("clientId") or ""
client_secret = selected.get("clientSecret") or ""

if not client_id or not client_secret:
    print(json.dumps({
        "ok": False,
        "error": "clientId/clientSecret not found in resolved DingTalk config",
        "source": source,
    }))
    raise SystemExit(0)

print(json.dumps({
    "ok": True,
    "clientId": client_id,
    "clientSecret": client_secret,
    "source": source,
    "configPath": config_path,
}))
PY
}

read_json_field() {
    local field="$1"
    python3 -c 'import json,sys; data=json.load(sys.stdin); value=data.get(sys.argv[1], ""); print(value if value is not None else "")' "$field"
}

sanitize_json() {
    python3 - <<'PY'
import json
import sys

text = sys.stdin.read().strip()
if not text:
    print("")
    raise SystemExit(0)

try:
    data = json.loads(text)
except json.JSONDecodeError:
    print(text)
    raise SystemExit(0)

def mask(value: str) -> str:
    if len(value) <= 8:
        return "***"
    return f"{value[:4]}...{value[-4:]}"

def visit(value):
    if isinstance(value, dict):
        out = {}
        for key, item in value.items():
            lowered = key.lower()
            if lowered in {"clientsecret", "access_token", "accesstoken", "ticket", "token"} and isinstance(item, str):
                out[key] = mask(item)
            else:
                out[key] = visit(item)
        return out
    if isinstance(value, list):
        return [visit(item) for item in value]
    return value

print(json.dumps(visit(data), ensure_ascii=False))
PY
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --client-id)
            CLIENT_ID="${2:-}"
            shift 2
            ;;
        --client-secret)
            CLIENT_SECRET="${2:-}"
            shift 2
            ;;
        --config)
            CONFIG_PATH="${2:-}"
            shift 2
            ;;
        --account-id)
            ACCOUNT_ID="${2:-}"
            shift 2
            ;;
        --timeout)
            TIMEOUT="${2:-10}"
            shift 2
            ;;
        --json)
            JSON_OUTPUT="true"
            shift 1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ -n "$CLIENT_ID" ] && [ -z "$CLIENT_SECRET" ]; then
    printf '%s\n' "--client-secret is required when --client-id is provided." >&2
    exit 1
fi

if [ -n "$CLIENT_SECRET" ] && [ -z "$CLIENT_ID" ]; then
    printf '%s\n' "--client-id is required when --client-secret is provided." >&2
    exit 1
fi

SOURCE_LABEL="args"
if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    require_python3
    if [ -z "$CONFIG_PATH" ]; then
        CONFIG_PATH="$DEFAULT_CONFIG"
    fi

    CONFIG_RESULT="$(resolve_from_config "$CONFIG_PATH" "$ACCOUNT_ID")"
    CONFIG_OK="$(printf '%s' "$CONFIG_RESULT" | read_json_field ok)"
    if [ "$CONFIG_OK" != "True" ] && [ "$CONFIG_OK" != "true" ]; then
        printf '%s\n' "Failed to resolve credentials: $(printf '%s' "$CONFIG_RESULT" | read_json_field error)" >&2
        exit 1
    fi

    CLIENT_ID="$(printf '%s' "$CONFIG_RESULT" | read_json_field clientId)"
    CLIENT_SECRET="$(printf '%s' "$CONFIG_RESULT" | read_json_field clientSecret)"
    SOURCE_LABEL="$(printf '%s' "$CONFIG_RESULT" | read_json_field source)"
    CONFIG_PATH="$(printf '%s' "$CONFIG_RESULT" | read_json_field configPath)"
fi

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    printf '%s\n' "Unable to resolve clientId/clientSecret." >&2
    exit 1
fi

require_python3
PAYLOAD="$(python3 - "$CLIENT_ID" "$CLIENT_SECRET" <<'PY'
import json
import sys

print(json.dumps({
    "clientId": sys.argv[1],
    "clientSecret": sys.argv[2],
    "subscriptions": [
        {"type": "CALLBACK", "topic": "/v1.0/im/bot/messages/get"}
    ],
}))
PY
)"

BODY_FILE="$(mktemp)"
cleanup() {
    rm -f "$BODY_FILE"
}
trap cleanup EXIT

HTTP_STATUS="$(curl -sS -o "$BODY_FILE" -w "%{http_code}" \
    -X POST "https://api.dingtalk.com/v1.0/gateway/connections/open" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    --max-time "$TIMEOUT" \
    --data "$PAYLOAD" 2>/dev/null || true)"

RAW_BODY="$(cat "$BODY_FILE")"
SANITIZED_BODY="$(printf '%s' "$RAW_BODY" | sanitize_json)"

printf '%s\n' "DingTalk connection check"
printf 'credential_source=%s\n' "$SOURCE_LABEL"
if [ -n "$CONFIG_PATH" ]; then
    printf 'config_path=%s\n' "$CONFIG_PATH"
fi
printf 'account_id=%s\n' "$ACCOUNT_ID"
printf 'client_id=%s\n' "$(mask_value "$CLIENT_ID")"
printf 'http_status=%s\n' "${HTTP_STATUS:-000}"
if [ "$JSON_OUTPUT" = "true" ] && command -v jq >/dev/null 2>&1; then
    # Pretty-print sanitized JSON if possible
    PRETTY="$(printf '%s' "$SANITIZED_BODY" | jq '.')" || PRETTY="$SANITIZED_BODY"
    printf 'response_json=%s\n' "$PRETTY"
else
    printf 'response=%s\n' "$SANITIZED_BODY"
fi

if [ "$HTTP_STATUS" = "200" ]; then
    ENDPOINT="$(printf '%s' "$RAW_BODY" | read_json_field endpoint)"
    TICKET="$(printf '%s' "$RAW_BODY" | read_json_field ticket)"
    if [ -n "$ENDPOINT" ]; then
        printf 'endpoint=%s\n' "$ENDPOINT"
    fi
    if [ -n "$TICKET" ]; then
        printf 'ticket=%s\n' "$(mask_value "$TICKET")"
    fi
    exit 0
fi

exit 1
