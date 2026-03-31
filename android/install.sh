#!/usr/bin/env bash
#
# Install hermes-agent on Termux using pre-built native wheels.
#
# Run this ON the phone (inside Termux), or via deploy.sh from your Mac.
#
# Usage:
#   ./install.sh                    # Full install
#   ./install.sh --deps-only        # Only install dependencies
#   ./install.sh --upgrade          # Upgrade existing install
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HERMES_DIR="$(dirname "$SCRIPT_DIR")"
WHEELS_DIR="$SCRIPT_DIR/wheels"

DEPS_ONLY=false
UPGRADE=""
for arg in "$@"; do
    case "$arg" in
        --deps-only) DEPS_ONLY=true ;;
        --upgrade)   UPGRADE="--upgrade" ;;
    esac
done

echo "━━━ Hermes Agent — Termux Installer ━━━"
echo ""

# ── Check environment ──
if [[ ! -d "$WHEELS_DIR" ]] || [[ -z "$(ls "$WHEELS_DIR"/*.whl 2>/dev/null)" ]]; then
    echo "❌ No wheels found in $WHEELS_DIR"
    echo "   Run ./android/build.sh on your Mac first."
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    echo "Installing Python..."
    pkg install -y python 2>&1 | tail -3
fi

if ! command -v rg &>/dev/null; then
    echo "Installing ripgrep..."
    pkg install -y ripgrep 2>&1 | tail -1
fi

# ── Step 1: Native wheels ──
echo "━━━ Installing native wheels ━━━"
pip3 install --no-cache-dir $UPGRADE "$WHEELS_DIR"/*.whl 2>&1 | tail -5
echo ""

# ── Step 2: setuptools (needed for editable install) ──
pip3 install --no-cache-dir --no-deps setuptools 2>&1 | tail -1

# ── Step 3: Pure-python dependencies ──
echo "━━━ Installing pure-python dependencies ━━━"

# All pure-python deps pinned to versions compatible with hermes-agent 0.6.0
PURE_DEPS=(
    "python-dotenv==1.2.2"
    "fire==0.7.1"
    "httpx==0.28.1"
    "rich==14.3.3"
    "tenacity==9.1.4"
    "requests==2.33.1"
    "charset-normalizer==3.4.6"
    "jinja2==3.1.6"
    "prompt_toolkit==3.0.52"
    "openai==2.30.0"
    "anthropic==0.86.0"
    "pydantic==2.12.5"
    "sniffio==1.3.1"
    "anyio==4.13.0"
    "certifi==2026.2.25"
    "httpcore==1.0.9"
    "h11==0.16.0"
    "distro==1.9.0"
    "annotated-types==0.7.0"
    "typing-inspection==0.4.2"
    "mdurl==0.1.2"
    "markdown-it-py==4.0.0"
    "Pygments==2.20.0"
    "tqdm==4.67.3"
    "tabulate==0.10.0"
    "termcolor==3.3.0"
    "docstring-parser==0.17.0"
    "nest-asyncio==1.6.0"
    "httpx-sse==0.4.3"
    "exa-py==2.10.2"
    "firecrawl-py==4.21.0"
    "parallel-web==0.4.2"
    "fal-client==0.13.2"
    "edge-tts==7.2.8"
    "PyJWT==2.12.1"
    "wcwidth==0.6.0"
    "websockets==16.0"
    "urllib3==2.6.3"
)

# --no-deps prevents pip from re-resolving (and trying to rebuild) native deps
pip3 install --no-cache-dir --no-deps $UPGRADE "${PURE_DEPS[@]}" 2>&1 | tail -3
echo ""

if $DEPS_ONLY; then
    echo "✅ Dependencies installed. Skipping hermes-agent install."
    exit 0
fi

# ── Step 4: hermes-agent itself ──
echo "━━━ Installing hermes-agent ━━━"
cd "$HERMES_DIR"
pip3 install --no-cache-dir --no-deps $UPGRADE -e "." 2>&1 | tail -3
echo ""

# ── Verify ──
echo "━━━ Verification ━━━"
python3 -c "
import pydantic_core, cryptography, jiter, yaml, aiohttp
import openai, anthropic, pydantic, rich, dotenv
from hermes_cli.main import main
print('  All imports OK')
print(f'  pydantic {pydantic.__version__} / core {pydantic_core.__version__}')
print(f'  openai {openai.__version__} / anthropic {anthropic.__version__}')
"

echo ""
echo "✅ hermes-agent installed successfully!"
echo ""
echo "Run:  hermes setup    # First-time configuration"
echo "      hermes          # Start interactive chat"
