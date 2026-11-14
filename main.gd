extends Node2D
## Humans vs Vampires - 8 players: 6 humans (each builds a base) and 2 vampires.
## You control one player, the other seven are bots.

const HudScript := preload("res://hud.gd")

const TILE := 40
const MAP_W := 60
const MAP_H := 40
const WORLD := Vector2(MAP_W * TILE, MAP_H * TILE)
const DAY_LEN := 35.0
const NIGHT_LEN := 40.0
const NIGHTS_TO_WIN := 5
const WALL_COST := 4
const TURRET_COST := 15
const BUILD_RADIUS := 300.0
const HUMAN_SPEED := 135.0
const VAMP_SPEED := 165.0
const CRYPT := Vector2(1200, 800)
const BASE_COLORS := [
	Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.2), Color(0.3, 0.9, 0.5),
	Color(1.0, 0.5, 0.8), Color(1.0, 0.6, 0.2), Color(0.7, 0.5, 1.0),
]
const TURRET_OFFSETS := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]


class Actor:
	var name := ""
	var pos := Vector2.ZERO
	var hp := 100.0
	var max_hp := 100.0
	var vamp := false
	var is_player := false
	var alive := true
	var wood := 20
	var base := -1
	var face := Vector2.DOWN
	var cd := 0.0
	var respawn := 0.0
	var harvest_cd := 0.0
	var goal_t := 0.0
	var base_target := 0
	var mode := "gather"
	var stuck_t := 0.0
	var last_pos := Vector2.ZERO
	var wander_t := 0.0
	var wander_dir := Vector2.ZERO


var rng := RandomNumberGenerator.new()
var actors: Array = []
var structures: Dictionary = {}   # Vector2i -> {type, hp, max, owner, cd}
var trees: Array = []             # {pos, wood}
var cores: Array = []             # Vector2i per base
var ring_offsets: Array = []
var effects: Array = []
var player: Actor = null
var spectate_target: Actor = null

var started := false
var finished := false
var is_night := false
var night_no := 0
var day_no := 1
var phase_t := 0.0
var regrow_t := 0.0

var cam: Camera2D
var canvas_mod: CanvasModulate
var hud = null
var menu: ColorRect
var title_lbl: Label
var info_lbl: Label
var btn_start: Button
var btn_h: Button
var btn_v: Button
var btn_again: Button


func _ready() -> void:
	rng.randomize()
	for x in range(-2, 3):
		for y in range(-2, 3):
			if maxi(absi(x), absi(y)) == 2 and not (x == 0 and y == 2):
				ring_offsets.append(Vector2i(x, y))
	cam = Camera2D.new()
	cam.position = CRYPT
	add_child(cam)
	canvas_mod = CanvasModulate.new()
	add_child(canvas_mod)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HudScript.new()
	hud.main = self
	layer.add_child(hud)
	build_menu(layer)
	generate_world()


# ---------------------------------------------------------------- menu

func build_menu(layer: CanvasLayer) -> void:
	menu = ColorRect.new()
	menu.color = Color(0, 0, 0, 0.78)
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(menu)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(cc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 22)
	cc.add_child(box)
	title_lbl = Label.new()
	title_lbl.text = "HUMANS vs VAMPIRES"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 58)
	box.add_child(title_lbl)
	info_lbl = Label.new()
	info_lbl.text = "8 players: 6 humans build bases and survive %d nights.\n2 vampires hunt them in the dark.\nHumans: gather wood (walk near trees), build WALLS and TURRETS.\nWASD + Space + Q/E on keyboard." % NIGHTS_TO_WIN
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.add_theme_font_size_override("font_size", 26)
	box.add_child(info_lbl)
	btn_start = make_button("START GAME")
	btn_start.custom_minimum_size = Vector2(520, 120)
	btn_start.add_theme_font_size_override("font_size", 48)
	btn_start.pressed.connect(start_game.bind(false))
	box.add_child(btn_start)
	btn_h = make_button("Play as HUMAN")
	btn_h.pressed.connect(start_game.bind(false))
	box.add_child(btn_h)
	btn_v = make_button("Play as VAMPIRE")
	btn_v.pressed.connect(start_game.bind(true))
	box.add_child(btn_v)
	btn_again = make_button("Play again")
	btn_again.pressed.connect(func(): get_tree().reload_current_scene())
	btn_again.visible = false
	box.add_child(btn_again)
	var ver_lbl := Label.new()
	ver_lbl.text = "Version " + game_version()
	ver_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver_lbl.add_theme_font_size_override("font_size", 22)
	ver_lbl.modulate = Color(1, 1, 1, 0.6)
	box.add_child(ver_lbl)


