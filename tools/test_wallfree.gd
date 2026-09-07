extends Node3D
## «Вдоль борта без руля» (жалоба 04.09: «машина сама следует вдоль изгибов
## трассы рядом с ограждениями, можно даже не рулить»). Два заезда по 4 с
## с одним газом и БЕЗ руля, 22 м/с на старте:
##   A — вплотную к ВНЕШНЕМУ борту перед самым крутым поворотом трассы;
##   C — по оси самой длинной прямой (контроль: стен рядом нет).
## Телеметрия: печатаем среднюю скорость у борта в долях от контрольной
## (04.09 «рельс» давал 69 %, скрежет — 43 %; 07.09 по просьбе игрока ход
## вдоль стены НЕ теряется — снова около 70 %). Единственное условие
## PASS: машину не должно выкинуть за ограждение.

const RUN_FRAMES := 240
const WARMUP := 60

var _main: Node3D
var _frame := 0
var _phase := 0
var _sum := 0.0
var _n := 0
var _min_v := 999.0
var _worst_out := -999.0   # вылет центра за грань ограждения, м
var _results: Array[float] = []
var _names := ["A: внешний борт, крутой поворот", "C: ось прямой (контроль)"]


func _ready() -> void:
	seed(7)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


## Отметка максимальной кривизны оси (м) и знак поворота (+1 — влево).
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
	car.linear_velocity = tangent * 22.0
	car.angular_velocity = Vector3.ZERO
	car.reset_speed_memory()
	_sum = 0.0
	_n = 0
	_min_v = 999.0
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
				var off: float = fposmod(s[0] - 14.0, track._curve.get_baked_length())
				# Внешний борт — со стороны, противоположной повороту.
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
		if local > RUN_FRAMES / 2:
			_sum += h.length()
			_n += 1
			_min_v = minf(_min_v, h.length())
		if local % 30 == 0:
			print("    t=%.1f с  |v| %.1f  до оси %.2f  стена=%s" % [
					local / 60.0, h.length(), dist, car._touching_wall()])
	elif local == RUN_FRAMES + 1:
		Input.action_release("accelerate")
		var avg := _sum / maxf(1.0, float(_n))
		_results.append(avg)
		print("  %s: средняя |v| за последние 2 с %.1f м/с, мин %.1f, вылет за грань %.2f м"
				% [_names[_phase], avg, _min_v, _worst_out])
		if _phase == 0 and _worst_out > 0.5:
			print("WALLFREE TEST: FAIL (машину выкинуло за ограждение)")
			get_tree().quit(1)
		_phase += 1
		if _phase == 2:
			var ratio := _results[0] / maxf(1.0, _results[1])
			print("WALLFREE TEST: PASS (у борта %.0f%% от контрольной скорости; за грань не выкинуло)"
					% (ratio * 100.0))
			get_tree().quit(0)
