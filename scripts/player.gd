extends CharacterBody3D

# ---- constants ----
const SPEED         := 5.0
const SPRINT_SPEED  := 8.5
const JUMP_VELOCITY := 4.8
const MOUSE_SENS    := 0.0022
const MAX_HEALTH    := 100
const MAX_STAMINA   := 100.0

const ATTACK_DMG      := 30
const HEAVY_ATTACK_DMG := 55
const KICK_DMG        := 10
const ATTACK_CD       := 0.75
const HEAVY_ATTACK_CD := 1.4
const KICK_CD         := 1.0
const BLOCK_MULT      := 0.15

const STAMINA_REGEN       := 18.0
const STAMINA_ATTACK_COST := 20.0
const STAMINA_HEAVY_COST  := 35.0
const STAMINA_BLOCK_DRAIN := 12.0
const STAMINA_SPRINT_DRAIN := 14.0
const STAMINA_KICK_COST   := 15.0
const STAMINA_JUMP_COST   := 10.0

const SWING_SPEED := 8.0

# ---- exported / set by spawner ----
var player_peer_id: int = 1
var player_name: String = "Warrior"

# ---- state ----
var health: int       = MAX_HEALTH
var stamina: float    = MAX_STAMINA
var is_dead: bool     = false
var atk_timer: float  = 0.0
var is_blocking: bool = false
var kills: int = 0
var deaths: int = 0

var _swing_progress: float = 0.0
var _swing_active: bool    = false
var _swing_is_heavy: bool  = false

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# ---- node refs ----
@onready var cam_pivot:    Node3D          = $CameraPivot
@onready var camera:       Camera3D        = $CameraPivot/Camera3D
@onready var sword_area:   Area3D          = $CameraPivot/SwordArea
@onready var sword_pivot:  Node3D          = $CameraPivot/SwordPivot
@onready var kick_area:    Area3D          = $CameraPivot/KickArea
@onready var kick_col:     CollisionShape3D = $CameraPivot/KickArea/CollisionShape3D
@onready var body_mesh:    MeshInstance3D  = $BodyMesh
@onready var name_label:   Label3D         = $NameLabel
@onready var sync_node:    MultiplayerSynchronizer = $Sync

signal player_killed(victim_id: int, killer_id: int)
signal hit_received(attacker_global_pos: Vector3)


