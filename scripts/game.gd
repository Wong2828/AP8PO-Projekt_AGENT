extends Node3D

const PLAYER_SCENE := preload("res://scenes/player.tscn")

const SPAWN_POSITIONS: Array[Vector3] = [
	Vector3(  8, 1,  8),
	Vector3( -8, 1,  8),
	Vector3(  8, 1, -8),
	Vector3( -8, 1, -8),
	Vector3( 13, 1,  0),
	Vector3(-13, 1,  0),
	Vector3(  0, 1, 13),
	Vector3(  0, 1,-13),
]

const RESPAWN_DELAY := 4.0

@onready var players_node: Node3D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var hud: CanvasLayer = $HUD

var _spawn_idx: int = 0


func _ready() -> void:
	if not multiplayer.is_server():
		return

	# Spawn all players that are already registered.
	for pid in NetworkManager.players:
		_spawn_player(pid)

	# Spawn future joiners.
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)


func _spawn_player(peer_id: int) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	players_node.add_child(player, true)
	var pos := SPAWN_POSITIONS[_spawn_idx % SPAWN_POSITIONS.size()]
	_spawn_idx += 1
	player.global_position = pos


func _on_player_joined(peer_id: int) -> void:
	if multiplayer.is_server():
		_spawn_player(peer_id)


func _on_player_left(peer_id: int) -> void:
	var node := players_node.get_node_or_null(str(peer_id))
	if node:
		node.queue_free()


## Called by player.gd _broadcast_death (call_local) when health hits 0.
## Only the server drives global state.
func on_player_killed(victim_id: int, killer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var victim_name: String = NetworkManager.players.get(victim_id, {}).get("name", "Unknown")
	var killer_name: String = NetworkManager.players.get(killer_id, {}).get("name", "Unknown")
	_show_kill_feed.rpc(killer_name, victim_name)
	var killer_node := players_node.get_node_or_null(str(killer_id))
	if killer_node:
		killer_node.kills += 1
	_do_respawn(victim_id)


func _do_respawn(victim_id: int) -> void:
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	var player := players_node.get_node_or_null(str(victim_id))
	if player == null:
		return
	var pos := SPAWN_POSITIONS[randi() % SPAWN_POSITIONS.size()]
	player.do_respawn.rpc(pos)


@rpc("authority", "call_local", "reliable")
func _show_kill_feed(killer: String, victim: String) -> void:
	if hud and hud.has_method("show_kill"):
		hud.show_kill(killer, victim)