func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))


func make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 90)
	b.add_theme_font_size_override("font_size", 36)
	return b


func _input(event: InputEvent) -> void:
	# Direct tap handling for the menu (does not depend on the GUI button system).
	if menu == null or not menu.visible:
		return
	var pos := Vector2.ZERO
	var pressed := false
	var te := event as InputEventScreenTouch
	var me := event as InputEventMouseButton
	if te != null and te.pressed:
		pos = te.position
		pressed = true
	elif me != null and me.pressed:
		pos = me.position
		pressed = true
	if not pressed:
		return
	if btn_again.visible and btn_again.get_global_rect().has_point(pos):
		get_tree().reload_current_scene()
	elif btn_start.visible and btn_start.get_global_rect().has_point(pos):
		start_game(false)
	elif btn_h.visible and btn_h.get_global_rect().has_point(pos):
		start_game(false)
	elif btn_v.visible and btn_v.get_global_rect().has_point(pos):
		start_game(true)


func start_game(as_vamp: bool) -> void:
	if started:
		return
	menu.visible = false
	var humans: Array = []
	var vamps: Array = []
	for i in 6:
		var h := Actor.new()
		h.name = "Human %d" % (i + 1)
		h.base = i
		h.pos = tile_center(cores[i] + Vector2i(0, 1))
		h.last_pos = h.pos
		humans.append(h)
		actors.append(h)
	for i in 2:
		var v := Actor.new()
		v.name = "Vampire %d" % (i + 1)
		v.vamp = true
		v.max_hp = 200.0
		v.hp = 200.0
		v.pos = CRYPT + Vector2(-40 + 80 * i, 0)
		v.base_target = rng.randi_range(0, 5)
		vamps.append(v)
		actors.append(v)
	if as_vamp:
		player = vamps[0]
	else:
		player = humans[rng.randi_range(0, 5)]
	player.is_player = true
	player.name = "You"
	started = true


# ---------------------------------------------------------------- world

func generate_world() -> void:
	cores = [Vector2i(10, 8), Vector2i(30, 8), Vector2i(50, 8),
		Vector2i(10, 31), Vector2i(30, 31), Vector2i(50, 31)]
	for i in cores.size():
		structures[cores[i]] = {"type": "core", "hp": 400.0, "max": 400.0, "owner": i, "cd": 0.0}
	var tries := 0
	while trees.size() < 90 and tries < 3000:
		tries += 1
		var p := Vector2(rng.randf_range(60.0, WORLD.x - 60.0), rng.randf_range(60.0, WORLD.y - 60.0))
		if p.distance_to(CRYPT) < 170.0:
			continue
		var ok := true
		for c: Vector2i in cores:
			if p.distance_to(tile_center(c)) < 135.0:
				ok = false
		for t: Dictionary in trees:
			var tp: Vector2 = t["pos"]
			if p.distance_to(tp) < 50.0:
				ok = false
		if ok:
			trees.append({"pos": p, "wood": 12})


func tile_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func tile_center(t: Vector2i) -> Vector2:
	return (Vector2(t) + Vector2(0.5, 0.5)) * TILE


func blocked_at(p: Vector2, r: float) -> bool:
	for off: Vector2 in [Vector2(-r, -r), Vector2(r, -r), Vector2(-r, r), Vector2(r, r)]:
		var q: Vector2 = p + off
		if q.x < 0.0 or q.y < 0.0 or q.x >= WORLD.x or q.y >= WORLD.y:
			return true
		if structures.has(tile_of(q)):
			return true
	return false


func try_move(a: Actor, step: Vector2) -> void:
	var np: Vector2 = a.pos + Vector2(step.x, 0.0)
	if not blocked_at(np, 13.0):
		a.pos = np
	np = a.pos + Vector2(0.0, step.y)
	if not blocked_at(np, 13.0):
		a.pos = np


func alive_humans() -> int:
	var n := 0
	for a: Actor in actors:
		if a.alive and not a.vamp:
			n += 1
	return n