func _ready() -> void:
	if name.is_valid_int():
		player_peer_id = int(name)

	if NetworkManager.players.has(player_peer_id):
		player_name = NetworkManager.players[player_peer_id].name
	name_label.text = player_name

	set_multiplayer_authority(player_peer_id)
	sync_node.set_multiplayer_authority(player_peer_id)

	add_to_group("players")

	if is_multiplayer_authority():
		camera.current = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		body_mesh.visible = false
		name_label.visible = false


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
	# Animate sword swing on all peers.
	_update_swing(delta)

	if not is_multiplayer_authority() or is_dead:
		return

	# Gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump.
	if Input.is_action_just_pressed("jump") and is_on_floor() and stamina >= STAMINA_JUMP_COST:
		velocity.y = JUMP_VELOCITY
		stamina -= STAMINA_JUMP_COST

	# Sprint check.
	var is_sprinting := Input.is_action_pressed("sprint") and stamina > 0.0
	var spd := SPRINT_SPEED if is_sprinting else SPEED

	# Horizontal movement.
	var dir2 := Input.get_vector("strafe_left", "strafe_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(dir2.x, 0, dir2.y)).normalized()
	if dir:
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
	else:
		velocity.x = move_toward(velocity.x, 0, spd)
		velocity.z = move_toward(velocity.z, 0, spd)

	move_and_slide()

	# Stamina drain for sprinting (only while actually moving).
	if is_sprinting and dir:
		stamina = max(0.0, stamina - STAMINA_SPRINT_DRAIN * delta)

	# Stamina drain for blocking.
	is_blocking = Input.is_action_pressed("block") and stamina > 0.0
	if is_blocking:
		stamina = max(0.0, stamina - STAMINA_BLOCK_DRAIN * delta)

	# Stamina regen (only when not blocking and not sprinting-while-moving).
	if not is_blocking and not (is_sprinting and dir):
		stamina = min(MAX_STAMINA, stamina + STAMINA_REGEN * delta)

	# Attack cooldown.
	if atk_timer > 0:
		atk_timer -= delta

	# Light attack.
	if Input.is_action_just_pressed("attack") and atk_timer <= 0 and not is_blocking and stamina >= STAMINA_ATTACK_COST:
		atk_timer = ATTACK_CD
		stamina -= STAMINA_ATTACK_COST
		_do_attack.rpc(false)

	# Heavy attack.
	if Input.is_action_just_pressed("heavy_attack") and atk_timer <= 0 and not is_blocking and stamina >= STAMINA_HEAVY_COST:
		atk_timer = HEAVY_ATTACK_CD
		stamina -= STAMINA_HEAVY_COST
		_do_attack.rpc(true)

	# Kick.
	if Input.is_action_just_pressed("kick") and atk_timer <= 0 and stamina >= STAMINA_KICK_COST:
		atk_timer = KICK_CD
		stamina -= STAMINA_KICK_COST
		_do_kick.rpc()


# ---- sword swing animation ----

func _update_swing(delta: float) -> void:
	if _swing_active:
		_swing_progress += delta * SWING_SPEED
		if _swing_progress >= 1.0:
			_swing_active = false
			_swing_progress = 0.0
			sword_pivot.rotation = Vector3.ZERO
		else:
			var angle: float
			if _swing_is_heavy:
				angle = sin(_swing_progress * PI) * 1.8
				sword_pivot.rotation = Vector3(angle, 0, 0)
			else:
				angle = sin(_swing_progress * PI) * 1.2
				sword_pivot.rotation = Vector3(0, -angle, 0)


# ---- combat RPCs ----

@rpc("any_peer", "call_local", "reliable")
func _do_attack(heavy: bool) -> void:
	if is_dead:
		return
	_swing_active = true
	_swing_progress = 0.0
	_swing_is_heavy = heavy
	var dmg := HEAVY_ATTACK_DMG if heavy else ATTACK_DMG
	for body in sword_area.get_overlapping_bodies():
		if body == self or not body.has_method("receive_hit"):
			continue
		var target: CharacterBody3D = body
		target.receive_hit.rpc_id(target.player_peer_id, dmg, player_peer_id)


@rpc("any_peer", "call_local", "reliable")
func _do_kick() -> void:
	if is_dead:
		return
	kick_col.disabled = false
	await get_tree().create_timer(0.15).timeout
	for body in kick_area.get_overlapping_bodies():
		if body == self or not body.has_method("receive_kick"):
			continue
		var target: CharacterBody3D = body
		target.receive_kick.rpc_id(target.player_peer_id, KICK_DMG, player_peer_id)
	kick_col.disabled = true


@rpc("any_peer", "reliable")
func receive_hit(amount: int, attacker_id: int) -> void:
	if is_dead:
		return
	if is_blocking:
		amount = int(amount * BLOCK_MULT)
	health = max(0, health - amount)
	_broadcast_health.rpc(health)
	_notify_hit.rpc_id(player_peer_id, attacker_id)
	if health == 0:
		_broadcast_death.rpc(attacker_id)


@rpc("any_peer", "reliable")
func receive_kick(_amount: int, attacker_id: int) -> void:
	if is_dead:
		return
	if is_blocking:
		is_blocking = false
		stamina = max(0.0, stamina - 30.0)
	health = max(0, health - _amount)
	_broadcast_health.rpc(health)
	_notify_hit.rpc_id(player_peer_id, attacker_id)
	if health == 0:
		_broadcast_death.rpc(attacker_id)


@rpc("any_peer", "reliable")
func _notify_hit(attacker_id: int) -> void:
	var attacker := get_parent().get_node_or_null(str(attacker_id))
	if attacker:
		hit_received.emit(attacker.global_position)


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
	# Notify game manager via group instead of fragile parent chain.
	for node in get_tree().get_nodes_in_group("game_manager"):
		if node.has_method("on_player_killed"):
			node.on_player_killed(player_peer_id, killer_id)


@rpc("authority", "call_local", "reliable")
func do_respawn(pos: Vector3) -> void:
	health = MAX_HEALTH
	stamina = MAX_STAMINA
	is_dead = false
	visible = true
	global_position = pos
	velocity = Vector3.ZERO
	if is_multiplayer_authority():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
