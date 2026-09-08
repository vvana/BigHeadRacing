extends Node3D
## «Еду прямо вдоль ЗАГНУТОГО борта — в момент отрыва машину дёргает
## в сторону борта» (жалоба 08.09).
##
## Манёвр воспроизводит именно её: машина идёт по ДУГЕ, прижатая к
## ВНЕШНЕМУ ограждению (центробежная сила прижимает сама — руль не
## трогаем, только газ), и на выходе из дуги в прямую борт уходит вбок —
## машина отделяется. Меряем:
##   * рывок — модуль изменения горизонтальной скорости за кадр (м/с²;
##     шины дают до ~20, депенетрация и капы ведения — сотни);
##   * «прилипание» — кадры, когда нос уже смотрит от стены, а машина
##     всё ещё идёт вдоль грани.
## PASS: рывков выше JERK_MAX нет.

const RUN_FRAMES := 110         # ~1.8 с: дуга + выход на прямую
const LEAD_IN := 30.0           # за сколько метров до конца дуги пускаем
const JERK_MAX := 40.0          # м/с²

var _main: Node3D
var _frame := 0
var _phase := 0
var _side := Vector3.ZERO       # от оси к «своему» борту в точке пуска
var _prev_v := Vector3.ZERO
var _worst := 0.0
var _worst_frame := 0
var _stuck := 0
var _starts: Array[float] = []
var _dbg := false


func _ready() -> void:
	_dbg = OS.get_cmdline_user_args().has("--dbg")
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	_starts = _pick_arc_exits()


## Точки в 30 м перед началом прямых: там дуга кончается, и прижатая к
## внешнему борту машина от него отделяется.
func _pick_arc_exits() -> Array[float]:
	var track: TrackBuilder = _main._track
	var length: float = track._curve.get_baked_length()
	var out: Array[float] = []
	for s: Vector2 in track._straights:
		if (s.y - s.x) * length < 60.0:
			continue
		out.append(fposmod(s.x * length - LEAD_IN, length))
		if out.size() >= 2:
			break
	return out


## Кривизна со знаком (>0 — трасса поворачивает влево).
func _curvature(off: float) -> float:
	var curve: Curve3D = _main._track._curve
	var length := curve.get_baked_length()
	var a := curve.sample_baked(fposmod(off - 5.0, length))
	var b := curve.sample_baked(off)
	var c := curve.sample_baked(fposmod(off + 5.0, length))
	var d1 := b - a
	var d2 := c - b
	d1.y = 0.0
	d2.y = 0.0
	return d1.normalized().signed_angle_to(d2.normalized(), Vector3.UP)


func _launch(off: float) -> void:
	var car: Car = _main._car
	var curve: Curve3D = _main._track._curve
	var pos := curve.sample_baked(off)
	var tangent := curve.sample_baked(off + 1.0) - pos
	tangent.y = 0.0
	tangent = tangent.normalized()
	# Внешний борт дуги — противоположный стороне поворота.
	var left := Vector3.UP.cross(tangent).normalized()
	_side = left * (-1.0 if _curvature(off) > 0.0 else 1.0)
	var face: float = _main._track.half_width_at_offset(off) \
			- TrackBuilder.WALL_THICKNESS * 0.5 - 0.9
	car.global_transform = Transform3D(Basis.looking_at(tangent),
			pos + _side * face + Vector3.UP * 0.62)
	car.linear_velocity = tangent * 24.0
	car.angular_velocity = Vector3.ZERO
	car.reset_speed_memory()
	# Без этого пристенок мерил бы расстояние до ЧУЖОЙ точки оси: после
	# телепорта track_offset ведётся по непрерывности и остаётся на старом
	# месте (у стенда это была немая «стена не работает»).
	car.reset_track_offset()
	car.controls_enabled = true
	_prev_v = Vector3.ZERO
	Input.action_press("accelerate")


func _physics_process(delta: float) -> void:
	_frame += 1
	var car: Car = _main._car
	if _frame == 5:
		for i in range(1, _main._cars.size()):
			var extra: Car = _main._cars[i]
			extra.controls_enabled = false
			extra.alive = false
			extra.weapon = -1
			extra.global_transform = Transform3D(Basis.IDENTITY,
					Vector3(160.0 + i * 6.0, 2.0, 160.0))
			extra.linear_velocity = Vector3.ZERO
		return
	if _frame < 30:
		return
	var local := _frame - 30 - _phase * (RUN_FRAMES + 10)
	if local == 0:
		_launch(_starts[_phase])
		return
	if local < 0 or local > RUN_FRAMES:
		return
	var curve: Curve3D = _main._track._curve
	var off := curve.get_closest_offset(car.global_position)
	var axis := curve.sample_baked(off)
	var n := car.global_position - axis
	n.y = 0.0
	var dist := n.length()
	if dist < 0.01:
		return
	n /= dist
	var v := car.linear_velocity
	v.y = 0.0
	var fwd := -car.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	car.controls_enabled = true
	var face: float = _main._track.half_width_at_offset(off)
	var acc := 0.0
	if _prev_v != Vector3.ZERO:
		acc = (v - _prev_v).length() / delta
	# Считаем только пока машина у своего борта (не уехала через полотно).
	var at_wall := (car.global_position - axis).dot(_side) > 0.0 \
			and dist > face - 4.0
	if _dbg:
		print("[f%d p%d] край %.2f нос·n %.2f рывок %.0f near %s учтён %s off %.1f/%.1f dy %.2f v %.1f упр %s"
				% [local, _phase, face - dist, fwd.dot(n), acc,
				str(car._wall_near), str(at_wall), off, car.track_offset,
				car.global_position.y - axis.y, v.length(),
				str(car.controls_enabled)])
	if local > 8 and at_wall:
		if acc > _worst:
			_worst = acc
			_worst_frame = local
		if fwd.dot(n) < -0.05 and v.dot(n) > -0.5:
			_stuck += 1
	_prev_v = v
	if local == RUN_FRAMES:
		Input.action_release("accelerate")
		_phase += 1
		if _phase >= _starts.size():
			print("WALLLEAVE: худший рывок %.1f м/с² (кадр %d), прилипших кадров %d"
					% [_worst, _worst_frame, _stuck])
			print("WALLLEAVE: %s (лимит %.0f м/с²)"
					% ["PASS" if _worst <= JERK_MAX else "FAIL", JERK_MAX])
			get_tree().quit(0 if _worst <= JERK_MAX else 1)
