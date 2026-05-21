#!/usr/bin/env bash
# CardShow Pro — one-command device installer.
#
# Detects your Mac's IP, starts the backend, finds the connected iPhone,
# builds + signs + installs + launches the app. No Xcode UI needed.
#
# First run will prompt for your Apple Developer Team ID (saved locally).
# Find yours: Xcode → Settings → Accounts → click your Apple ID → "Manage Certificates"
# Or just open Xcode, the team shows in the project's signing tab.
#
# Usage:  ./scripts/run-on-device.sh
#         ./scripts/run-on-device.sh --simulator   (run in iOS simulator instead)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BACKEND_DIR="$REPO_ROOT/backend"
IOS_DIR="$REPO_ROOT/ios"
CONFIG_FILE="$REPO_ROOT/.cardshow.config"   # local config — gitignored

# ─── pretty logging ───────────────────────────────────────────────────────────
log()   { printf "\033[1;33m▸\033[0m %s\n" "$*"; }
ok()    { printf "\033[1;32m✓\033[0m %s\n" "$*"; }
warn()  { printf "\033[1;31m✗\033[0m %s\n" "$*"; }
hdr()   { printf "\n\033[1;36m── %s ──\033[0m\n" "$*"; }

# ─── 1. detect Mac's LAN IP ───────────────────────────────────────────────────
detect_ip() {
    local ip
    ip="$(ipconfig getifaddr en0 2>/dev/null || true)"
    [[ -z "$ip" ]] && ip="$(ipconfig getifaddr en1 2>/dev/null || true)"
    [[ -z "$ip" ]] && {
        warn "Couldn't detect your Mac's LAN IP. Are you on Wi-Fi?"
        exit 1
    }
    echo "$ip"
}

# ─── 2. load or prompt for Team ID & Bundle ID ────────────────────────────────
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    fi

    if [[ -z "${TEAM_ID:-}" ]]; then
        hdr "First-time setup"
        echo "Open Xcode → Settings → Accounts → click your Apple ID,"
        echo "then look in the projet's Signing & Capabilities tab for your Team ID."
        echo "(Personal/free accounts also work — they have a 10-character team ID.)"
        echo ""
        read -r -p "Enter your Apple Developer Team ID (10 chars): " TEAM_ID
    fi

    if [[ -z "${BUNDLE_ID:-}" ]]; then
        DEFAULT_BUNDLE="com.cardshowpro.$(whoami | tr -cd '[:alnum:]')"
        read -r -p "Bundle ID [$DEFAULT_BUNDLE]: " BUNDLE_ID
        BUNDLE_ID="${BUNDLE_ID:-$DEFAULT_BUNDLE}"
    fi

    cat > "$CONFIG_FILE" <<EOF
TEAM_ID=$TEAM_ID
BUNDLE_ID=$BUNDLE_ID
EOF
    ok "Config saved → $CONFIG_FILE (gitignored)"
}

# ─── 3. ensure backend is running ─────────────────────────────────────────────
start_backend() {
    local ip="$1"

    if curl -s -m 1 "http://localhost:8000/health" >/dev/null 2>&1; then
        ok "Backend already running on :8000"
        return
    fi

    log "Starting backend at http://$ip:8000 …"
    cd "$BACKEND_DIR"
    if [[ ! -d .venv ]]; then
        log "Creating Python venv (one-time)…"
        python3 -m venv .venv
        ./.venv/bin/pip install -q -r requirements.txt
    fi
    if [[ ! -f .env ]]; then
        cp .env.example .env
    fi
    if [[ ! -f pokescan.db ]]; then
        ./.venv/bin/alembic upgrade head >/dev/null 2>&1
        ./.venv/bin/python seed.py >/dev/null 2>&1
    fi
    # Run in background, log to file
    nohup ./.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000 --log-level warning \
        > /tmp/cardshowpro-backend.log 2>&1 &
    local pid=$!
    cd "$REPO_ROOT"

    # Wait for health endpoint
    for _ in {1..20}; do
        if curl -s -m 1 "http://localhost:8000/health" >/dev/null 2>&1; then
            ok "Backend up (pid $pid) — logs: /tmp/cardshowpro-backend.log"
            return
        fi
        sleep 0.5
    done
    warn "Backend didn't start. Check /tmp/cardshowpro-backend.log"
    exit 1
}

# ─── 4. inject backend URL into Info.plist via project.yml ────────────────────
configure_project() {
    local ip="$1"
    local url="http://$ip:8000/api/v1"

    log "Configuring project.yml: TEAM_ID=$TEAM_ID, BUNDLE_ID=$BUNDLE_ID, URL=$url"

    # Write a local override file that xcodegen merges into project.yml
    cat > "$IOS_DIR/project.local.yml" <<EOF
settings:
  base:
    DEVELOPMENT_TEAM: $TEAM_ID
    PRODUCT_BUNDLE_IDENTIFIER: $BUNDLE_ID

targets:
  CardShowPro:
    settings:
      base:
        DEVELOPMENT_TEAM: $TEAM_ID
        PRODUCT_BUNDLE_IDENTIFIER: $BUNDLE_ID
    info:
      properties:
        BackendBaseURL: $url
EOF

    cd "$IOS_DIR"
    # Re-generate the Xcode project merging the local override
    if command -v xcodegen >/dev/null 2>&1; then
        xcodegen generate --spec project.yml --project-roots "$IOS_DIR" >/dev/null 2>&1 || {
            # Fall back: manually merge into a temp file
            cp project.yml project.merged.yml
            cat project.local.yml >> project.merged.yml
            xcodegen generate --spec project.merged.yml >/dev/null
            rm project.merged.yml
        }
    fi
    cd "$REPO_ROOT"
    ok "Xcode project configured"
}

