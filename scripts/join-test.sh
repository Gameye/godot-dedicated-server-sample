#!/usr/bin/env bash
# Connect a headless Godot client to the server and check the match lifecycle:
# the server logs JOIN, then LEAVE when the client quits, and then ends the
# match and exits with code 0 because no players are left.
#
#   scripts/build-server.sh   # also saves the Godot editor the client runs on
#   scripts/join-test.sh
set -euo pipefail

SRV=gds-join-srv-$$ CLI=gds-join-cli-$$
cleanup() { docker rm -f "$SRV" "$CLI" >/dev/null 2>&1 || true; }
trap cleanup EXIT
fail() { printf 'join-test: FAIL %s\n' "$*" >&2; docker logs "$SRV" 2>&1 | tail -n 10 >&2 || true; docker logs "$CLI" 2>&1 | tail -n 10 >&2 || true; exit 1; }
pass() { printf 'join-test: ok   %s\n' "$*"; }
server_log_has() { docker logs "$SRV" 2>&1 | grep -c -- "$1" >/dev/null; }
wait_for() { local i; for ((i = 0; i < $2; i++)); do server_log_has "$1" && return 0; sleep 1; done; return 1; }

cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ -x build/game-server.x86_64 && -x build/godot-editor.x86_64 ]] || fail "no build; run scripts/build-server.sh"

docker build --platform linux/amd64 -q -t godot-dedicated-server-sample:join-server . >/dev/null
# The client image builds from its own folder: the project's .dockerignore
# only lets the server build through.
ctx=$(mktemp -d)
cp build/godot-editor.x86_64 project.godot main.tscn server_bootstrap.gd match_lifecycle.gd "$ctx/"
printf '%s\n' 'FROM debian:bookworm-slim' \
  'RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libfontconfig1 && rm -rf /var/lib/apt/lists/*' \
  'COPY godot-editor.x86_64 /usr/local/bin/godot' \
  'WORKDIR /client' 'COPY project.godot main.tscn server_bootstrap.gd match_lifecycle.gd /client/' \
  >"$ctx/Dockerfile"
docker build --platform linux/amd64 -q -t godot-dedicated-server-sample:join-client "$ctx" >/dev/null
rm -rf "$ctx"
pass "server and client images built"

docker run -d --name "$SRV" --platform linux/amd64 godot-dedicated-server-sample:join-server >/dev/null
wait_for 'READY port=7777' 60 || fail "server did not log READY"

# The client shares the server container's network and connects over localhost.
docker run -d --name "$CLI" --network "container:$SRV" --platform linux/amd64 \
  godot-dedicated-server-sample:join-client godot --headless --path /client -- --connect=127.0.0.1:7777 >/dev/null
wait_for 'JOIN ' 60 || fail "client did not join"
pass "client joined"

docker kill "$CLI" >/dev/null   # the client drops, like a player closing the game
wait_for 'LEAVE ' 60 || fail "no LEAVE after the client left"
wait_for 'MATCH_END reason="all players left"' 30 || fail "match did not end when the last player left"
code=$(docker wait "$SRV")
[[ "$code" == 0 ]] || fail "server exit code $code"
pass "client left, match ended and the server exited with code 0"
