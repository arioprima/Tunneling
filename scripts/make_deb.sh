#!/usr/bin/env bash
set -euo pipefail

# === Konfigurasi utama (boleh kamu ubah jika perlu) ===
# Nama executable di folder bundle (cek di build/linux/x64/release/bundle/)
APP_NAME="bitvise"

# Auto ambil versi dari pubspec.yaml (format: 1.0.0+1 => pakai 1.0.0)
if [[ -f "pubspec.yaml" ]]; then
  VERSION="$(grep -E '^version:' pubspec.yaml | head -n1 | awk '{print $2}' | cut -d'+' -f1)"
else
  VERSION="1.0.0"
fi

MAINTAINER="Your Name <you@example.com>"
HOMEPAGE="https://example.com"
SECTION="utils"
PRIORITY="optional"

# Path bundle dari Flutter (x64). Kalau ARM ganti x64 -> arm64
BUNDLE_DIR="build/linux/x64/release/bundle"

# Deteksi arsitektur Debian: amd64/arm64/dll.
DEB_ARCH="$(dpkg --print-architecture)"

# === Validasi awal ===
if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "❌ Bundle tidak ditemukan: $BUNDLE_DIR"
  echo "Jalankan dulu: flutter build linux --release"
  exit 1
fi

if [[ ! -x "$BUNDLE_DIR/$APP_NAME" ]]; then
  echo "❌ Executable '$APP_NAME' tidak ditemukan di $BUNDLE_DIR"
  echo "Isi folder bundle:"
  ls -lah "$BUNDLE_DIR"
  echo
  echo "Jika nama executable beda, set APP_NAME di script ini sesuai nama file di bundle."
  exit 1
fi

# === Layout paket .deb ===
OUT_DIR="dist"
PKG_DIR="$OUT_DIR/${APP_NAME}_${VERSION}_${DEB_ARCH}"
ROOT="$PKG_DIR/pkg"

rm -rf "$PKG_DIR"
mkdir -p "$ROOT/DEBIAN"
mkdir -p "$ROOT/opt/$APP_NAME"
mkdir -p "$ROOT/usr/bin"
mkdir -p "$ROOT/usr/share/applications"
mkdir -p "$ROOT/usr/share/icons/hicolor/256x256/apps"

# Salin seluruh isi bundle ke /opt/<APP_NAME>
cp -a "$BUNDLE_DIR/." "$ROOT/opt/$APP_NAME/"

# Buat wrapper di /usr/bin/<APP_NAME>
cat > "$ROOT/usr/bin/$APP_NAME" <<EOF
#!/usr/bin/env sh
exec /opt/$APP_NAME/$APP_NAME "\$@"
EOF
chmod 0755 "$ROOT/usr/bin/$APP_NAME"

# Cari ikon (opsional), pakai yang ada:
ICON_SRC=""
if [[ -f "$BUNDLE_DIR/data/flutter_assets/assets/icon.png" ]]; then
  ICON_SRC="$BUNDLE_DIR/data/flutter_assets/assets/icon.png"
elif [[ -f "assets/icon.png" ]]; then
  ICON_SRC="assets/icon.png"
fi

# File .desktop (launcher menu)
DESKTOP_FILE="$ROOT/usr/share/applications/${APP_NAME}.desktop"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=${APP_NAME}
Exec=/usr/bin/${APP_NAME}
Icon=${APP_NAME}
Type=Application
Terminal=false
Categories=Utility;Development;
EOF

# Pasang icon kalau ada
if [[ -n "$ICON_SRC" ]]; then
  cp "$ICON_SRC" "$ROOT/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png"
fi

# File control Debian
CONTROL_FILE="$ROOT/DEBIAN/control"
cat > "$CONTROL_FILE" <<EOF
Package: ${APP_NAME}
Version: ${VERSION}
Section: ${SECTION}
Priority: ${PRIORITY}
Architecture: ${DEB_ARCH}
Maintainer: ${MAINTAINER}
Homepage: ${HOMEPAGE}
Depends: libc6, libstdc++6, libgtk-3-0, liblzma5, libx11-6, libxcb1, libxkbcommon0, libxi6, libxtst6
Description: ${APP_NAME} (Flutter) with multi-window + SFTP
 A Flutter-based SSH/SFTP client.
EOF

# Izin file
find "$ROOT/opt/$APP_NAME" -type d -print0 | xargs -0 chmod 0755
# default file: 0644, tapi executable utama harus 0755
find "$ROOT/opt/$APP_NAME" -type f -print0 | xargs -0 chmod 0644
chmod 0755 "$ROOT/opt/$APP_NAME/$APP_NAME" || true
chmod 0755 "$ROOT/usr/bin/$APP_NAME"

# Build .deb
mkdir -p "$OUT_DIR"
DEB_FILE="${OUT_DIR}/${APP_NAME}_${VERSION}_${DEB_ARCH}.deb"
dpkg-deb --build --root-owner-group "$ROOT" "$DEB_FILE"

echo "✅ Selesai: $DEB_FILE"
echo "Install: sudo apt install ./$DEB_FILE"