# ─── 5. find the connected device & install ───────────────────────────────────
install_simulator() {
    hdr "Building & launching in simulator"
    cd "$IOS_DIR"
    # boot the default simulator
    local sim_id
    sim_id="$(xcrun simctl list devices booted 2>/dev/null | grep -oE '\([0-9A-F-]{36}\)' | head -1 | tr -d '()' || true)"
    if [[ -z "$sim_id" ]]; then
        # Boot iPhone 17 Pro
        sim_id="$(xcrun simctl list devices available | grep 'iPhone 17 Pro' | head -1 | grep -oE '\([0-9A-F-]{36}\)' | tr -d '()' || true)"
        if [[ -n "$sim_id" ]]; then
            xcrun simctl boot "$sim_id" 2>/dev/null || true
        fi
    fi

    xcodebuild -project CardShowPro.xcodeproj \
        -scheme CardShowPro \
        -destination "platform=iOS Simulator,id=$sim_id" \
        -derivedDataPath /tmp/cardshowpro-build \
        build 2>&1 | grep -E "(error:|warning:|BUILD)" | tail -20

    local app_path="/tmp/cardshowpro-build/Build/Products/Debug-iphonesimulator/CardShowPro.app"
    xcrun simctl install "$sim_id" "$app_path"
    xcrun simctl launch "$sim_id" "$BUNDLE_ID"
    open -a Simulator
    ok "App launched in simulator"
    cd "$REPO_ROOT"
}

install_device() {
    hdr "Building & installing on device"
    cd "$IOS_DIR"

    # Find first connected physical iPhone via devicectl
    local devices_json
    devices_json="$(xcrun devicectl list devices --json-output - 2>/dev/null || echo '{}')"
    local device_id
    device_id="$(echo "$devices_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for d in data.get('result', {}).get('devices', []):
    p = d.get('deviceProperties', {})
    if p.get('platformIdentifier') == 'com.apple.platform.iphoneos' \
       and d.get('connectionProperties', {}).get('tunnelState') in ('connected','disconnected'):
        print(d['identifier'])
        break
")"

    if [[ -z "$device_id" ]]; then
        warn "No iPhone detected via USB-C. Falling back to xcodebuild auto-pick…"
        device_id="generic/platform=iOS"
    fi
    log "Target device: $device_id"

    log "Building (this takes ~30s)…"
    xcodebuild -project CardShowPro.xcodeproj \
        -scheme CardShowPro \
        -destination "platform=iOS,id=$device_id" \
        -derivedDataPath /tmp/cardshowpro-build \
        -allowProvisioningUpdates \
        CODE_SIGN_STYLE=Automatic \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
        build 2>&1 | tee /tmp/cardshowpro-xcb.log | grep -E "(error:|BUILD)" | tail -20

    if grep -q "BUILD SUCCEEDED" /tmp/cardshowpro-xcb.log; then
        ok "Build succeeded"
    else
        warn "Build failed. Full log: /tmp/cardshowpro-xcb.log"
        exit 1
    fi

    local app_path="/tmp/cardshowpro-build/Build/Products/Debug-iphoneos/CardShowPro.app"
    if [[ ! -d "$app_path" ]]; then
        warn "Build output not found at $app_path"
        exit 1
    fi

    log "Installing on device…"
    xcrun devicectl device install app --device "$device_id" "$app_path" 2>&1 | tail -5
    ok "App installed"

    log "Launching…"
    xcrun devicectl device process launch --device "$device_id" "$BUNDLE_ID" 2>&1 | tail -3
    ok "Done — CardShow Pro is now running on your iPhone"
    cd "$REPO_ROOT"
}

# ─── main ─────────────────────────────────────────────────────────────────────
hdr "CardShow Pro — device launcher"

MODE="device"
if [[ "${1:-}" == "--simulator" ]] || [[ "${1:-}" == "-s" ]]; then
    MODE="simulator"
fi

IP="$(detect_ip)"
ok "Mac LAN IP: $IP"

load_config

start_backend "$IP"
configure_project "$IP"

if [[ "$MODE" == "simulator" ]]; then
    install_simulator
else
    install_device
fi

hdr "All set"
echo "Backend logs:  tail -f /tmp/cardshowpro-backend.log"
echo "Stop backend:  kill \$(lsof -ti:8000)"
echo "Edit URL in app: Settings tab → Connection → Edit"
