# Godot dedicated server sample for Gameye

A minimal Godot 4 dedicated server that runs on [Gameye](https://gameye.com). It exports a Linux dedicated server build inside a container, packages it in a Docker image and runs one match per server process, which is how Gameye runs sessions.

It goes with the [Godot guide](https://gameye.com/docs/guides/integrations/godot/) in the Gameye docs and uses the same code: the `ServerBootstrap` and `MatchLifecycle` autoloads, and the `start.sh` wrapper that turns `SIGTERM` into a stop file.

## What it shows

- An ENet server on UDP 7777 that logs `READY`, `JOIN`, `LEAVE` and `MATCH_END` lines to stdout, which is what Gameye's logs endpoint returns.
- One match per process. The server quits when the match ends, which ends the Gameye session and stops billing.
- A clean shutdown when Gameye stops a session. Godot 4 doesn't pass `SIGTERM` to scripts, so `start.sh` turns it into a stop file that `match_lifecycle.gd` checks.
- `Engine.max_fps` set to the tick rate, so the headless loop doesn't spin a CPU core.
- A Dockerfile that runs the server as a non-root user.
- A smoke test, and a join test with a headless Godot client.

No Gameye plugin or SDK is involved. The server never holds a Gameye API token.

## Requirements

- Docker. The build runs in a Linux container, so it works the same on macOS, Windows and Linux.
- About 1.4 GB of disk for the Godot editor and export templates, downloaded once from Godot's official releases and kept in a Docker volume.
- A Gameye account to deploy. Sign up at [trial.gameye.com](https://trial.gameye.com/).

## Build

```bash
scripts/build-server.sh
```

This exports the `LinuxServer` preset (Export Mode: dedicated server) with Godot 4.7.2 and writes `build/game-server.x86_64` and `build/game-server.pck`. The script checks the downloads against the release's SHA512 sums. Set `GODOT_VERSION` to build with another release.

## Test locally

```bash
scripts/smoke-test.sh
scripts/join-test.sh
```

The smoke test checks that the server logs `READY` on UDP 7777, quits with exit code 0 when a match ends, and shuts down cleanly on `SIGTERM`. The join test connects a headless Godot client and checks that the server logs `JOIN`, then `LEAVE` when the client drops, and then ends the match and exits because no players are left.

To run the server yourself:

```bash
docker build --platform linux/amd64 -t godot-dedicated-server-sample:local .
docker run --rm -p 7777:7777/udp godot-dedicated-server-sample:local -- --match-seconds=300
```

## Deploy to Gameye

1. Push the image to Docker Hub or GitHub Container Registry with a new tag for every build:

   ```bash
   docker build --platform linux/amd64 -t <you>/godot-dedicated-server-sample:build-001 .
   docker push <you>/godot-dedicated-server-sample:build-001
   ```

2. In the Gameye Admin Panel, create an application for the image with UDP port `7777` in bridge networking. See [Getting started](https://gameye.com/docs/getting-started/).

3. Start a session from your backend:

   ```bash
   curl -X POST https://api.sandbox-gameye.gameye.net/session \
     -H "Authorization: Bearer $GAMEYE_API_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "image": "godot-dedicated-server-sample",
       "location": "europe",
       "version": "build-001",
       "args": ["--", "--match-seconds=600"],
       "ttl": "30m"
     }'
   ```

   Enterprise accounts use `api.production-gameye.gameye.net`. The response holds `host` and a `ports` list. Players connect to `host` on the `host` port that maps container port 7777, with `ENetMultiplayerPeer.create_client(host, port)`.

4. Read the server's logs with [`GET /logs`](https://gameye.com/docs/api-v2/reference/get-logs/), and stop the session early with [`DELETE /session/{id}`](https://gameye.com/docs/api-v2/reference/delete-session/).

## Match options

Pass these after `--` in the session's `args`, so Godot hands them to the game:

| Option | Effect |
|---|---|
| `--match-seconds=600` | End the match after 600 seconds. `0` or absent means no time limit. |
| `--keep-alive` | Don't quit when the last player leaves. By default the server quits once every player who joined has left. |

## Files

| Path | What it is |
|---|---|
| `server_bootstrap.gd` | Starts the ENet server and logs READY, JOIN and LEAVE. Also the headless client used by the join test. |
| `match_lifecycle.gd` | The one shutdown path for match end and the stop signal. |
| `start.sh` | Runs the server and turns `SIGTERM` into the stop file. |
| `export_presets.cfg` | The `LinuxServer` export preset, exported as a dedicated server. |
| `Dockerfile` | Runtime image for the exported server. |
| `scripts/build-server.sh` | Exports the server in a Linux container. |
| `scripts/smoke-test.sh`, `scripts/join-test.sh` | Local checks before you deploy. |

## Using this in your own project

Copy the two autoloads, `start.sh`, the Dockerfile and the export preset. Two details in them matter. The container user needs a home folder, because Godot keeps its user data (`user://`) there and logs errors at startup without one. And `start.sh` runs the server under `stdbuf -oL`: Gameye runs containers with a terminal, so its logs are live either way, but with plain `docker run`, Docker Compose or CI, Godot holds `print()` output in a buffer and `docker logs` shows nothing until it fills. Report match results to your own backend in `report_results`, and let the backend call Gameye. Signal handling can change between Godot versions, so run the smoke test again after an engine upgrade.

## License

MIT. See [LICENSE](LICENSE). Godot itself is MIT-licensed by its contributors; this repository contains no engine code.
