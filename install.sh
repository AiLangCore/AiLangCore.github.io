#!/usr/bin/env sh
set -eu

REPO="${AILANG_REPO:-AiLangCore/AiLang}"
INSTALL_ROOT="${AILANG_INSTALL_ROOT:-$HOME/.ailang}"
CHANNEL="${AILANG_CHANNEL:-stable}"
VERSION="${AILANG_VERSION:-}"

usage() {
  cat <<'EOF'
Usage: install.sh [--version <version>] [--channel stable|alpha|beta|rc] [--root <path>]

Environment:
  AILANG_REPO          GitHub repo to download from. Default: AiLangCore/AiLang
  AILANG_VERSION      Exact version or tag to install.
  AILANG_CHANNEL      stable, alpha, beta, or rc. Default: stable.
  AILANG_INSTALL_ROOT Install root. Default: ~/.ailang
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --channel)
      CHANNEL="${2:-}"
      shift 2
      ;;
    --root)
      INSTALL_ROOT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

fetch() {
  url="$1"
  out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$out"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$out" "$url"
  else
    echo "curl or wget is required" >&2
    exit 1
  fi
}

fetch_stdout() {
  url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$url"
  else
    echo "curl or wget is required" >&2
    exit 1
  fi
}

detect_rid() {
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os" in
    Darwin) platform="osx" ;;
    Linux) platform="linux" ;;
    *) echo "unsupported OS: $os" >&2; exit 1 ;;
  esac
  case "$arch" in
    arm64|aarch64) cpu="arm64" ;;
    x86_64|amd64) cpu="x64" ;;
    *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
  esac
  printf '%s-%s\n' "$platform" "$cpu"
}

resolve_version() {
  if [ -n "$VERSION" ]; then
    case "$VERSION" in
      v*) printf '%s\n' "$VERSION" ;;
      *) printf 'v%s\n' "$VERSION" ;;
    esac
    return 0
  fi

  if [ "$CHANNEL" = "stable" ]; then
    fetch_stdout "https://api.github.com/repos/$REPO/releases/latest" \
      | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -n 1
    return 0
  fi

  fetch_stdout "https://api.github.com/repos/$REPO/releases?per_page=100" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*-'$CHANNEL'\.[^"]*\)".*/\1/p' \
    | head -n 1
}

write_shim() {
  name="$1"
  target="$2"
  path="$INSTALL_ROOT/bin/$name"
  cat > "$path" <<EOF
#!/usr/bin/env sh
set -eu
ROOT="\$(CDPATH= cd -- "\$(dirname -- "\$0")/.." && pwd)"
CURRENT="\$ROOT/current"
if [ -x "\$CURRENT/bin/$target" ]; then
  exec "\$CURRENT/bin/$target" "\$@"
fi
if [ -x "\$CURRENT/$target" ]; then
  exec "\$CURRENT/$target" "\$@"
fi
if [ "$target" = "ailang" ] && [ -x "\$CURRENT/airun" ]; then
  exec "\$CURRENT/airun" "\$@"
fi
echo "missing installed executable: $target" >&2
exit 127
EOF
  chmod +x "$path"
}

need tar
RID="$(detect_rid)"
TAG="$(resolve_version)"
if [ -z "$TAG" ]; then
  echo "could not resolve AiLang release for channel: $CHANNEL" >&2
  exit 1
fi
VERSION_NO_V="${TAG#v}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

ARTIFACT="ailang-$VERSION_NO_V-$RID.tar.gz"
URL="https://github.com/$REPO/releases/download/$TAG/$ARTIFACT"
if ! fetch "$URL" "$TMP_DIR/$ARTIFACT"; then
  ARTIFACT="airun-$VERSION_NO_V-$RID.tar.gz"
  URL="https://github.com/$REPO/releases/download/$TAG/$ARTIFACT"
  fetch "$URL" "$TMP_DIR/$ARTIFACT"
fi

CHECKSUMS_URL="https://github.com/$REPO/releases/download/$TAG/checksums.txt"
if fetch "$CHECKSUMS_URL" "$TMP_DIR/checksums.txt" 2>/dev/null; then
  if command -v shasum >/dev/null 2>&1 && grep "  $ARTIFACT\$" "$TMP_DIR/checksums.txt" >/dev/null 2>&1; then
    (cd "$TMP_DIR" && grep "  $ARTIFACT\$" checksums.txt | shasum -a 256 -c -)
  elif command -v sha256sum >/dev/null 2>&1 && grep "  $ARTIFACT\$" "$TMP_DIR/checksums.txt" >/dev/null 2>&1; then
    (cd "$TMP_DIR" && grep "  $ARTIFACT\$" checksums.txt | sha256sum -c -)
  fi
fi

DEST="$INSTALL_ROOT/toolchains/$VERSION_NO_V"
rm -rf "$DEST"
mkdir -p "$DEST" "$INSTALL_ROOT/bin"
tar -xzf "$TMP_DIR/$ARTIFACT" -C "$DEST" --strip-components 1

ln -sfn "$DEST" "$INSTALL_ROOT/current"
write_shim ailang ailang
write_shim airun airun
write_shim aivm aivm
write_shim aivectra aivectra

cat <<EOF
Installed AiLangCore $VERSION_NO_V for $RID

Add this to PATH:
  export PATH="$INSTALL_ROOT/bin:\$PATH"

Then run:
  ailang --version
EOF
