#!/usr/bin/env bash
# Export the Linux dedicated server build inside a Linux container. Downloads
# the official Godot editor and export templates once, checks them against the
# release's SHA512 sums, and keeps them in the Docker volume godot-<version>.
#
#   scripts/build-server.sh
#
# Output: build/game-server.x86_64 and build/game-server.pck
#
# Environment (optional):
#   GODOT_VERSION   default 4.7.2 (the version this sample is tested with)
set -euo pipefail

VERSION=${GODOT_VERSION:-4.7.2}
RELEASE="$VERSION-stable"
BASE="https://github.com/godotengine/godot-builds/releases/download/$RELEASE"

in_container() {
  local tools=/tools/$RELEASE
  local editor="$tools/Godot_v${RELEASE}_linux.x86_64"
  local templates="$HOME/.local/share/godot/export_templates/${VERSION}.stable"
  apt-get update -qq && apt-get install -y -qq --no-install-recommends ca-certificates curl unzip libfontconfig1 >/dev/null
  mkdir -p "$tools"
  cd "$tools"
  if [[ ! -x "$editor" || ! -f templates.ok ]]; then
    curl -fsSLO "$BASE/SHA512-SUMS.txt"
    for f in "Godot_v${RELEASE}_linux.x86_64.zip" "Godot_v${RELEASE}_export_templates.tpz"; do
      [[ -f "$f" ]] || { echo "downloading $f"; curl -fsSLO "$BASE/$f"; }
      grep " $f\$" SHA512-SUMS.txt | sha512sum -c - || { rm -f "$f"; echo "checksum mismatch: $f" >&2; exit 1; }
    done
    unzip -oq "Godot_v${RELEASE}_linux.x86_64.zip"
    touch templates.ok
  fi
  mkdir -p "$templates"
  [[ -f "$templates/version.txt" ]] || unzip -oqj "Godot_v${RELEASE}_export_templates.tpz" 'templates/linux_release.x86_64' 'templates/version.txt' -d "$templates"

  # Export from a container-local copy; the project is mounted read-only.
  rm -rf /work && mkdir -p /work /out
  tar -C /project --exclude=./build --exclude=./.godot -cf - . | tar -C /work -xf -
  cd /work
  "$editor" --headless --import >/out/import.log 2>&1 || true
  "$editor" --headless --export-release "LinuxServer" /out/game-server.x86_64 2>&1 | tee /out/export.log
  [[ -x /out/game-server.x86_64 && -f /out/game-server.pck ]] || { echo "export failed, see build/export.log" >&2; exit 1; }
  cp "$editor" /out/godot-editor.x86_64   # the join test uses it as a headless client
}

on_host() {
  command -v docker >/dev/null 2>&1 || { echo "docker not found" >&2; exit 1; }
  local repo
  repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  mkdir -p "$repo/build"
  docker run --rm --platform linux/amd64 \
    -v "$repo:/project:ro" -v "$repo/build:/out" -v "godot-$VERSION:/tools" \
    -e GODOT_VERSION="$VERSION" \
    debian:bookworm-slim bash /project/scripts/build-server.sh --in-container
  echo "done: $repo/build/game-server.x86_64"
}

if [[ "${1:-}" == "--in-container" ]]; then in_container; else on_host; fi
