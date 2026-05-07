#!/usr/bin/env sh
set -eu

REPO="${AILANG_REPO:-AiLangCore/AiLang}"
AIVM_REPO="${AIVM_REPO:-AiLangCore/AiVM}"
AIVECTRA_REPO="${AIVECTRA_REPO:-AiLangCore/AiVectra}"
INSTALL_ROOT="${AILANG_INSTALL_ROOT:-$HOME/.ailang}"
CHANNEL="${AILANG_CHANNEL:-alpha}"
VERSION="${AILANG_VERSION:-}"
AIVM_VERSION="${AIVM_VERSION:-}"
AIVECTRA_VERSION="${AIVECTRA_VERSION:-}"

usage() {
  cat <<'EOF'
Usage: install.sh [--version <version>] [--channel alpha|beta|rc|stable] [--root <path>]

Environment:
  AILANG_REPO          GitHub repo to download from. Default: AiLangCore/AiLang
  AIVM_REPO            GitHub repo to download AiVM from. Default: AiLangCore/AiVM
  AIVECTRA_REPO        GitHub repo to download AiVectra from. Default: AiLangCore/AiVectra
  AILANG_VERSION      Exact version or tag to install.
  AIVM_VERSION         Exact AiVM version or tag to install.
  AIVECTRA_VERSION     Exact AiVectra version or tag to install.
  AILANG_CHANNEL      alpha, beta, rc, or stable. Default: alpha.
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

detect_platform() {
  os="$(uname -s)"
  case "$os" in
    Darwin) printf '%s\n' "macos" ;;
    Linux) printf '%s\n' "linux" ;;
    *) echo "unsupported OS: $os" >&2; exit 1 ;;
  esac
}

normalize_tag() {
  value="$1"
  case "$value" in
    v*) printf '%s\n' "$value" ;;
    *) printf 'v%s\n' "$value" ;;
  esac
}

resolve_repo_version() {
  repo="$1"
  exact="$2"
  if [ -n "$exact" ]; then
    case "$exact" in
      v*) printf '%s\n' "$exact" ;;
      *) printf 'v%s\n' "$exact" ;;
    esac
    return 0
  fi

  if [ "$CHANNEL" = "stable" ]; then
    fetch_stdout "https://api.github.com/repos/$repo/releases/latest" \
      | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -n 1
    return 0
  fi

  fetch_stdout "https://api.github.com/repos/$repo/releases?per_page=100" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*-'$CHANNEL'\.[^"]*\)".*/\1/p' \
    | head -n 1
}

resolve_version() {
  resolve_repo_version "$REPO" "$VERSION"
}

extract_archive() {
  archive="$1"
  dest="$2"
  case "$archive" in
    *.tar.gz) tar -xzf "$archive" -C "$dest" --strip-components 1 ;;
    *.zip)
      need unzip
      unzip -q "$archive" -d "$TMP_DIR/unzip"
      first_dir="$(find "$TMP_DIR/unzip" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
      if [ -n "$first_dir" ]; then
        cp -R "$first_dir"/. "$dest"/
      else
        cp -R "$TMP_DIR/unzip"/. "$dest"/
      fi
      rm -rf "$TMP_DIR/unzip"
      ;;
    *) echo "unsupported archive: $archive" >&2; exit 1 ;;
  esac
}

download_release_asset() {
  repo="$1"
  tag="$2"
  artifact="$3"
  out="$4"
  fetch "https://github.com/$repo/releases/download/$tag/$artifact" "$out"
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
PLATFORM="$(detect_platform)"
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
extract_archive "$TMP_DIR/$ARTIFACT" "$DEST"

AIVM_TAG="$(resolve_repo_version "$AIVM_REPO" "$AIVM_VERSION")"
if [ -n "$AIVM_TAG" ]; then
  AIVM_VERSION_NO_V="${AIVM_TAG#v}"
  AIVM_STAGE="$TMP_DIR/aivm"
  mkdir -p "$AIVM_STAGE" "$DEST/bin" "$DEST/aivm"
  AIVM_ARTIFACT="aivm-$AIVM_VERSION_NO_V-$PLATFORM.tar.gz"
  download_release_asset "$AIVM_REPO" "$AIVM_TAG" "$AIVM_ARTIFACT" "$TMP_DIR/$AIVM_ARTIFACT"
  extract_archive "$TMP_DIR/$AIVM_ARTIFACT" "$AIVM_STAGE"
  cp -R "$AIVM_STAGE"/. "$DEST/aivm"/
  if [ -x "$AIVM_STAGE/bin/aivm" ]; then
    cp "$AIVM_STAGE/bin/aivm" "$DEST/bin/aivm"
    chmod +x "$DEST/bin/aivm"
  fi
fi

AIVECTRA_TAG="$(resolve_repo_version "$AIVECTRA_REPO" "$AIVECTRA_VERSION")"
if [ -n "$AIVECTRA_TAG" ]; then
  AIVECTRA_VERSION_NO_V="${AIVECTRA_TAG#v}"
  AIVECTRA_STAGE="$TMP_DIR/aivectra"
  mkdir -p "$AIVECTRA_STAGE" "$DEST/bin" "$DEST/aivectra"
  AIVECTRA_ARTIFACT="aivectra-$AIVECTRA_VERSION_NO_V.tar.gz"
  download_release_asset "$AIVECTRA_REPO" "$AIVECTRA_TAG" "$AIVECTRA_ARTIFACT" "$TMP_DIR/$AIVECTRA_ARTIFACT"
  extract_archive "$TMP_DIR/$AIVECTRA_ARTIFACT" "$AIVECTRA_STAGE"
  cp -R "$AIVECTRA_STAGE"/. "$DEST/aivectra"/
  if [ -x "$AIVECTRA_STAGE/bin/aivectra" ]; then
    cp "$AIVECTRA_STAGE/bin/aivectra" "$DEST/bin/aivectra"
    chmod +x "$DEST/bin/aivectra"
  fi
fi

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
