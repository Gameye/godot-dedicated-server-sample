FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*
# Godot writes its user data (user://) under the home folder, so the user needs one.
RUN groupadd --system --gid 10001 game \
 && useradd --system --uid 10001 --gid game --create-home --home-dir /home/game --shell /usr/sbin/nologin game
WORKDIR /server
COPY --chown=game:game build/game-server.x86_64 build/game-server.pck /server/
COPY --chown=game:game --chmod=755 start.sh /server/start.sh
RUN chmod +x /server/game-server.x86_64
USER game
EXPOSE 7777/udp
# Exec form, so SIGTERM reaches start.sh.
ENTRYPOINT ["/server/start.sh"]