func phase_left() -> float:
	return (NIGHT_LEN if is_night else DAY_LEN) - phase_t


func title_text() -> String:
	if is_night:
		return "NIGHT %d / %d" % [night_no, NIGHTS_TO_WIN]
	return "DAY %d" % day_no


# ---------------------------------------------------------------- main loop

func _process(delta: float) -> void:
	if started and not finished:
		update_clock(delta)
		for a: Actor in actors:
			update_actor(a, delta)
		update_turrets(delta)
		update_trees(delta)
		check_win()
	for e: Dictionary in effects:
		e["t"] = float(e["t"]) - delta
	effects = effects.filter(func(e): return float(e["t"]) > 0.0)
	update_camera(delta)
	hud.queue_redraw()
	queue_redraw()


func update_clock(delta: float) -> void:
	phase_t += delta
	var length: float = NIGHT_LEN if is_night else DAY_LEN
	if phase_t >= length:
		phase_t = 0.0
		if is_night:
			is_night = false
			day_no += 1
			if night_no >= NIGHTS_TO_WIN:
				end_game(true)
		else:
			is_night = true
			night_no += 1
	var dark := 0.0
	if is_night:
		dark = 1.0
		if NIGHT_LEN - phase_t < 5.0:
			dark = (NIGHT_LEN - phase_t) / 5.0
	elif DAY_LEN - phase_t < 5.0:
		dark = 1.0 - (DAY_LEN - phase_t) / 5.0
	canvas_mod.color = Color(1, 1, 1).lerp(Color(0.38, 0.4, 0.72), dark)


func update_actor(a: Actor, delta: float) -> void:
	a.cd = maxf(a.cd - delta, 0.0)
	if not a.alive:
		if a.vamp:
			a.respawn -= delta
			if a.respawn <= 0.0:
				a.alive = true
				a.hp = a.max_hp
				a.pos = CRYPT + Vector2(rng.randf_range(-50, 50), rng.randf_range(-50, 50))
		return
	if a.vamp:
		update_vamp(a, delta)
	else:
		update_human(a, delta)


func update_trees(delta: float) -> void:
	regrow_t += delta
	if regrow_t >= 3.0:
		regrow_t = 0.0
		for t: Dictionary in trees:
			if int(t["wood"]) < 12:
				t["wood"] = int(t["wood"]) + 1


func update_turrets(delta: float) -> void:
	for k: Vector2i in structures.keys():
		var s: Dictionary = structures[k]
		if s["type"] != "turret":
			continue
		s["cd"] = float(s["cd"]) - delta
		if float(s["cd"]) > 0.0:
			continue
		var c: Vector2 = tile_center(k)
		var v: Actor = nearest_vamp(c, 280.0)
		if v != null:
			damage_actor(v, 10.0)
			s["cd"] = 0.8
			effects.append({"a": c, "b": v.pos, "t": 0.12})


func check_win() -> void:
	if not finished and alive_humans() == 0:
		end_game(false)


func end_game(humans_won: bool) -> void:
	finished = true
	menu.visible = true
	title_lbl.text = "HUMANS SURVIVED!" if humans_won else "VAMPIRES WIN!"
	var you_won: bool = (humans_won and not player.vamp) or ((not humans_won) and player.vamp)
	info_lbl.text = ("You won!" if you_won else "You lost.") + "\nNights survived: %d / %d" % [night_no if not humans_won else NIGHTS_TO_WIN, NIGHTS_TO_WIN]
	btn_start.visible = false
	btn_h.visible = false
	btn_v.visible = false
	btn_again.visible = true


func update_camera(delta: float) -> void:
	var target: Vector2 = CRYPT
	if started:
		var focus: Actor = player
		if player != null and not player.alive and not player.vamp:
			if spectate_target == null or not spectate_target.alive:
				spectate_target = null
				for a: Actor in actors:
					if a.alive and not a.vamp:
						spectate_target = a
						break
			if spectate_target != null:
				focus = spectate_target
		if focus != null:
			target = focus.pos
	cam.position = cam.position.lerp(target, minf(1.0, delta * 8.0))


# ---------------------------------------------------------------- humans

