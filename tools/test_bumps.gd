extends Node3D
## Диагностика: машина на ИИ едет 90 с, печатаем всплески вертикальной
## скорости на «ровных» местах (плато профиля, вдали от трамплинов).

var _main: Node3D
var _frame := 0
var _prev_vy := 0.0
var _body_contacts := 0  # кадры, когда КУЗОВ (не колёса) касается дороги
var _kicks := 0          # резкая смена угла курса (> 2.5°/кадр на ровном)
var _prev_h := Vector3.ZERO

var _ramps: Array = []  # доли круга с трамплинами — берём у самой трассы


func _ready() -> void:
	seed(777)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


## «Ровное место» — профиль высот не меняется в окрестности точки.
## Считается ПО САМОЙ ТРАССЕ, а не по зашитому списку плато: раньше здесь
## лежал массив FLAT_ZONES, скопированный из HEIGHT_KEYS, и любая правка
## профиля молча делала тест бессмысленным (зоны съезжали на склоны).
func _is_level(t: float) -> bool:
	const D := 0.02
	var h := TrackBuilder._profile_height(t)
	return is_equal_approx(h, TrackBuilder._profile_height(t - D)) 			and is_equal_approx(h, TrackBuilder._profile_height(t + D))


## Кривизна оси трассы (рад/м) в точке — сколько трасса поворачивает
## на метр пути. Нужна, чтобы отличить законный доворот по дуге от
## «пинка» (см. порог ниже).
func _axis_curvature(pos: Vector3) -> float:
	var curve: Curve3D = _main._track._curve
	var length: float = curve.get_baked_length()
	var off: float = curve.get_closest_offset(pos)
	const D := 4.0
	var t0: Vector3 = curve.sample_baked(fposmod(off + D, length)) \
			- curve.sample_baked(off)
	var t1: Vector3 = curve.sample_baked(fposmod(off + D * 2.0, length)) \
			- curve.sample_baked(fposmod(off + D, length))
	t0.y = 0.0
	t1.y = 0.0
	if t0.length_squared() < 1e-6 or t1.length_squared() < 1e-6:
		return 0.0
	return t0.normalized().angle_to(t1.normalized()) / D


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 5:
		var car: Car = _main._car
		car.is_player = false  # ехать на ИИ
		car.weapon = -1  # случайный «буст» со старта исказил бы замеры
		# Соперники не должны мешать: глушим и увозим в угол карты.
		for i in range(1, _main._cars.size()):
			var extra: Car = _main._cars[i]
			extra.controls_enabled = false
			# alive=false: иначе автовозврат вернёт соперника на трассу.
			extra.alive = false
			extra.weapon = -1
			extra.global_transform = Transform3D(Basis.IDENTITY,
					Vector3(110.0 + i * 6.0, 2.0, 110.0))
			extra.linear_velocity = Vector3.ZERO
	if _frame < 60:
		return
	var car: Car = _main._car
	var curve: Curve3D = _main._track._curve
	var length := curve.get_baked_length()
	var t := curve.get_closest_offset(car.global_position) / length
	var vy := car.linear_velocity.y
	var flat := _is_level(t)
	if _ramps.is_empty():
		_ramps = _main._track._ramp_ratios()
	# Зона трамплина несимметрична: перед ним 0.01 круга, ПОСЛЕ — 0.10
	# (~70 м), потому что с трамплина на 30 м/с машина улетает метров на
	# 40-60 и приземляется уже далеко за ним; это законный удар о землю,
	# а не «подброс на ровном месте».
	for r: float in _ramps:
		if t > r - 0.01 and t < r + 0.10:
			flat = false
	var h := car.linear_velocity
	h.y = 0.0
	if flat and h.length() > 10.0 and _prev_h.length() > 10.0 			and not car._touching_wall() and car._wall_align_time <= 0.0 			and car._ext_push_time <= 0.0:
		var ang := rad_to_deg(h.normalized().angle_to(_prev_h.normalized()))
		# Порог — НЕ константа: на трассе с крутыми поворотами машина за
		# кадр законно доворачивает на v/R (в шпильке R=19 это ~3°/кадр
		# при 34 м/с), и фиксированные 2.5° ловили бы обычное прохождение
		# дуги. Считаем ЛИШНИЙ доворот сверх поворота самой оси трассы.
		var axis_turn := rad_to_deg(
				h.length() * _d * _axis_curvature(car.global_position))
		if ang > maxf(2.5, axis_turn * 1.6):
			_kicks += 1
			print("KICK t=%.3f ang=%.1f° (ось %.1f°) v=%.1f" % [
				t, ang, axis_turn, h.length()])
	_prev_h = h
	for b in car.get_colliding_bodies():
		if b is StaticBody3D and not b.is_in_group("walls"):
			_body_contacts += 1
			break
	# Резкий скачок vy вверх на плато = подброс.
	if flat and vy > 0.8 and _prev_vy <= 0.8:
		print("BUMP t=%.3f vy=%.2f pos=%s v=%.1f" % [
			t, vy, car.global_position, car.linear_velocity.length()])
	_prev_vy = vy
	if _frame > 60 * 90:
		print("DONE body_contacts=%d kicks=%d" % [_body_contacts, _kicks])
		get_tree().quit(0)
