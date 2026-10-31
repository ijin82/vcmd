#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

APP_NAME="vcmd"
APP_TITLE="vCommander"
DIST_DIR="${SCRIPT_DIR}/dist"

# Obtain version either from argument, environment, or interactive prompt
VERSION="${1:-${VERSION}}"
if [ -z "${VERSION}" ]; then
    read -r -p "Enter release version (e.g. 0.1.0 or v0.1.0): " VERSION
fi

# Trim whitespace
VERSION="$(echo "${VERSION}" | xargs)"

if [ -z "${VERSION}" ]; then
    echo "Error: Release version cannot be empty." >&2
    exit 1
fi

ARCH="$(uname -m)"
RELEASE_TAG="${APP_NAME}-${VERSION}-linux-${ARCH}"
STAGE_DIR="${DIST_DIR}/${RELEASE_TAG}"
ARCHIVE_NAME="${RELEASE_TAG}.tar.gz"
ARCHIVE_PATH="${DIST_DIR}/${ARCHIVE_NAME}"

echo "=================================================="
echo " Preparing release package: ${RELEASE_TAG}"
echo "=================================================="

# 1. Clean and build binary
echo "==> Compiling fresh binary..."
make clean
make build

if [ ! -f "${APP_NAME}" ]; then
    echo "Error: Compilation failed, '${APP_NAME}' binary not found." >&2
    exit 1
fi

# 2. Setup staging area
echo "==> Preparing staging directory..."
rm -rf "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}/data"

# 3. Copy files to package
echo "==> Copying release files..."
cp -p "${APP_NAME}" "${STAGE_DIR}/${APP_NAME}"

# Strip binary to reduce distribution size
if command -v strip >/dev/null 2>&1; then
    echo "==> Stripping debug symbols from release binary..."
    strip --strip-unneeded "${STAGE_DIR}/${APP_NAME}" 2>/dev/null || true
fi

cp -p "install.sh" "${STAGE_DIR}/install.sh"
chmod 755 "${STAGE_DIR}/install.sh"

if [ -f "data/style.css" ]; then
    cp -p "data/style.css" "${STAGE_DIR}/data/style.css"
fi

if [ -f "${APP_NAME}.svg" ]; then
    cp -p "${APP_NAME}.svg" "${STAGE_DIR}/${APP_NAME}.svg"
fi

if [ -f "README.md" ]; then
    cp -p "README.md" "${STAGE_DIR}/README.md"
fi

if [ -f "LICENSE" ]; then
    cp -p "LICENSE" "${STAGE_DIR}/LICENSE"
fi

# 4. Create tar.gz archive
echo "==> Creating tarball ${ARCHIVE_NAME}..."
mkdir -p "${DIST_DIR}"
tar -czf "${ARCHIVE_PATH}" -C "${DIST_DIR}" "${RELEASE_TAG}"

# 5. Generate SHA256 checksum
if command -v sha256sum >/dev/null 2>&1; then
    (cd "${DIST_DIR}" && sha256sum "${ARCHIVE_NAME}" > "${ARCHIVE_NAME}.sha256")
fi

# 6. Clean up temporary staging directory
rm -rf "${STAGE_DIR}"

echo ""
echo "=================================================="
echo "✓ Release build completed successfully!"
echo "=================================================="
echo "  Archive:  ${ARCHIVE_PATH}"
echo "  Size:     $(du -h "${ARCHIVE_PATH}" | cut -f1)"
if [ -f "${ARCHIVE_PATH}.sha256" ]; then
    echo "  SHA256:   $(cat "${ARCHIVE_PATH}.sha256")"
fi
echo ""
echo "Archive contents:"
tar -ztvf "${ARCHIVE_PATH}"
echo ""
echo "To test installation from archive:"
echo "  tar -xzf ${ARCHIVE_PATH}"
echo "  cd ${RELEASE_TAG}"
echo "  ./install.sh install   # Installs binary, desktop file, icon, styles"
echo "  ./install.sh uninstall # Removes all installed files"
echo "=================================================="