func update_human(a: Actor, delta: float) -> void:
	if a.is_player:
		player_control(a, delta)
	else:
		ai_human(a, delta)
	# harvest wood from nearby trees
	a.harvest_cd -= delta
	if a.harvest_cd <= 0.0 and a.wood < 99:
		for t: Dictionary in trees:
			var tp: Vector2 = t["pos"]
			if int(t["wood"]) > 0 and tp.distance_to(a.pos) < 46.0:
				t["wood"] = maxi(0, int(t["wood"]) - 2)
				a.wood = mini(99, a.wood + 2)
				a.harvest_cd = 0.5
				break
	# heal near own core
	var ct: Vector2i = cores[a.base]
	if structures.has(ct) and a.pos.distance_to(tile_center(ct)) < 110.0:
		a.hp = minf(a.max_hp, a.hp + 4.0 * delta)


func player_control(a: Actor, delta: float) -> void:
	var kx := 0.0
	var ky := 0.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		kx += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		kx -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		ky += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		ky -= 1.0
	var d: Vector2 = hud.move_vec + Vector2(kx, ky)
	if d.length() > 1.0:
		d = d.normalized()
	var spd := HUMAN_SPEED
	if a.vamp:
		spd = VAMP_SPEED if is_night else VAMP_SPEED * 0.5
	if d.length() > 0.1:
		a.face = d.normalized()
		try_move(a, d * spd * delta)
	var act: bool = hud.act_held or Input.is_key_pressed(KEY_SPACE)
	if act and a.cd <= 0.0:
		if a.vamp:
			vamp_attack(a)
		else:
			human_attack(a)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo:
		if not started:
			if k.keycode == KEY_H or k.keycode == KEY_ENTER or k.keycode == KEY_SPACE:
				start_game(false)
			elif k.keycode == KEY_V:
				start_game(true)
			return
		if k.keycode == KEY_1 or k.keycode == KEY_Q:
			player_build("wall")
		elif k.keycode == KEY_2 or k.keycode == KEY_E:
			player_build("turret")


func player_build(type: String) -> void:
	if not started or finished or player == null or not player.alive or player.vamp:
		return
	place(build_tile(player), type, player)


func build_tile(a: Actor) -> Vector2i:
	var first: Vector2i = tile_of(a.pos + a.face * 46.0)
	for dist in [46.0, 70.0, 94.0]:
		var t: Vector2i = tile_of(a.pos + a.face * float(dist))
		if can_build(t, a):
			return t
	return first


func can_build(t: Vector2i, a: Actor) -> bool:
	if structures.has(t):
		return false
	if t.x < 0 or t.y < 0 or t.x >= MAP_W or t.y >= MAP_H:
		return false
	var c: Vector2 = tile_center(t)
	if c.distance_to(tile_center(cores[a.base])) > BUILD_RADIUS:
		return false
	for o: Actor in actors:
		if o.alive and absf(o.pos.x - c.x) < 34.0 and absf(o.pos.y - c.y) < 34.0:
			return false
	return true


func place(t: Vector2i, type: String, a: Actor) -> bool:
	var cost: int = WALL_COST if type == "wall" else TURRET_COST
	if a.wood < cost or not can_build(t, a):
		return false
	a.wood -= cost
	var hp: float = 120.0 if type == "wall" else 90.0
	structures[t] = {"type": type, "hp": hp, "max": hp, "owner": a.base, "cd": 0.5}
	return true


func demolish(t: Vector2i, a: Actor) -> void:
	structures.erase(t)
	a.wood = mini(99, a.wood + 2)


func human_attack(a: Actor) -> void:
	var hit := false
	for v: Actor in actors:
		if v.alive and v.vamp and v.pos.distance_to(a.pos) < 62.0:
			damage_actor(v, 22.0)
			hit = true
	if hit:
		a.cd = 0.5
		return
	if a.is_player:
		# swinging at your own wall removes it (refund 2 wood)
		var t: Vector2i = tile_of(a.pos + a.face * 36.0)
		if structures.has(t):
			var s: Dictionary = structures[t]
			if s["owner"] == a.base and s["type"] != "core":
				demolish(t, a)
				a.cd = 0.4


# ---------------------------------------------------------------- vampires

func update_vamp(a: Actor, delta: float) -> void:
	if a.is_player:
		player_control(a, delta)
	else:
		ai_vamp(a, delta)
	if is_night:
		a.hp = minf(a.max_hp, a.hp + 2.0 * delta)
	elif a.pos.distance_to(CRYPT) > 110.0:
		damage_actor(a, 3.0 * delta)   # sunlight burns


