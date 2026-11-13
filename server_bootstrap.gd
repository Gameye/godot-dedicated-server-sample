# Starts the ENet server in the dedicated server build and logs the match
# lifecycle to stdout, which is what Gameye's logs endpoint returns.
#
# Options, passed after `--` in the session's args:
#   --match-seconds=600     end the match after this many seconds (0 = no limit)
#   --keep-alive            don't quit when the last player leaves
#   --connect=HOST:PORT     run as a headless client instead (used by the join test)
extends Node

const PORT := 7777
const MAX_CLIENTS := 16

var _players := 0
var _any_joined := false
var _quit_when_empty := true


func _ready() -> void:
	var options := _parse_user_args()
	if options.has("connect"):
		_start_client(options["connect"])
		return
	if not OS.has_feature("dedicated_server"):
		return

	Engine.max_fps = 60   # the tick rate; without a cap the headless loop spins a core
	_quit_when_empty = not options.has("keep-alive")

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		push_error("bind failed: %s" % err)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("READY port=%d" % PORT)

	var match_seconds := int(options.get("match-seconds", "0"))
	if match_seconds > 0:
		get_tree().create_timer(match_seconds).timeout.connect(
			func(): MatchLifecycle.end_match("time limit"))


func _on_peer_connected(id: int) -> void:
	_players += 1
	_any_joined = true
	print("JOIN %d players=%d" % [id, _players])


func _on_peer_disconnected(id: int) -> void:
	_players = max(0, _players - 1)
	print("LEAVE %d players=%d" % [id, _players])
	if _quit_when_empty and _any_joined and _players == 0:
		MatchLifecycle.end_match("all players left")


func _start_client(address: String) -> void:
	var parts := address.rsplit(":", true, 1)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(parts[0], int(parts[1]))
	if err != OK:
		push_error("connect failed: %s" % err)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(func(): print("CONNECTED %s" % address))
	multiplayer.connection_failed.connect(func():
		push_error("connection to %s failed" % address)
		get_tree().quit(1))


func _parse_user_args() -> Dictionary:
	var options := {}
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		options[pair[0]] = pair[1] if pair.size() > 1 else ""
	return options
