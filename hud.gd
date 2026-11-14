extends Control
## Touch HUD: virtual joystick (left), action buttons (right), status bar.

const STICK_R := 90.0

var main = null
var move_vec := Vector2.ZERO
var act_held := false
var stick_id := -1
var act_id := -1
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func buttons() -> Dictionary:
	var s: Vector2 = get_viewport_rect().size
	var d := {"act": {"c": Vector2(s.x - 120.0, s.y - 120.0), "r": 75.0}}
	if main.player != null and not main.player.vamp:
		d["wall"] = {"c": Vector2(s.x - 290.0, s.y - 90.0), "r": 50.0}
		d["turret"] = {"c": Vector2(s.x - 170.0, s.y - 260.0), "r": 50.0}
	return d


func hit_button(p: Vector2) -> String:
	var d: Dictionary = buttons()
	for k: String in d.keys():
		var b: Dictionary = d[k]
		var c: Vector2 = b["c"]
		if p.distance_to(c) <= float(b["r"]) * 1.15:
			return k
	return ""


func _input(event: InputEvent) -> void:
	if main == null or not main.started or main.finished:
		return
	var te := event as InputEventScreenTouch
	if te != null:
		if te.pressed:
			var hit: String = hit_button(te.position)
			if hit == "act":
				act_id = te.index
				act_held = true
			elif hit != "":
				main.player_build(hit)
			elif te.position.x < get_viewport_rect().size.x * 0.55 and stick_id == -1:
				stick_id = te.index
				stick_origin = te.position
				stick_pos = te.position
				move_vec = Vector2.ZERO
		else:
			if te.index == stick_id:
				stick_id = -1
				move_vec = Vector2.ZERO
			if te.index == act_id:
				act_id = -1
				act_held = false
		return
	var de := event as InputEventScreenDrag
	if de != null and de.index == stick_id:
		var v: Vector2 = de.position - stick_origin
		if v.length() > STICK_R:
			v = v.normalized() * STICK_R
		stick_pos = stick_origin + v
		move_vec = v / STICK_R


func _draw() -> void:
	if main == null or not main.started:
		return
	var s: Vector2 = get_viewport_rect().size
	var f: Font = ThemeDB.fallback_font
	var p = main.player
	# top bar
	draw_rect(Rect2(0, 0, s.x, 48), Color(0, 0, 0, 0.55))
	var txt := "%s  %ds" % [main.title_text(), int(main.phase_left())]
	draw_string(f, Vector2(16, 34), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
	var info := "Humans alive: %d/6" % main.alive_humans()
	if p != null and not p.vamp:
		info += "    Wood: %d    HP: %d" % [p.wood, int(p.hp)]
	elif p != null:
		info += "    HP: %d" % int(p.hp)
	draw_string(f, Vector2(300, 34), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.95, 0.7))
	# status line
	var status := ""
	if p != null:
		if p.vamp:
			if not p.alive:
				status = "You were slain - respawning in the crypt..."
			elif not main.is_night:
				status = "Sunlight burns! Stay near the CRYPT (centre) until night."
			else:
				status = "Hunt the humans. Bite them, break their walls!"
		elif not p.alive:
			status = "You were eliminated - spectating."
		elif main.is_night:
			status = "Night! Get inside your base and close the gap. Turrets shoot vampires."
		else:
			status = "Day: walk near trees to gather wood, then build WALLS around your core."
	draw_string(f, Vector2(16, s.y - 12), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.9))
	# joystick
	if stick_id != -1:
		draw_circle(stick_origin, STICK_R, Color(1, 1, 1, 0.15))
		draw_circle(stick_pos, 40.0, Color(1, 1, 1, 0.45))
	else:
		draw_circle(Vector2(170, s.y - 150), STICK_R, Color(1, 1, 1, 0.08))
		draw_string(f, Vector2(120, s.y - 145), "MOVE", HORIZONTAL_ALIGNMENT_CENTER, 100, 22, Color(1, 1, 1, 0.4))
	# buttons
	var d: Dictionary = buttons()
	for k: String in d.keys():
		var b: Dictionary = d[k]
		var c: Vector2 = b["c"]
		var r: float = b["r"]
		var label := ""
		var col := Color(0.9, 0.3, 0.3, 0.55)
		if k == "act":
			label = "BITE" if (p != null and p.vamp) else "STAKE"
			if k == "act" and act_held:
				col = Color(1, 0.5, 0.5, 0.8)
		elif k == "wall":
			label = "WALL\n%d" % main.WALL_COST
			col = Color(0.6, 0.45, 0.25, 0.65)
		else:
			label = "TURRET\n%d" % main.TURRET_COST
			col = Color(0.4, 0.45, 0.6, 0.65)
		draw_circle(c, r, col)
		draw_arc(c, r, 0.0, TAU, 32, Color(1, 1, 1, 0.6), 2.0)
		var lines: PackedStringArray = label.split("\n")
		for i in lines.size():
			draw_string(f, c + Vector2(-r, 8.0 + 24.0 * (i - (lines.size() - 1) * 0.5)), lines[i], HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 22, Color.WHITE)
