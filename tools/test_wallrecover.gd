extends Node3D
## Разворот из «застрял носом в отбойнике»: машина СТОИТ вплотную к стене
## носом под 80° к оси (итог перпендикулярного удара — скорость съедена,
## нос в стену), «игрок» жмёт газ и руль от стены. Машина должна встать
## вдоль трассы (угол к оси < 30°) не дольше чем за 2 с. До помощи
## развороту (автодоворот при носе поперёк + нижний порог силы руля на
## малой скорости) руль на нулевой скорости был бессилен, нажатый руль
## отключал штатный доворот вдоль ограждения, и приходилось несколько
## раз разгоняться в стену заново, чтобы развернуться.

const RECOVER_LIMIT := 2.0  # с от начала руления до угла < 30°

var _main: Node3D
var _frame := 0
var _phase := "launch"      # launch -> wait_hit -> steer -> done
var _steer_frame := 0
var _steer_action := ""
var _recover_time := -1.0


func _ready() -> void:
	seed(7)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _tangent_at(pos: Vector3) -> Vector3:
	var curve: Curve3D = _main._track._curve
	var off := curve.get_closest_offset(pos)
	var t: Vector3 = curve.sample_baked(
			fposmod(off + 0.5, curve.get_baked_length())) \
			- curve.sample_baked(off)
	t.y = 0.0
	return t.normalized()


func _track_angle(car: Car) -> float:
	var fwd := -car.global_transform.basis.z
	fwd.y = 0.0
	var tangent := _tangent_at(car.global_position)
	return tangent.signed_angle_to(fwd, Vector3.UP)


func _physics_process(_d: float) -> void:
	_frame += 1
	var car: Car = _main._car
	if _frame == 5:
		for i in range(1, _main._cars.size()):
			var extra: Car = _main._cars[i]
			extra.controls_enabled = false
			extra.alive = false  # и от автовозврата на трассу
			extra.weapon = -1
			extra.global_transform = Transform3D(Basis.IDENTITY,
					Vector3(110.0 + i * 6.0, 2.0, 110.0))
			extra.linear_velocity = Vector3.ZERO
	if _frame < 30:
		return
	match _phase:
		"launch":
			var curve: Curve3D = _main._track._curve
			var off := curve.get_baked_length() * 0.05
			var pos := curve.sample_baked(off)
			var tangent := _tangent_at(pos)
			var side := tangent.cross(Vector3.UP).normalized()
			# Центр у самой стены (вылет носа 1.5 м + зазор), нос под 80°
			# в стену — состояние сразу после перпендикулярного удара.
			# Полотно переменной ширины — грань стены в этой точке.
			# Тип пишем явно: _main объявлен как Node3D, вывод типа для
			# его полей не работает (иначе Parse Error и тест не грузится).
			var wall_face: float = \
					_main._track.half_width_at_offset(off) \
					- TrackBuilder.WALL_THICKNESS * 0.5
			var center: Vector3 = pos + side * (wall_face - 1.7)
			var dir := (tangent * cos(deg_to_rad(80.0))
					+ side * sin(deg_to_rad(80.0))).normalized()
			car.global_transform = Transform3D(
					Basis.looking_at(dir), center + Vector3.UP * 0.62)
			car.linear_velocity = Vector3.ZERO
			car.angular_velocity = Vector3.ZERO
			car.controls_enabled = true
			# Газ + руль от стены (положительное рысканье растит угол к
			# оси — рулим против) нажаты сразу, отсчёт времени — отсюда.
			_steer_action = "steer_right" if _track_angle(car) > 0.0 \
					else "steer_left"
			Input.action_press("accelerate")
			Input.action_press(_steer_action)
			_steer_frame = _frame
			_phase = "steer"
		"steer":
			var t := (_frame - _steer_frame) / 60.0
			var ang := absf(rad_to_deg(_track_angle(car)))
			if ang < 30.0:
				_recover_time = t
				_phase = "done"
			elif t > RECOVER_LIMIT + 1.0:
				_phase = "done"
		"done":
			Input.action_release("accelerate")
			if _steer_action != "":
				Input.action_release(_steer_action)
			var ok := _recover_time >= 0.0 and _recover_time <= RECOVER_LIMIT
			print("WALLRECOVER TEST: %s (разворот за %s, лимит %.1f с)" % [
					"PASS" if ok else "FAIL",
					("%.2f с" % _recover_time) if _recover_time >= 0.0
							else "НЕ РАЗВЕРНУЛАСЬ",
					RECOVER_LIMIT])
			get_tree().quit(0 if ok else 1)