func vamp_attack(a: Actor) -> bool:
	var best: Actor = null
	var bd := 52.0
	for h: Actor in actors:
		if h.alive and not h.vamp:
			var d: float = h.pos.distance_to(a.pos)
			if d < bd:
				bd = d
				best = h
	if best != null:
		damage_actor(best, 25.0)
		a.hp = minf(a.max_hp, a.hp + 10.0)
		a.cd = 0.7
		return true
	var mult: float = (1.0 + 0.15 * float(night_no - 1)) if is_night else 0.5
	for off in [28.0, 40.0]:
		var t: Vector2i = tile_of(a.pos + a.face * float(off))
		if structures.has(t):
			damage_structure(t, 20.0 * mult)
			a.cd = 0.7
			return true
	return false


func ai_vamp(a: Actor, delta: float) -> void:
	if not is_night:
		var back: Vector2 = CRYPT - a.pos
		if back.length() > 40.0:
			a.face = back.normalized()
			try_move(a, a.face * VAMP_SPEED * 0.5 * delta)
		return
	a.goal_t -= delta
	var tgt: Actor = null
	var bd := 380.0
	for h: Actor in actors:
		if h.alive and not h.vamp:
			var d: float = h.pos.distance_to(a.pos)
			if d < bd:
				bd = d
				tgt = h
	var target: Vector2
	if tgt != null:
		target = tgt.pos
	else:
		if a.goal_t <= 0.0:
			a.base_target = pick_weak_base()
			a.goal_t = 20.0
		target = tile_center(cores[a.base_target])
	var to: Vector2 = target - a.pos
	if to.length() < 4.0:
		return
	var dir: Vector2 = to.normalized()
	a.face = dir
	if a.cd <= 0.0 and vamp_attack(a):
		return
	var before: Vector2 = a.pos
	try_move(a, dir * VAMP_SPEED * delta)
	if a.pos.distance_to(before) < VAMP_SPEED * delta * 0.3 and a.cd <= 0.0:
		for f: Vector2 in [Vector2(signf(dir.x), 0.0), Vector2(0.0, signf(dir.y))]:
			a.face = f
			if vamp_attack(a):
				break
		a.face = dir


func pick_weak_base() -> int:
	var scores: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for k: Vector2i in structures.keys():
		var s: Dictionary = structures[k]
		if s["type"] == "wall":
			scores[int(s["owner"])] = float(scores[int(s["owner"])]) + 1.0
		elif s["type"] == "turret":
			scores[int(s["owner"])] = float(scores[int(s["owner"])]) + 3.0
	var best := 0
	var best_score := 1e9
	for i in 6:
		var owner_alive := false
		for h: Actor in actors:
			if h.base == i and not h.vamp and h.alive:
				owner_alive = true
		var sc: float = float(scores[i]) + rng.randf_range(0.0, 6.0)
		if not owner_alive:
			sc += 1000.0
		if sc < best_score:
			best_score = sc
			best = i
	return best


# ---------------------------------------------------------------- shared combat

func nearest_vamp(p: Vector2, r: float) -> Actor:
	var best: Actor = null
	var bd := r
	for v: Actor in actors:
		if v.alive and v.vamp:
			var d: float = v.pos.distance_to(p)
			if d < bd:
				bd = d
				best = v
	return best


func damage_actor(t: Actor, dmg: float) -> void:
	if not t.alive:
		return
	t.hp -= dmg
	if t.hp <= 0.0:
		t.hp = 0.0
		t.alive = false
		if t.vamp:
			t.respawn = 10.0


func damage_structure(t: Vector2i, dmg: float) -> void:
	var s: Dictionary = structures[t]
	s["hp"] = float(s["hp"]) - dmg
	if float(s["hp"]) <= 0.0:
		structures.erase(t)


# ---------------------------------------------------------------- bots (humans)

