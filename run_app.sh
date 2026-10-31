#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
export PATH="$HOME/.flutter/bin:$PATH"

# Rebuild if binary doesn't exist
BUNDLE_BIN="./apps/mobile_desktop/build/linux/x64/debug/bundle/void_notes"
if [ ! -f "$BUNDLE_BIN" ]; then
    echo "Compilando aplicativo Flutter para Linux..."
    (cd apps/mobile_desktop && flutter build linux --debug)
fi

echo "============================================================"
echo "  Iniciando void-notes Desktop Application (GTK)"
echo "============================================================"
exec "$BUNDLE_BIN" "$@"
