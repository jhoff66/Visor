#!/bin/zsh
# Compila o Visor, embute o scrcpy oficial e monta o "Visor.app" nesta pasta.
set -euo pipefail
cd "$(dirname "$0")"

SCRCPY_VERSION="5.0.1"
BASE_URL="https://github.com/Genymobile/scrcpy/releases/download/v${SCRCPY_VERSION}"
LICENSE_URL="https://raw.githubusercontent.com/Genymobile/scrcpy/v${SCRCPY_VERSION}/LICENSE"
APP="Visor.app"

mkdir -p build

# `./build.sh icon` redesenha o Resources/AppIcon.icns a partir do Tools/make-icon.swift.
if [[ "${1:-}" == "icon" ]]; then
  swiftc -O Tools/make-icon.swift -o build/make-icon
  build/make-icon build/icon.png
  SET="build/AppIcon.iconset"
  rm -rf "$SET" && mkdir -p "$SET"
  for px in 16 32 128 256 512; do
    sips -z $px $px build/icon.png --out "$SET/icon_${px}x${px}.png" >/dev/null
    sips -z $((px * 2)) $((px * 2)) build/icon.png --out "$SET/icon_${px}x${px}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o Resources/AppIcon.icns
  echo "Ícone: $PWD/Resources/AppIcon.icns"
  exit 0
fi

# 1) scrcpy oficial (com cache em build/vendor). Nome do tarball usa aarch64 para arm64.
typeset -A TARBALL_ARCH=(arm64 aarch64 x86_64 x86_64)
for arch in arm64 x86_64; do
  dir="build/vendor/$arch/scrcpy-macos-${TARBALL_ARCH[$arch]}-v${SCRCPY_VERSION}"
  if [[ ! -x "$dir/scrcpy" || ! -x "$dir/adb" || ! -f "$dir/scrcpy-server" ]]; then
    echo "Baixando scrcpy $SCRCPY_VERSION ($arch)…"
    rm -rf "build/vendor/$arch" && mkdir -p "build/vendor/$arch"
    curl -fL --progress-bar -o "build/vendor/scrcpy-$arch.tar.gz" "$BASE_URL/scrcpy-macos-${TARBALL_ARCH[$arch]}-v${SCRCPY_VERSION}.tar.gz"
    tar -xzf "build/vendor/scrcpy-$arch.tar.gz" -C "build/vendor/$arch"
  fi
done
if [[ ! -s build/vendor/LICENSE ]]; then
  curl -fsL -o build/vendor/LICENSE "$LICENSE_URL" || cp "build/vendor/arm64/scrcpy-macos-aarch64-v${SCRCPY_VERSION}/LICENSE" build/vendor/LICENSE
fi

# 2) Binário universal: roda em Apple Silicon e em Intel.
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -target $arch-apple-macos14.0 \
    Sources/Visor/*.swift Sources/Visor/Views/*.swift -o build/Visor-$arch
done
lipo -create build/Visor-arm64 build/Visor-x86_64 -output build/Visor

# 3) Monta o .app.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/Visor "$APP/Contents/MacOS/Visor"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp build/vendor/LICENSE "$APP/Contents/Resources/scrcpy-LICENSE.txt"

for arch in arm64 x86_64; do
  src="build/vendor/$arch/scrcpy-macos-${TARBALL_ARCH[$arch]}-v${SCRCPY_VERSION}"
  dst="$APP/Contents/Resources/scrcpy-$arch"
  mkdir -p "$dst"
  cp "$src/scrcpy" "$src/scrcpy-server" "$src/scrcpy.png" "$src/disconnected.png" "$dst/"
  # O adb vem universal; guarda só a fatia da arquitetura.
  if lipo -info "$src/adb" 2>/dev/null | grep -q "Architectures in the fat file"; then
    lipo -thin $arch "$src/adb" -output "$dst/adb"
  else
    cp "$src/adb" "$dst/adb"
  fi
  chmod +x "$dst/scrcpy" "$dst/adb"
  xattr -cr "$dst"
  codesign --force --sign - "$dst/scrcpy"
  codesign --force --sign - "$dst/adb"
done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Visor</string>
  <key>CFBundleDisplayName</key><string>Visor</string>
  <key>CFBundleIdentifier</key><string>br.com.jhosefer.visor</string>
  <key>CFBundleExecutable</key><string>Visor</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>pt-BR</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSLocalNetworkUsageDescription</key><string>O Visor se conecta aos celulares Android da sua rede Wi-Fi.</string>
</dict>
</plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP" && echo "Assinatura ok"
echo "Pronto: $PWD/$APP"

# `./build.sh install` também atualiza a cópia em /Applications e reabre o app.
if [[ "${1:-}" == "install" ]]; then
  pkill -x Visor && sleep 1 || true
  rm -rf "/Applications/$APP"
  cp -R "$APP" "/Applications/$APP"
  open "/Applications/$APP"
  echo "Instalado em /Applications/$APP"
fi
