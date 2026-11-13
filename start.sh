#!/bin/sh
# Godot 4 doesn't pass SIGTERM to scripts, so this wrapper turns it into a stop
# file that match_lifecycle.gd checks. Gameye sends SIGTERM when you stop a
# session or its ttl runs out, then SIGKILL 50 seconds later.
trap 'touch /tmp/gameye-stop' TERM INT
rm -f /tmp/gameye-stop
# stdbuf flushes stdout after every line. Gameye runs containers with a
# terminal, so its logs are live either way, but plain `docker run`, compose
# and CI give stdout a pipe, and Godot then holds print() output in a buffer.
stdbuf -oL -eL /server/game-server.x86_64 --headless "$@" &
child=$!
wait "$child"; rc=$?
# wait returns early when the trap runs; keep waiting for the server to exit.
while kill -0 "$child" 2>/dev/null; do wait "$child"; rc=$?; done
exit "$rc"
