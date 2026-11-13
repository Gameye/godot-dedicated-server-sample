#!/usr/bin/env bash
# Build the server image and check what Gameye relies on:
#   1. the server starts and logs READY on UDP 7777
#   2. it quits by itself when the match ends (exit code 0)
#   3. it shuts down cleanly on SIGTERM, as when Gameye stops a session
#
#   scripts/smoke-test.sh [image-tag]
set -euo pipefail

TAG=${1:-godot-dedicated-server-sample:smoke}
NAME=gds-smoke-$$
fail() { printf 'smoke-test: FAIL %s\n' "$*" >&2; docker logs "$NAME" 2>&1 | tail -n 20 >&2 || true; docker rm -f "$NAME" >/dev/null 2>&1 || true; exit 1; }
pass() { printf 'smoke-test: ok   %s\n' "$*"; }
wait_for_log() { local i; for ((i = 0; i < $2; i++)); do docker logs "$NAME" 2>&1 | grep -c -- "$1" >/dev/null && return 0; sleep 1; done; return 1; }

cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ -x build/game-server.x86_64 ]] || fail "no server build; run scripts/build-server.sh first"
docker build --platform linux/amd64 -q -t "$TAG" . >/dev/null
pass "image $TAG built"

# 1 and 2: a match with a 5 second time limit ends on its own.
docker run -d --name "$NAME" --platform linux/amd64 -p 7777:7777/udp "$TAG" -- --match-seconds=5 >/dev/null
wait_for_log 'READY port=7777' 60 || fail "no READY line within 60 s"
pass "server READY on 7777"
wait_for_log 'MATCH_END reason="time limit"' 60 || fail "match did not end after --match-seconds=5"
code=$(docker wait "$NAME")
[[ "$code" == 0 ]] || fail "exit code $code after match end"
pass "match ended and the process exited with code 0"
docker rm "$NAME" >/dev/null

# 3: SIGTERM, as sent by DELETE /session/{id} or ttl expiry.
docker run -d --name "$NAME" --platform linux/amd64 "$TAG" >/dev/null
wait_for_log 'READY port=7777' 60 || fail "no READY line within 60 s"
start=$(date +%s)
docker stop --timeout 50 "$NAME" >/dev/null
took=$(($(date +%s) - start))
code=$(docker inspect -f '{{.State.ExitCode}}' "$NAME")
docker logs "$NAME" 2>&1 | grep -c 'SHUTDOWN reason="stop signal"' >/dev/null || fail "no SHUTDOWN line after SIGTERM"
[[ "$code" == 0 ]] || fail "exit code $code after SIGTERM (137 means it was killed)"
pass "SIGTERM: clean shutdown in ${took}s, exit code 0"
docker rm "$NAME" >/dev/null
