extends Node3D
## ДИАГНОСТИКА: «еду вдоль ограждения — тяжело вывернуть от него».
## Три одинаковых манёвра: машина ставится параллельно трассе на 20 м/с
## и держит газ + руль ПРОЧЬ от ограждения 1.5 с.
##   A — вплотную к правому борту
##   B — вплотную к левому борту
##   C — в середине полотна (контроль, стены рядом нет)
## Меряем, на сколько метров машина ушла в сторону руля за 1.5 с.
## Если A/B заметно хуже C — виновато ведение у стены.

const START_T := 0.06           # доля круга — место пуска
const RUN_FRAMES := 90          # 1.5 с манёвра

var _main: Node3D
var _frame := 0
var _phase := 0
var _side := Vector3.ZERO       # нормаль «к стене» в момент пуска
var _start_dist := 0.0
var _lat := 0.0                 # смещение в сторону руля, м
var _lat_mid := 0.0             # то же на полпути (0.75 с) — «не прилипла ли»
var _results: Array[float] = []
var _mids: Array[float] = []
var _names := ["A: правый борт", "B: левый борт", "C: середина (контроль)"]


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _launch(offset_from_axis: float, wall_side: Vector3) -> void:
	var car: Car = _main._car
	var curve: Curve3D = _main._track._curve
	var off := curve.get_baked_length() * START_T
	var pos := curve.sample_baked(off)
	var tangent := curve.sample_baked(off + 1.0) - pos
	tangent.y = 0.0
	tangent = tangent.normalized()
	_side = wall_side
	car.global_transform = Transform3D(
		Basis.looking_at(tangent), pos + _side * offset_from_axis + Vector3.UP * 0.62)
	car.linear_velocity = tangent * 20.0
	car.angular_velocity = Vector3.ZERO
	car.reset_speed_memory()
	_start_dist = _main._track.distance_from_axis(car.global_position)
	_lat = 0.0
	# Руль ПРОЧЬ от стены: away >= 0 → рысканье положительное (влево).
	var away := -signf((-car.global_transform.basis.z)
			.signed_angle_to(_side, Vector3.UP))
	Input.action_press("accelerate")
	Input.action_press("steer_left" if away >= 0.0 else "steer_right")


func _release() -> void:
	Input.action_release("accelerate")
	Input.action_release("steer_left")
	Input.action_release("steer_right")


func _telemetry(t: int) -> void:
	var car: Car = _main._car
	var curve: Curve3D = _main._track._curve
	var off := curve.get_closest_offset(car.global_position)
	var axis_pos := curve.sample_baked(off)
	var n := car.global_position - axis_pos
	n.y = 0.0
	var dist := n.length()
	n = n.normalized()
	var h := car.linear_velocity
	h.y = 0.0
	var tangent := curve.sample_baked(
			fposmod(off + 0.5, curve.get_baked_length())) - axis_pos
	tangent.y = 0.0
	var fwd := -car.global_transform.basis.z
	fwd.y = 0.0
	print("    t=%2d  до оси %.2f  v_out %+.2f  курс %+5.1f°  |v| %.1f  стена=%s  align %.2f" % [
		t, dist, h.dot(n),
		rad_to_deg(tangent.normalized().signed_angle_to(fwd.normalized(), Vector3.UP)),
		h.length(), car._touching_wall(), car._wall_align_time])


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame < 160:
		return
	var car: Car = _main._car
	var local := _frame - 160 - _phase * (RUN_FRAMES + 20)
	if local == 0:
		var curve: Curve3D = _main._track._curve
		var off := curve.get_baked_length() * START_T
		var tangent := curve.sample_baked(off + 1.0) - curve.sample_baked(off)
		tangent.y = 0.0
		var right := tangent.normalized().cross(Vector3.UP).normalized()
		match _phase:
			0: _launch(7.8, right)
			1: _launch(7.8, -right)
			2: _launch(0.5, right)
		print("--- %s ---" % _names[_phase])
	elif local > 0 and local <= RUN_FRAMES:
		# Смещение в сторону руля = уменьшение расстояния до оси со стороны
		# стены (для контроля — то же самое относительно стартовой нормали).
		var track: TrackBuilder = _main._track
		var d: Vector3 = car.global_position - track._curve.sample_baked(
				track._curve.get_closest_offset(car.global_position))
		d.y = 0.0
		_lat = _start_dist - d.dot(_side)
		if local == RUN_FRAMES / 2:
			_lat_mid = _lat
		if local % 15 == 0:
			_telemetry(local)
	elif local == RUN_FRAMES + 1:
		_release()
		_results.append(_lat)
		_mids.append(_lat_mid)
		print("  ушла от стены: %.2f м за 0.75 с, %.2f м за 1.5 с" % [_lat_mid, _lat])
		_phase += 1
		if _phase == 3:
			print("ИТОГ (за 0.75 с): правый борт %.2f м, левый борт %.2f м, контроль %.2f м" % [
				_mids[0], _mids[1], _mids[2]])
			# «Прилипание»: до фикса у левого борта за 0.75 с руления от стены
			# машина уходила всего на 0.16 м. Требуем ≥ 1.5 м у ОБОИХ бортов.
			var ok := _mids[0] >= 1.5 and _mids[1] >= 1.5
			print("WALLTURN TEST: %s (за 0.75 с руления от стены надо уйти ≥ 1.5 м)"
					% ("PASS" if ok else "FAIL"))
			get_tree().quit(0 if ok else 1)
