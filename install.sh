#!/usr/bin/env bash
# Zegel one-line installer (improvement #106).
#
# Usage: curl -sL https://raw.githubusercontent.com/jw-1980/zegel/main/install.sh | bash
#
# Downloads the latest release binary for the current OS/arch from
# GitHub Releases, verifies its SHA-256 checksum, and installs it to
# /usr/local/bin/zegel (override with ZEGEL_INSTALL_DIR).

set -euo pipefail

REPO="jw-1980/zegel"
INSTALL_DIR="${ZEGEL_INSTALL_DIR:-/usr/local/bin}"
BIN_NAME="zegel"

detect_os() {
  case "$(uname -s)" in
    Linux*)  echo "linux" ;;
    Darwin*) echo "macos" ;;
    CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
    *) echo "unsupported" ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x64" ;;
    arm64|aarch64) echo "arm64" ;;
    *) echo "unsupported" ;;
  esac
}

OS="$(detect_os)"
ARCH="$(detect_arch)"

if [[ "$OS" == "unsupported" || "$ARCH" == "unsupported" ]]; then
  echo "Zegel does not ship prebuilt binaries for $(uname -s)/$(uname -m)." >&2
  echo "Please install from source: https://github.com/$REPO" >&2
  exit 1
fi

echo "==> Detected $OS/$ARCH"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TAG="$(curl -sSfL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep -m1 '"tag_name":' \
  | sed -E 's/.*"([^"]+)".*/\1/')"

if [[ -z "$TAG" ]]; then
  echo "Failed to determine latest release tag from GitHub." >&2
  exit 1
fi

echo "==> Installing Zegel $TAG"

ARCHIVE="zegel-${TAG}-${OS}-${ARCH}.tar.gz"
URL="https://github.com/$REPO/releases/download/$TAG/$ARCHIVE"
CHECKSUM_URL="https://github.com/$REPO/releases/download/$TAG/SHA256SUMS"

curl -sSfL -o "$TMP_DIR/$ARCHIVE" "$URL"
curl -sSfL -o "$TMP_DIR/SHA256SUMS" "$CHECKSUM_URL"

echo "==> Verifying checksum"
(cd "$TMP_DIR" && sha256sum --check --ignore-missing SHA256SUMS)

echo "==> Extracting"
tar -xzf "$TMP_DIR/$ARCHIVE" -C "$TMP_DIR"

if [[ ! -w "$INSTALL_DIR" ]]; then
  SUDO="sudo"
else
  SUDO=""
fi

$SUDO install -m 0755 "$TMP_DIR/$BIN_NAME" "$INSTALL_DIR/$BIN_NAME"

echo "==> Installed $INSTALL_DIR/$BIN_NAME"
"$INSTALL_DIR/$BIN_NAME" --version || true