func nearest_tree(p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var bd := 1e9
	for t: Dictionary in trees:
		if int(t["wood"]) >= 2:
			var tp: Vector2 = t["pos"]
			var d: float = tp.distance_to(p)
			if d < bd:
				bd = d
				best = t
	return best


func next_build(a: Actor) -> Dictionary:
	var ct: Vector2i = cores[a.base]
	for off: Vector2i in ring_offsets:
		if not structures.has(ct + off):
			return {"tile": ct + off, "type": "wall"}
	for off: Vector2i in TURRET_OFFSETS:
		if not structures.has(ct + off):
			return {"tile": ct + off, "type": "turret"}
	return {}


func nav_point(a: Actor, dest: Vector2, ct: Vector2i) -> Vector2:
	var bt: Vector2i = tile_of(a.pos)
	var dx: int = bt.x - ct.x
	var dy: int = bt.y - ct.y
	var in_ring: bool = absi(dx) <= 2 and absi(dy) <= 2
	var dt: Vector2i = tile_of(dest)
	var dest_in: bool = absi(dt.x - ct.x) <= 2 and absi(dt.y - ct.y) <= 2
	var door_out: Vector2 = tile_center(ct + Vector2i(0, 3))
	if in_ring and not dest_in:
		return door_out
	if (not in_ring) and dest_in:
		if dy >= 3:
			if absf(a.pos.x - door_out.x) < 10.0:
				return dest
			return door_out
		if absi(dx) <= 3:
			var side: int = 4 if dx >= 0 else -4
			return tile_center(Vector2i(ct.x + side, bt.y))
		var side2: int = 4 if dx > 0 else -4
		return tile_center(Vector2i(ct.x + side2, ct.y + 3))
	return dest


func ai_move(a: Actor, target: Vector2, delta: float) -> void:
	var d: Vector2 = target - a.pos
	if d.length() < 4.0:
		return
	a.face = d.normalized()
	try_move(a, a.face * HUMAN_SPEED * delta)
	a.stuck_t += delta
	if a.stuck_t > 0.7:
		if a.pos.distance_to(a.last_pos) < 5.0:
			a.wander_t = 0.6
			a.wander_dir = Vector2.from_angle(rng.randf() * TAU)
		a.last_pos = a.pos
		a.stuck_t = 0.0


func ai_human(a: Actor, delta: float) -> void:
	var ct: Vector2i = cores[a.base]
	var home: Vector2 = tile_center(ct + Vector2i(0, 1))
	var door: Vector2i = ct + Vector2i(0, 2)
	var bt: Vector2i = tile_of(a.pos)
	var inside: bool = absi(bt.x - ct.x) <= 2 and absi(bt.y - ct.y) <= 2
	var dusk: bool = is_night or (DAY_LEN - phase_t) < 8.0
	var threat: Actor = nearest_vamp(a.pos, 70.0)
	if threat != null and inside:
		a.face = (threat.pos - a.pos).normalized()
		if a.cd <= 0.0:
			human_attack(a)
		return
	if a.wander_t > 0.0:
		a.wander_t -= delta
		try_move(a, a.wander_dir * HUMAN_SPEED * delta)
		return
	var dest: Vector2 = home
	if dusk:
		# go home and close the door
		if inside and a.pos.distance_to(home) < 20.0:
			if not structures.has(door) and a.cd <= 0.0:
				if place(door, "wall", a):
					a.cd = 0.3
			return
	else:
		if inside and structures.has(door) and a.pos.distance_to(home) < 30.0 and a.cd <= 0.0:
			var ds: Dictionary = structures[door]
			if ds["owner"] == a.base:
				demolish(door, a)
				a.cd = 0.3
		var plan: Dictionary = next_build(a)
		var cost := 0
		if not plan.is_empty():
			cost = (WALL_COST + 4) if plan["type"] == "wall" else TURRET_COST
		if plan.is_empty():
			a.mode = "idle"
		elif a.mode == "idle":
			a.mode = "gather"
		if a.mode == "build":
			if a.wood < cost:
				a.mode = "gather"
		elif a.mode == "gather" and a.wood >= maxi(cost, 24):
			a.mode = "build"
		if a.mode == "build":
			dest = home
			if a.pos.distance_to(home) < 24.0:
				if a.cd <= 0.0:
					place(plan["tile"], plan["type"], a)
					a.cd = 0.3
				return
		elif a.mode == "gather":
			var tree: Dictionary = nearest_tree(a.pos)
			if not tree.is_empty():
				dest = tree["pos"]
	ai_move(a, nav_point(a, dest, ct), delta)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, WORLD), Color(0.2, 0.36, 0.18))
	for x in range(0, MAP_W + 1):
		draw_line(Vector2(x * TILE, 0), Vector2(x * TILE, WORLD.y), Color(0, 0, 0, 0.06), 1.0)
	for y in range(0, MAP_H + 1):
		draw_line(Vector2(0, y * TILE), Vector2(WORLD.x, y * TILE), Color(0, 0, 0, 0.06), 1.0)
	for i in cores.size():
		var bc: Color = BASE_COLORS[i]
		draw_arc(tile_center(cores[i]), BUILD_RADIUS, 0.0, TAU, 64, Color(bc, 0.35), 2.0)
	draw_circle(CRYPT, 100.0, Color(0.14, 0.07, 0.2))
	draw_arc(CRYPT, 100.0, 0.0, TAU, 48, Color(0.6, 0.2, 0.7), 3.0)
	draw_string(font, CRYPT + Vector2(-60, 6), "CRYPT", HORIZONTAL_ALIGNMENT_CENTER, 120, 22, Color(0.8, 0.5, 0.9))
	# trees
	for t: Dictionary in trees:
		var tp: Vector2 = t["pos"]
		var w: int = int(t["wood"])
		draw_rect(Rect2(tp + Vector2(-4, 0), Vector2(8, 14)), Color(0.4, 0.26, 0.12))
		if w > 0:
			draw_circle(tp + Vector2(0, -6), 8.0 + float(w) * 0.8, Color(0.1, 0.45, 0.15))
	# structures
	for k: Vector2i in structures.keys():
		var s: Dictionary = structures[k]
		var r := Rect2(Vector2(k) * TILE + Vector2(1, 1), Vector2(TILE - 2, TILE - 2))
		var oc: Color = BASE_COLORS[int(s["owner"])]
		var type: String = s["type"]
		if type == "wall":
			draw_rect(r, Color(0.5, 0.35, 0.2))
			draw_rect(r, oc, false, 2.0)
		elif type == "turret":
			draw_rect(r, Color(0.35, 0.35, 0.4))
			draw_circle(r.get_center(), 11.0, Color(0.6, 0.6, 0.65))
			draw_circle(r.get_center(), 5.0, oc)
		else:
			draw_rect(r, Color(0.85, 0.7, 0.3))
			draw_rect(r, oc, false, 4.0)
		var frac: float = float(s["hp"]) / float(s["max"])
		if frac < 0.999:
			draw_rect(Rect2(r.position + Vector2(2, -5), Vector2(TILE - 6, 4)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(r.position + Vector2(2, -5), Vector2((TILE - 6) * frac, 4)), Color(0.9, 0.2, 0.2))
	# build preview
	if started and player != null and player.alive and not player.vamp and not finished:
		var gt: Vector2i = build_tile(player)
		var ok := can_build(gt, player)
		draw_rect(Rect2(Vector2(gt) * TILE, Vector2(TILE, TILE)), Color(0.3, 1, 0.3, 0.3) if ok else Color(1, 0.3, 0.3, 0.3))
	# actors
	for a: Actor in actors:
		if not a.alive:
			continue
		var col: Color = Color(0.6, 0.05, 0.12) if a.vamp else BASE_COLORS[a.base]
		draw_circle(a.pos + Vector2(3, 5), 14.0, Color(0, 0, 0, 0.25))
		draw_circle(a.pos, 14.0, col)
		draw_circle(a.pos + a.face * 7.0, 5.0, Color(1, 0.95, 0.95))
		if a.vamp:
			var side := a.face.orthogonal() * 4.0
			var tip: Vector2 = a.pos + a.face * 22.0
			draw_line(a.pos + a.face * 14.0 + side, tip + side, Color.WHITE, 2.0)
			draw_line(a.pos + a.face * 14.0 - side, tip - side, Color.WHITE, 2.0)
		if a.hp < a.max_hp - 0.5:
			draw_rect(Rect2(a.pos + Vector2(-16, -24), Vector2(32, 4)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(a.pos + Vector2(-16, -24), Vector2(32.0 * a.hp / a.max_hp, 4)), Color(0.2, 0.9, 0.2))
		if a.is_player:
			draw_arc(a.pos, 20.0, 0.0, TAU, 24, Color.WHITE, 2.0)
			draw_string(font, a.pos + Vector2(-30, -30), "YOU", HORIZONTAL_ALIGNMENT_CENTER, 60, 16, Color.WHITE)
	for e: Dictionary in effects:
		draw_line(e["a"], e["b"], Color(1, 0.9, 0.4), 3.0)
