#!/bin/bash
# Instala ou atualiza o Visor em /Applications.
# Uso: curl -fsSL https://raw.githubusercontent.com/jhoff66/Visor/main/install.sh | bash
set -euo pipefail

URL="https://github.com/jhoff66/Visor/releases/latest/download/Visor.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Baixando o Visor…"
curl -fL --progress-bar -o "$TMP/Visor.zip" "$URL"
ditto -x -k "$TMP/Visor.zip" "$TMP"

pkill -x Visor 2>/dev/null && sleep 1 || true
rm -rf /Applications/Visor.app
ditto "$TMP/Visor.app" /Applications/Visor.app
xattr -cr /Applications/Visor.app

open /Applications/Visor.app
echo "Pronto: Visor instalado em /Applications e aberto."
