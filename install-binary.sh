#!/usr/bin/env sh

PROJECT_NAME="distribution-tooling-for-helm"
BINARY_NAME="dt"
PROJECT_GH="samsung-cnct/$PROJECT_NAME"
PLUGIN_MANIFEST="plugin.yaml"

# Convert HELM_BIN and HELM_PLUGIN_DIR to unix if cygpath is
# available. This is the case when using MSYS2 or Cygwin
# on Windows where helm returns a Windows path but we
# need a Unix path

if command -v cygpath >/dev/null 2>&1; then
  HELM_BIN="$(cygpath -u "${HELM_BIN}")"
  HELM_PLUGIN_DIR="$(cygpath -u "${HELM_PLUGIN_DIR}")"
fi

[ -z "$HELM_BIN" ] && HELM_BIN=$(command -v helm)

[ -z "$HELM_HOME" ] && HELM_HOME=$(helm env | grep 'HELM_DATA_HOME' | cut -d '=' -f2 | tr -d '"')

mkdir -p "$HELM_HOME"

if [ "$SKIP_BIN_INSTALL" = "1" ]; then
  echo "Skipping binary install"
  exit
fi

# which mode is the common installer script running in
SCRIPT_MODE="install"
if [ "$1" = "-u" ]; then
  SCRIPT_MODE="update"
fi

# initArch discovers the architecture for this system.
initArch() {
  ARCH=$(uname -m)
  case $ARCH in
  armv5*) ARCH="armv5" ;;
  armv6*) ARCH="armv6" ;;
  armv7*) ARCH="armv7" ;;
  aarch64) ARCH="arm64" ;;
  x86) ARCH="386" ;;
  x86_64) ARCH="amd64" ;;
  i686) ARCH="386" ;;
  i386) ARCH="386" ;;
  esac
}

# initOS discovers the operating system for this system.
initOS() {
  OS=$(uname -s)

  case "$OS" in
  Windows_NT) OS='windows' ;;
  # Msys support
  MSYS*) OS='windows' ;;
  # Minimalist GNU for Windows
  MINGW*) OS='windows' ;;
  CYGWIN*) OS='windows' ;;
  Darwin) OS='darwin' ;;
  Linux) OS='linux' ;;
  esac
}

# verifySupported checks that the os/arch combination is supported for
# binary builds.
verifySupported() {
  supported="linux-amd64\nlinux-arm64\nfreebsd-amd64\ndarwin-amd64\ndarwin-arm64\nwindows-amd64"
  if ! echo "${supported}" | grep -q "${OS}-${ARCH}"; then
    echo "No prebuild binary for ${OS}-${ARCH}."
    exit 1
  fi

  if
    ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1
  then
    echo "Either curl or wget is required"
    exit 1
  fi
}

# getDownloadURL checks the latest available version.
getDownloadURL() {
  version="$(< "$HELM_PLUGIN_DIR/$PLUGIN_MANIFEST" grep "version" | cut -d '"' -f 2)"
  ext="tar.gz"
  if [ "$OS" = "windows" ]; then
    ext="zip"
  fi
  if [ "$SCRIPT_MODE" = "install" ] && [ -n "$version" ]; then
    DOWNLOAD_URL="https://github.com/${PROJECT_GH}/releases/download/v${version}/${PROJECT_NAME}_${version}_${OS}_${ARCH}.${ext}"
  else
    DOWNLOAD_URL="https://github.com/${PROJECT_GH}/releases/latest/download/${PROJECT_NAME}_${version}_${OS}_${ARCH}.${ext}"
  fi
}

# Temporary dir
mkTempDir() {
  HELM_TMP="$(mktemp -d -t "${PROJECT_NAME}-XXXXXX")"
}
rmTempDir() {
  if [ -d "${HELM_TMP:-/tmp/distribution-tooling-for-helm-tmp}" ]; then
    rm -rf "${HELM_TMP:-/tmp/distribution-tooling-for-helm-tmp}"
  fi
}

# downloadFile downloads the latest binary package and also the checksum
# for that binary.
downloadFile() {
  PLUGIN_TMP_FILE="${HELM_TMP}/${PROJECT_NAME}.tgz"
  echo "Downloading $DOWNLOAD_URL"
  if
    command -v curl >/dev/null 2>&1
  then
    curl -sSf -L "$DOWNLOAD_URL" >"$PLUGIN_TMP_FILE"
  elif
    command -v wget >/dev/null 2>&1
  then
    wget -q -O - "$DOWNLOAD_URL" >"$PLUGIN_TMP_FILE"
  fi
}

# installFile verifies the SHA256 for the file, then unpacks and
# installs it.
installFile() {
  HELM_TMP_BIN="$HELM_TMP/$BINARY_NAME"
  if [ "${OS}" = "windows" ]; then
    HELM_TMP_BIN="$HELM_TMP_BIN.exe"
    unzip "$PLUGIN_TMP_FILE" -d "$HELM_TMP"
  else
    tar xzf "$PLUGIN_TMP_FILE" -C "$HELM_TMP"
  fi
  echo "Preparing to install into ${HELM_PLUGIN_DIR}"
  mkdir -p "$HELM_PLUGIN_DIR/bin"
  cp "$HELM_TMP_BIN" "$HELM_PLUGIN_DIR/bin"
}

# exit_trap is executed if on exit (error or not).
exit_trap() {
  result=$?
  rmTempDir
  if [ "$result" != "0" ]; then
    echo "Failed to install $PROJECT_NAME"
    printf "\tFor support, go to https://github.com/%s.\n" "$PROJECT_GH"
  fi
  exit $result
}

# testVersion tests the installed client to make sure it is working.
testVersion() {
  set +e
  echo "$PROJECT_NAME installed into $HELM_PLUGIN_DIR"
  "${HELM_PLUGIN_DIR}/bin/$BINARY_NAME" -h
  set -e
}

# Execution

#Stop execution on any error
trap "exit_trap" EXIT
set -e
initArch
initOS
verifySupported
getDownloadURL
mkTempDir
downloadFile
installFile
testVersion
