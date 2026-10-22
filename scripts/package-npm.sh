#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM="$(uname -s)"
ARCH="$(uname -m)"

case "${PLATFORM}-${ARCH}" in
  Darwin-arm64)
    PACKAGE_DIR="${ROOT_DIR}/npm/@utoo/lint-darwin-arm64"
    BINARY_NAME="utoo-lint"
    ;;
  Darwin-x86_64)
    PACKAGE_DIR="${ROOT_DIR}/npm/@utoo/lint-darwin-x64"
    BINARY_NAME="utoo-lint"
    ;;
  Linux-aarch64|Linux-arm64)
    PACKAGE_DIR="${ROOT_DIR}/npm/@utoo/lint-linux-arm64"
    BINARY_NAME="utoo-lint"
    ;;
  Linux-x86_64)
    PACKAGE_DIR="${ROOT_DIR}/npm/@utoo/lint-linux-x64"
    BINARY_NAME="utoo-lint"
    ;;
  MINGW*-x86_64|MSYS*-x86_64|CYGWIN*-x86_64)
    PACKAGE_DIR="${ROOT_DIR}/npm/@utoo/lint-win32-x64"
    BINARY_NAME="utoo-lint.exe"
    ;;
  *)
    echo "unsupported packaging target: ${PLATFORM}-${ARCH}" >&2
    exit 1
    ;;
esac

cd "${ROOT_DIR}"
zig build -Doptimize=fast -j1

mkdir -p "${PACKAGE_DIR}/bin"
cp "${ROOT_DIR}/zig-out/bin/${BINARY_NAME}" "${PACKAGE_DIR}/bin/${BINARY_NAME}"
chmod 755 "${PACKAGE_DIR}/bin/${BINARY_NAME}"

echo "staged ${PACKAGE_DIR}/bin/${BINARY_NAME}"
