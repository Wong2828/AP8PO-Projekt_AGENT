extends CharacterBody3D

# ---- constants ----
const SPEED         := 5.0
const SPRINT_SPEED  := 8.5
const JUMP_VELOCITY := 4.8
const MOUSE_SENS    := 0.0022
const MAX_HEALTH    := 100
const ATTACK_DMG    := 30
const ATTACK_CD     := 0.75   # seconds between attacks
const BLOCK_MULT    := 0.15   # fraction of damage blocked

# ---- exported / set by spawner ----
## Peer that owns this player (matches node name).
var player_peer_id: int = 1
var player_name: String = "Warrior"

# ---- state ----
var health: int     = MAX_HEALTH
var is_dead: bool   = false
var atk_timer: float = 0.0
var is_blocking: bool = false
var kills: int = 0
var deaths: int = 0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# ---- node refs ----
@onready var cam_pivot:   Node3D          = $CameraPivot
@onready var camera:      Camera3D        = $CameraPivot/Camera3D
@onready var sword_area:  Area3D          = $CameraPivot/SwordArea
@onready var body_mesh:   MeshInstance3D  = $BodyMesh
@onready var name_label:  Label3D         = $NameLabel
@onready var sync_node:   MultiplayerSynchronizer = $Sync


func _ready() -> void:
	# Derive peer id from node name (set by game.gd when adding child).
	if name.is_valid_int():
		player_peer_id = int(name)

	# Populate display name from NetworkManager dictionary if available.
	if NetworkManager.players.has(player_peer_id):
		player_name = NetworkManager.players[player_peer_id].name
	name_label.text = player_name

	set_multiplayer_authority(player_peer_id)
	sync_node.set_multiplayer_authority(player_peer_id)

	if is_multiplayer_authority():
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		body_mesh.visible = false   # hide own body in FPS
		name_label.visible = false  # don't show own name label


# ---- input (authority only) ----

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		cam_pivot.rotate_x(-event.relative.y * MOUSE_SENS)
		cam_pivot.rotation.x = clamp(cam_pivot.rotation.x, -PI / 2.1, PI / 2.1)
	if event.is_action_pressed("ui_cancel"):
		var m := Input.get_mouse_mode()
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE if m == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority() or is_dead:
		return

	# Gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Horizontal movement.
	var spd := SPRINT_SPEED if Input.is_action_pressed("sprint") else SPEED
	var dir2 := Input.get_vector("strafe_left", "strafe_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(dir2.x, 0, dir2.y)).normalized()
	if dir:
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
	else:
		velocity.x = move_toward(velocity.x, 0, spd)
		velocity.z = move_toward(velocity.z, 0, spd)

	move_and_slide()

	# Attack cooldown.
	if atk_timer > 0:
		atk_timer -= delta

	# Attack.
	if Input.is_action_just_pressed("attack") and atk_timer <= 0 and not is_blocking:
		atk_timer = ATTACK_CD
		_do_attack.rpc()

	# Block.
	is_blocking = Input.is_action_pressed("block")


# ---- combat RPCs ----

@rpc("any_peer", "call_local", "reliable")
func _do_attack() -> void:
	if is_dead:
		return
	# Hit detection runs on all peers; damage is authoritative.
	for body in sword_area.get_overlapping_bodies():
		if body == self or not body.has_method("receive_hit"):
			continue
		var target: CharacterBody3D = body
		# Only the server (or target authority) should apply damage.
		target.receive_hit.rpc_id(target.player_peer_id, ATTACK_DMG, player_peer_id)


@rpc("any_peer", "reliable")
func receive_hit(amount: int, attacker_id: int) -> void:
	# Runs on the target's authoritative machine.
	if is_dead:
		return
	if is_blocking:
		amount = int(amount * BLOCK_MULT)
	health = max(0, health - amount)
	_broadcast_health.rpc(health)
	if health == 0:
		_broadcast_death.rpc(attacker_id)


@rpc("authority", "call_local", "reliable")
func _broadcast_health(new_health: int) -> void:
	health = new_health


@rpc("authority", "call_local", "reliable")
func _broadcast_death(killer_id: int) -> void:
	if is_dead:
		return
	is_dead = true
	deaths += 1
	visible = false
	if is_multiplayer_authority():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Notify game manager on the server.
	if get_parent().get_parent().has_method("on_player_killed"):
		get_parent().get_parent().on_player_killed(player_peer_id, killer_id)


@rpc("authority", "call_local", "reliable")
func do_respawn(pos: Vector3) -> void:
	health = MAX_HEALTH
	is_dead = false
	visible = true
	global_position = pos
	velocity = Vector3.ZERO
	if is_multiplayer_authority():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
