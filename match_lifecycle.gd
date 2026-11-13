# One shutdown path for both ways a match ends: the natural end, and Gameye
# stopping the session. Godot 4 doesn't pass SIGTERM to scripts, so start.sh
# turns it into a stop file, which this autoload checks four times a second.
extends Node

const STOP_FILE := "/tmp/gameye-stop"   # start.sh creates it on SIGTERM

var _stopping := false


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	var poll := Timer.new()
	poll.wait_time = 0.25
	poll.timeout.connect(_check_stop_file)
	add_child(poll)
	poll.start()


func _check_stop_file() -> void:
	if FileAccess.file_exists(STOP_FILE):
		shutdown("stop signal")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:   # a normal quit request, not SIGTERM
		shutdown("quit request")


# Call when the match is over. The process exits with code 0, the Gameye
# session ends and billing stops. Don't go back to a lobby: start a new
# session for the next match.
func end_match(reason: String) -> void:
	if _stopping:
		return
	print("MATCH_END reason=\"%s\"" % reason)
	shutdown(reason)


func shutdown(reason: String) -> void:
	if _stopping:
		return
	_stopping = true
	if reason == "stop signal":
		print("SHUTDOWN reason=\"%s\"" % reason)
	# Gameye kills the container 50 seconds after SIGTERM; this timer is a
	# safety net so a slow report can't hold the server open.
	get_tree().create_timer(10.0).timeout.connect(get_tree().quit.bind(0))
	await report_results(reason)
	get_tree().quit(0)


# Send the match result to your own backend here, and keep it to a few
# seconds. The server never holds a Gameye API token.
func report_results(reason: String) -> void:
	print("RESULTS reported (%s)" % reason)
