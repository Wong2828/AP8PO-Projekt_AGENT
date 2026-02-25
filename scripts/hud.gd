extends CanvasLayer

const MAX_FEED_ENTRIES := 6
const FEED_DURATION    := 5.0

var _health_bar: ProgressBar
var _health_label: Label
var _dead_panel: Panel
var _dead_label: Label
var _crosshair: Label
var _kill_feed_vbox: VBoxContainer
var _kills_label: Label
var _esc_hint: Label

var _local_player: CharacterBody3D = null


func _ready() -> void:
	_build_hud()
	# Poll for the local player each frame once it exists.
	set_process(true)


func _process(_delta: float) -> void:
	if _local_player == null:
		_find_local_player()
	_update_hud()


func _find_local_player() -> void:
	var players_node := get_parent().get_node_or_null("Players")
	if players_node == null:
		return
	for child in players_node.get_children():
		if child.is_multiplayer_authority():
			_local_player = child
			break


func _update_hud() -> void:
	if _local_player == null:
		return

	var hp: int = _local_player.health
	_health_bar.value = hp
	_health_label.text = "%d / %d" % [hp, _local_player.MAX_HEALTH]

	var dead: bool = _local_player.is_dead
	_dead_panel.visible = dead
	_crosshair.visible = not dead
	_esc_hint.visible = not dead

	if dead:
		_dead_label.text = "☠  You were slain  ☠\nRespawning in a few seconds…"

	_kills_label.text = "Kills: %d   Deaths: %d" % [_local_player.kills, _local_player.deaths]


## Called by game.gd (via RPC) to display a kill event.
func show_kill(killer: String, victim: String) -> void:
	var entry := Label.new()
	entry.text = "⚔  %s  slew  %s" % [killer, victim]
	entry.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	entry.add_theme_font_size_override("font_size", 16)
	_kill_feed_vbox.add_child(entry)
	# Limit entries
	while _kill_feed_vbox.get_child_count() > MAX_FEED_ENTRIES:
		_kill_feed_vbox.get_child(0).queue_free()
	# Auto-remove after duration
	get_tree().create_timer(FEED_DURATION).timeout.connect(
		func() -> void:
			if is_instance_valid(entry):
				entry.queue_free()
	)


# ─── UI construction ───────────────────────────────────────────────

func _build_hud() -> void:
	# Crosshair (centre)
	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.add_theme_font_size_override("font_size", 28)
	_crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.position -= Vector2(8, 14)
	add_child(_crosshair)

	# Health bar (bottom-left)
	var hp_bg := ColorRect.new()
	hp_bg.color = Color(0, 0, 0, 0.55)
	hp_bg.set_anchor(SIDE_LEFT,   0)
	hp_bg.set_anchor(SIDE_TOP,    1)
	hp_bg.set_anchor(SIDE_RIGHT,  0)
	hp_bg.set_anchor(SIDE_BOTTOM, 1)
	hp_bg.offset_left   = 16
	hp_bg.offset_top    = -76
	hp_bg.offset_right  = 256
	hp_bg.offset_bottom = -16
	add_child(hp_bg)

	var hp_vbox := VBoxContainer.new()
	hp_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hp_vbox.add_theme_constant_override("separation", 4)
	hp_bg.add_child(hp_vbox)

	var hp_title := Label.new()
	hp_title.text = "  ♥  HEALTH"
	hp_title.add_theme_font_size_override("font_size", 13)
	hp_title.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	hp_vbox.add_child(hp_title)

	_health_bar = ProgressBar.new()
	_health_bar.min_value = 0
	_health_bar.max_value = 100
	_health_bar.value = 100
	_health_bar.custom_minimum_size = Vector2(0, 22)
	_health_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_vbox.add_child(_health_bar)

	_health_label = Label.new()
	_health_label.text = "100 / 100"
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_label.add_theme_font_size_override("font_size", 12)
	_health_label.add_theme_color_override("font_color", Color.WHITE)
	hp_vbox.add_child(_health_label)

	# Kill/death counter (top-left)
	var kd_bg := ColorRect.new()
	kd_bg.color = Color(0, 0, 0, 0.45)
	kd_bg.set_anchor(SIDE_LEFT,   0)
	kd_bg.set_anchor(SIDE_TOP,    0)
	kd_bg.set_anchor(SIDE_RIGHT,  0)
	kd_bg.set_anchor(SIDE_BOTTOM, 0)
	kd_bg.offset_left   = 8
	kd_bg.offset_top    = 8
	kd_bg.offset_right  = 240
	kd_bg.offset_bottom = 38
	add_child(kd_bg)

	_kills_label = Label.new()
	_kills_label.text = "Kills: 0   Deaths: 0"
	_kills_label.add_theme_font_size_override("font_size", 14)
	_kills_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_kills_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kills_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kd_bg.add_child(_kills_label)

	# Kill feed (top-right)
	var feed_bg := ColorRect.new()
	feed_bg.color = Color(0, 0, 0, 0.40)
	feed_bg.set_anchor(SIDE_LEFT,   1)
	feed_bg.set_anchor(SIDE_TOP,    0)
	feed_bg.set_anchor(SIDE_RIGHT,  1)
	feed_bg.set_anchor(SIDE_BOTTOM, 0)
	feed_bg.offset_left   = -380
	feed_bg.offset_top    = 8
	feed_bg.offset_right  = -8
	feed_bg.offset_bottom = 180
	add_child(feed_bg)

	_kill_feed_vbox = VBoxContainer.new()
	_kill_feed_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_kill_feed_vbox.add_theme_constant_override("separation", 4)
	feed_bg.add_child(_kill_feed_vbox)

	# Dead overlay (centre)
	_dead_panel = Panel.new()
	_dead_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dead_panel.visible = false
	var dead_style := StyleBoxFlat.new()
	dead_style.bg_color = Color(0.1, 0, 0, 0.72)
	_dead_panel.add_theme_stylebox_override("panel", dead_style)
	add_child(_dead_panel)

	_dead_label = Label.new()
	_dead_label.text = "☠  You were slain  ☠"
	_dead_label.add_theme_font_size_override("font_size", 36)
	_dead_label.add_theme_color_override("font_color", Color(0.95, 0.2, 0.2))
	_dead_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dead_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dead_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dead_panel.add_child(_dead_label)

	# ESC hint (bottom-centre)
	_esc_hint = Label.new()
	_esc_hint.text = "ESC – toggle cursor"
	_esc_hint.add_theme_font_size_override("font_size", 12)
	_esc_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_esc_hint.set_anchor(SIDE_LEFT,   0)
	_esc_hint.set_anchor(SIDE_TOP,    1)
	_esc_hint.set_anchor(SIDE_RIGHT,  1)
	_esc_hint.set_anchor(SIDE_BOTTOM, 1)
	_esc_hint.offset_top    = -28
	_esc_hint.offset_bottom = -4
	_esc_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_esc_hint)
