extends Node3D
## Диагностика: машина на ИИ едет 90 с, печатаем всплески вертикальной
## скорости на «ровных» местах (плато профиля, вдали от трамплинов).

var _main: Node3D
var _frame := 0
var _prev_vy := 0.0
var _body_contacts := 0  # кадры, когда КУЗОВ (не колёса) касается дороги
var _kicks := 0          # резкая смена угла курса (> 2.5°/кадр на ровном)
var _prev_h := Vector3.ZERO

# Плато из TrackBuilder.HEIGHT_KEYS (доли круга) с отступом от переходов.
const FLAT_ZONES: Array = [
	[0.01, 0.13], [0.26, 0.40], [0.49, 0.60], [0.72, 0.82], [0.92, 0.99],
]
const RAMPS: Array = [0.44, 0.875]


func _ready() -> void:
	seed(777)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 5:
		var car: Car = _main._car
		car.is_player = false  # ехать на ИИ
		# Соперники не должны мешать: глушим и увозим в угол карты.
		for i in range(1, _main._cars.size()):
			var extra: Car = _main._cars[i]
			extra.controls_enabled = false
			# alive=false: иначе автовозврат вернёт соперника на трассу.
			extra.alive = false
			extra.ammo = 0
			extra.mines = 0
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
	var flat := false
	for z: Array in FLAT_ZONES:
		if t >= z[0] and t <= z[1]:
			flat = true
			break
	for r: float in RAMPS:
		if absf(t - r) < 0.03:
			flat = false
	var h := car.linear_velocity
	h.y = 0.0
	if flat and h.length() > 10.0 and _prev_h.length() > 10.0 			and not car._touching_wall() and car._wall_align_time <= 0.0 			and car._ext_push_time <= 0.0:
		var ang := rad_to_deg(h.normalized().angle_to(_prev_h.normalized()))
		if ang > 2.5:
			_kicks += 1
			print("KICK t=%.3f ang=%.1f° v=%.1f" % [t, ang, h.length()])
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
