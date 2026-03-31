#!/usr/bin/env bash
#
# Deploy hermes-agent to a Termux phone over SSH.
#
# Prerequisites:
#   - ./android/build.sh has been run (wheels exist)
#   - Termux on phone has openssh installed (pkg install openssh)
#   - sshd running on phone (sshd)
#
# Usage:
#   ./android/deploy.sh <host> [port] [password]
#
# Examples:
#   ./android/deploy.sh 192.168.1.42              # default port 8022, key auth
#   ./android/deploy.sh 192.168.1.42 8022 mypass  # with password
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

HOST="${1:?Usage: deploy.sh <host> [port] [password]}"
PORT="${2:-8022}"
PASSWORD="${3:-}"

REMOTE_DIR="/data/data/com.termux/files/home/hermes-agent"

# SSH/SCP command builders
if [[ -n "$PASSWORD" ]]; then
    SSH="sshpass -p $PASSWORD ssh -o StrictHostKeyChecking=no -p $PORT $HOST"
    SCP="sshpass -p $PASSWORD scp -o StrictHostKeyChecking=no -P $PORT"
else
    SSH="ssh -o StrictHostKeyChecking=no -p $PORT $HOST"
    SCP="scp -o StrictHostKeyChecking=no -P $PORT"
fi

echo "━━━ Deploying hermes-agent to $HOST:$PORT ━━━"
echo ""

# ── Check connectivity ──
echo "Testing SSH connection..."
$SSH "echo 'Connected to \$(uname -m) / \$(cat /data/data/com.termux/files/usr/etc/termux-app/termux.properties 2>/dev/null | head -1 || echo Termux)'" || {
    echo "❌ SSH connection failed. Make sure:"
    echo "   1. Termux has openssh: pkg install openssh"
    echo "   2. sshd is running:    sshd"
    echo "   3. You know the password: passwd"
    exit 1
}

# ── Create deployment tarball (excluding heavy stuff) ──
echo "Creating deployment package..."
TARBALL=$(mktemp /tmp/hermes-deploy-XXXXX.tar.gz)
trap 'rm -f "$TARBALL"' EXIT

tar -czf "$TARBALL" \
    --exclude='.git' \
    --exclude='./tests' \
    --exclude='./environments' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='*.egg-info' \
    --exclude='venv' \
    --exclude='.venv' \
    --exclude='android/hermes-termux.tar.gz' \
    -C "$PROJECT_DIR" .

SIZE=$(du -sh "$TARBALL" | cut -f1)
echo "Package size: $SIZE"

# ── Upload ──
echo "Uploading to $HOST..."
$SSH "mkdir -p $REMOTE_DIR"
$SCP "$TARBALL" "$HOST:$REMOTE_DIR/deploy.tar.gz"

# ── Extract + install on phone ──
echo "Installing on phone..."
$SSH bash -s << 'REMOTE_SCRIPT'
set -e
cd ~/hermes-agent
tar -xzf deploy.tar.gz
rm deploy.tar.gz

# Run the install script
chmod +x android/install.sh
bash android/install.sh
REMOTE_SCRIPT

echo ""
echo "✅ Deployment complete!"
echo ""
echo "SSH into your phone and run:"
echo "  ssh -p $PORT $HOST"
echo "  hermes setup    # First-time config"
echo "  hermes          # Start chatting"
