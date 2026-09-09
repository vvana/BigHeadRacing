extends Node3D
## «Машина едет по изгибу борта сама» на скорости с бустом (жалоба 09.09:
## ведение вдоль изгиба появляется на больших скоростях при ускорении).
## Машина у ВНЕШНЕГО борта перед самым крутым поворотом, 40 м/с, турбина
## III ступени, газ в пол и БЕЗ руля 3 с. Стена не должна везти её по
## дуге даром: PASS, если в повороте ход падает хотя бы до 35 % входного
## (ниже BEND_KEEP) и машину не выкинуло за ограждение. Контроль — та же
## машина по оси прямой (первые 1.5 с ход не должен падать).
## Цифры 09.09: до платного доворота (Car.WALL_TURN_LOSS) минимум был
## 50 % и на выходе из поворота уже 45 м/с — стена честно везла; с ним —
## минимум 22 %, на выходе 32 м/с.
## Запуск: godot --headless --path . res://tools/TestWallBend.tscn

const RUN_FRAMES := 180
const WARMUP := 60
const ENTRY := 40.0
const BEND_KEEP := 0.35

var _main: Node3D
var _frame := 0
var _phase := 0
var _min_v := 999.0
var _end_v := 0.0
var _worst_out := -999.0
var _mins: Array[float] = []
var _names := ["A: внешний борт, крутой поворот, буст III", "C: ось прямой (контроль)"]


func _ready() -> void:
	seed(7)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _sharpest() -> Array:
	var curve: Curve3D = _main._track._curve
	var length := curve.get_baked_length()
	var best_off := 0.0
	var best_k := 0.0
	var best_sign := 1.0
	var off := 0.0
	while off < length:
		var a := curve.sample_baked(off)
		var b := curve.sample_baked(fposmod(off + 4.0, length))
		var c := curve.sample_baked(fposmod(off + 8.0, length))
		var t1 := b - a
		var t2 := c - b
		t1.y = 0.0
		t2.y = 0.0
		if t1.length_squared() > 1e-6 and t2.length_squared() > 1e-6:
			var k := t1.normalized().signed_angle_to(t2.normalized(), Vector3.UP)
			if absf(k) > best_k:
				best_k = absf(k)
				best_off = off
				best_sign = signf(k)
		off += 2.0
	return [best_off, best_sign, best_k]


func _longest_straight_off() -> float:
	var track: TrackBuilder = _main._track
	var best := 0.0
	var best_len := 0.0
	for s: Vector2 in track._straights:
		if s.y - s.x > best_len:
			best_len = s.y - s.x
			best = s.x + 0.004
	return track._curve.get_baked_length() * best


func _launch(off: float, from_axis: float, side_sign: float) -> void:
	var car: Car = _main._car
	var curve: Curve3D = _main._track._curve
	var length := curve.get_baked_length()
	var pos := curve.sample_baked(off)
	var tangent := curve.sample_baked(fposmod(off + 1.0, length)) - pos
	tangent.y = 0.0
	tangent = tangent.normalized()
	var right := tangent.cross(Vector3.UP).normalized()
	car.global_transform = Transform3D(Basis.looking_at(tangent),
			pos + right * side_sign * from_axis + Vector3.UP * 0.62)
	car.linear_velocity = tangent * ENTRY
	car.angular_velocity = Vector3.ZERO
	car.reset_speed_memory()
	var st := PackedByteArray()
	st.resize(Weapons.COUNT)
	st[Weapons.BOOST] = 3
	car.weapon_steps = st
	car.apply_boost()
	_min_v = 999.0
	_end_v = 0.0
	_worst_out = -999.0
	Input.action_press("accelerate")


func _physics_process(_d: float) -> void:
	_frame += 1
	var car: Car = _main._car
	if _frame == 5:
		for i in range(1, _main._cars.size()):
			var extra: Car = _main._cars[i]
			extra.controls_enabled = false
			extra.alive = false
			extra.weapon = -1
			extra.global_transform = Transform3D(Basis.IDENTITY,
					Vector3(110.0 + i * 6.0, 2.0, 110.0))
			extra.linear_velocity = Vector3.ZERO
	if _frame < WARMUP:
		return
	var local := _frame - WARMUP - _phase * (RUN_FRAMES + 30)
	var track: TrackBuilder = _main._track
	if local == 0:
		match _phase:
			0:
				var s := _sharpest()
				var off: float = fposmod(s[0] - 20.0, track._curve.get_baked_length())
				var outer: float = -s[1]
				_launch(off, track.half_width_at_offset(off) - 1.2, outer)
				print("--- %s (кривизна %.1f°/4 м, отметка %.0f м) ---"
						% [_names[0], rad_to_deg(s[2]), s[0]])
			1:
				_launch(_longest_straight_off(), 0.0, 1.0)
				print("--- %s ---" % _names[1])
	elif local > 0 and local <= RUN_FRAMES:
		var h := car.linear_velocity
		h.y = 0.0
		var dist := track.distance_from_axis(car.global_position)
		var off := track._curve.get_closest_offset(car.global_position)
		_worst_out = maxf(_worst_out, dist - track.half_width_at_offset(off))
		# Контроль — только первые 1.5 с: прямой на 3 с при 50 м/с не хватает,
		# дальше машина честно влетает в борт в её конце.
		if _phase == 0 or local <= RUN_FRAMES / 2:
			_min_v = minf(_min_v, h.length())
		_end_v = h.length()
		if local % 20 == 0:
			print("    t=%.2f с  |v| %.1f  до оси %.2f  стена=%s" % [
					local / 60.0, h.length(), dist, car._touching_wall()])
	elif local == RUN_FRAMES + 1:
		Input.action_release("accelerate")
		_mins.append(_min_v)
		print("  %s: вход %.0f м/с, минимум %.1f (%.0f%%), в конце %.1f, вылет за грань %.2f м"
				% [_names[_phase], ENTRY, _min_v, _min_v / ENTRY * 100.0, _end_v, _worst_out])
		if _phase == 0 and _worst_out > 0.5:
			print("WALLBEND TEST: FAIL (машину выкинуло за ограждение)")
			get_tree().quit(1)
		_phase += 1
		if _phase == 2:
			var ok := _mins[0] <= ENTRY * BEND_KEEP and _mins[1] > ENTRY * 0.8
			print("WALLBEND TEST: %s (у борта в повороте минимум %.0f%% входа, лимит %.0f%%; на прямой %.0f%%)"
					% ["PASS" if ok else "FAIL", _mins[0] / ENTRY * 100.0,
					BEND_KEEP * 100.0, _mins[1] / ENTRY * 100.0])
			get_tree().quit(0 if ok else 1)
