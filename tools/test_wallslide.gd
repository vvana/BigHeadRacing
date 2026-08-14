extends Node3D
## Автотест ведения вдоль ограждения: машину пускают в стену под ~55°
## на 20 м/с. Стена должна НАПРАВИТЬ её вдоль трассы, не тормозя.
## Фаза 1: после входа в пристенок отскок К ОСИ ни на одном кадре не
## превышает 3 м/с, корпус в конце вдоль трассы (< 30°), а горизонтальная
## скорость в первые полсекунды у стены в диапазоне 12..18.5 м/с:
## стена должна СЛЕГКА притормозить (не в ноль, но и не бесплатно).
## Фаза 2: у стены должен работать «руль от стены» — руление прочь от
## ограждения обязано отвернуть нос.

var _main: Node3D
var _frame := 0
var _side := Vector3.ZERO       # горизонтальная нормаль «к стене» в точке пуска
var _touched := false
var _max_inward := 0.0          # максимальная скорость отскока (от стены к оси)
var _speed_frames := 0
var _min_speed := 999.0         # мин. горизонтальная скорость после входа в пристенок
var _phase1_ok := false
var _steered_away := false      # хоть на одном кадре нос ушёл от стены


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _angle_to_track() -> float:
	var car: Car = _main._car
	var curve: Curve3D = _main._track._curve
	var off := curve.get_closest_offset(car.global_position)
	var tangent := curve.sample_baked(fposmod(off + 0.5, curve.get_baked_length())) \
			- curve.sample_baked(off)
	tangent.y = 0.0
	var fwd := -car.global_transform.basis.z
	fwd.y = 0.0
	return rad_to_deg(tangent.angle_to(fwd))


func _physics_process(_delta: float) -> void:
	_frame += 1
	var car: Car = _main._car
	var track: TrackBuilder = _main._track
	if _frame == 30:
		# Пуск в стену со стартовой прямой: 55° к касательной, 20 м/с.
		var curve: Curve3D = track._curve
		var off := curve.get_baked_length() * 0.05
		var pos := curve.sample_baked(off)
		var tangent := (curve.sample_baked(off + 1.0) - pos)
		tangent.y = 0.0
		tangent = tangent.normalized()
		_side = tangent.cross(Vector3.UP).normalized()
		var dir := (tangent * cos(deg_to_rad(55.0))
				+ _side * sin(deg_to_rad(55.0))).normalized()
		car.global_transform = Transform3D(
			Basis.looking_at(dir), pos + _side * 2.0 + Vector3.UP * 0.62)
		car.linear_velocity = dir * 20.0
		car.angular_velocity = Vector3.ZERO
	elif _frame > 30 and _frame < 170:
		# «Пристенок»: сработало ведение у стены (окно доворота взведено).
		if car._touching_wall() or car._wall_align_time > 0.0:
			_touched = true
		if _touched:
			_max_inward = maxf(_max_inward, -car.linear_velocity.dot(_side))
			if _speed_frames < 30:
				_speed_frames += 1
				var hv := car.linear_velocity
				hv.y = 0.0
				_min_speed = minf(_min_speed, hv.length())
	elif _frame == 170:
		var a := _angle_to_track()
		_phase1_ok = _touched and _max_inward < 3.0 and a < 30.0 \
				and _min_speed > 12.0 and _min_speed < 18.5
		print("фаза 1 (ведение): %s (пристенок=%s, отскок к оси %.2f м/с (лимит 3), угол %.1f° (лимит 30), мин. скорость %.1f м/с (норма 12..18.5))" % [
			"ok" if _phase1_ok else "FAIL", _touched, _max_inward, a, _min_speed])
	elif _frame == 176:
		# Фаза 2: игрок жмёт газ и руль ОТ стены (честно, через Input —
		# положительное рысканье, т.е. влево, это действие steer_left).
		var away := -signf((-car.global_transform.basis.z)
				.signed_angle_to(_wall_normal(), Vector3.UP))
		Input.action_press("accelerate")
		Input.action_press("steer_left" if away >= 0.0 else "steer_right")
	elif _frame > 176 and _frame < 240:
		# Отрулила, если нос ушёл от стены ИЛИ машина покинула пристенок.
		var fwd := -car.global_transform.basis.z
		fwd.y = 0.0
		if fwd.dot(_wall_normal()) < -0.1 \
				or track.distance_from_axis(car.global_position) < 4.0:
			_steered_away = true
	elif _frame == 240:
		Input.action_release("accelerate")
		Input.action_release("steer_left")
		Input.action_release("steer_right")
		print("фаза 2 (руль от стены): %s (нос %s)" % [
			"ok" if _steered_away else "FAIL",
			"ушёл от стены" if _steered_away else "так и уткнут в стену"])
		var ok := _phase1_ok and _steered_away
		print("WALLSLIDE TEST: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)


## Горизонтальная нормаль от оси трассы к стене у текущего положения машины.
func _wall_normal() -> Vector3:
	var car: Car = _main._car
	var curve: Curve3D = _main._track._curve
	var n := car.global_position \
			- curve.sample_baked(curve.get_closest_offset(car.global_position))
	n.y = 0.0
	return n.normalized()
