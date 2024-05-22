class_name RandomNumberMultiplayer
extends Node

## Can be used to seed the DungeonGenerator to sync the seed with all clients on multiplayer

# Connect to DungeonGenerator generate(seed) function
signal got_random_int(num : int)

var random_number : int

func _ready():
	if is_multiplayer_authority():
		random_number = randi()
		emit_random_number(random_number)
	else:
		request_random_number.rpc_id(get_multiplayer_authority())

@rpc("authority", "call_remote", "reliable", 0)
func emit_random_number(num : int):
	got_random_int.emit(num)

@rpc("any_peer", "call_remote", "reliable", 0)
func request_random_number():
	emit_random_number.rpc_id(multiplayer.get_remote_sender_id(), random_number)
