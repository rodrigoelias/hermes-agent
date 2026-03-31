#!/usr/bin/env bash
#
# Build hermes-agent native wheels for Android/Termux aarch64.
#
# Compiles all native Python extensions (Rust + C) inside a real Termux
# Docker environment so the resulting .whl files work on a physical phone.
#
# Requirements:
#   - Docker (with linux/arm64 support — native on Apple Silicon)
#   - Internet access (PyPI + Termux repos + crates.io)
#
# Usage:
#   ./android/build.sh              # Build wheels only
#   ./android/build.sh --full       # Build wheels + deployment tarball
#
# Output:
#   android/wheels/*.whl            # Pre-built native wheels
#   android/hermes-termux.tar.gz    # Full deployment package (with --full)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WHEELS_DIR="$SCRIPT_DIR/wheels"
FULL_BUILD=false

[[ "${1:-}" == "--full" ]] && FULL_BUILD=true

cd "$PROJECT_DIR"

# ── Resolve DNS for Termux Docker (Android's Bionic resolver doesn't work in containers)
_resolve_hosts() {
    local hosts_file
    hosts_file=$(mktemp)
    echo "127.0.0.1 localhost" > "$hosts_file"
    echo "::1 ip6-localhost" >> "$hosts_file"

    local domains=(
        packages-cf.termux.dev pypi.org files.pythonhosted.org
        crates.io static.crates.io index.crates.io
    )
    for domain in "${domains[@]}"; do
        local ip
        ip=$(dig +short "$domain" A 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
        [[ -n "$ip" ]] && echo "$ip $domain" >> "$hosts_file"
    done
    echo "$hosts_file"
}

HOSTS_FILE=$(_resolve_hosts)
trap 'rm -f "$HOSTS_FILE"' EXIT

# ── Native packages to cross-compile ──
# Pinned to versions required by hermes-agent's dependency tree.
# Update these when bumping deps in pyproject.toml.
NATIVE_PKGS=(
    "pydantic-core==2.41.5"   # pinned by pydantic 2.12.5
    "cryptography==46.0.6"
    "cffi==2.0.0"
    "jiter==0.13.0"
    "aiohttp==3.13.4"
    "PyYAML==6.0.3"
    "MarkupSafe==3.0.3"
    "msgpack==1.1.2"
)

echo "━━━ Building native Termux aarch64 wheels ━━━"
echo ""
echo "Packages: ${NATIVE_PKGS[*]}"
echo ""

mkdir -p "$WHEELS_DIR"
rm -f "$WHEELS_DIR"/*.whl

docker run --rm --platform linux/arm64 \
    -v "$HOSTS_FILE:/system/etc/hosts:ro" \
    -v "$WHEELS_DIR:/output" \
    termux/termux-docker:aarch64 bash -c "
set -e
export DEBIAN_FRONTEND=noninteractive

# Configure Termux repos
echo 'deb https://packages-cf.termux.dev/apt/termux-main/ stable main' \
    > /data/data/com.termux/files/usr/etc/apt/sources.list
apt update -qq 2>/dev/null
apt upgrade -y -o Dpkg::Options::='--force-confnew' 2>&1 | tail -1

# Install build toolchain
pkg install -y python rust binutils build-essential libffi openssl pkg-config 2>&1 | tail -1

# maturin needs this to detect Android API level
export ANDROID_API_LEVEL=24
export OPENSSL_DIR=/data/data/com.termux/files/usr

mkdir -p /tmp/wheels

PKGS='${NATIVE_PKGS[*]}'
for pkg in \$PKGS; do
    echo \"⏳ \$pkg\"
    pip3 wheel --no-cache-dir --wheel-dir /tmp/wheels \"\$pkg\" 2>&1 | tail -1
done

# Keep only native (.so) wheels + their pure-python build deps
cp /tmp/wheels/*.whl /output/

echo ''
echo '━━━ Built wheels ━━━'
ls -lh /tmp/wheels/*.whl | awk '{print \$5, \$9}' | sed 's|/tmp/wheels/||'
"

WHEEL_COUNT=$(ls "$WHEELS_DIR"/*.whl 2>/dev/null | wc -l | tr -d ' ')
TOTAL_SIZE=$(du -sh "$WHEELS_DIR" | cut -f1)
echo ""
echo "✅ $WHEEL_COUNT wheels in android/wheels/ ($TOTAL_SIZE)"

# ── Optional: build full deployment tarball ──
if $FULL_BUILD; then
    echo ""
    echo "━━━ Building deployment tarball ━━━"

    TARBALL="$SCRIPT_DIR/hermes-termux.tar.gz"

    # Create tarball: source + wheels + install script
    tar -czf "$TARBALL" \
        --exclude='.git' \
        --exclude='android/hermes-termux.tar.gz' \
        --exclude='./tests' \
        --exclude='./environments' \
        --exclude='__pycache__' \
        --exclude='*.pyc' \
        --exclude='*.egg-info' \
        --exclude='venv' \
        --exclude='.venv' \
        -C "$PROJECT_DIR" .

    SIZE=$(du -sh "$TARBALL" | cut -f1)
    echo "✅ $TARBALL ($SIZE)"
    echo ""
    echo "Deploy:  ./android/deploy.sh <host> [port] [password]"
fi
