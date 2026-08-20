extends Node3D
## Диагностика «колёса проваливаются сквозь дорогу»: машина на ИИ едет 90 с,
## каждый кадр меряем, насколько НИЗ визуального колеса (пивот - радиус)
## оказался ниже полотна под ним. Копим по 100 корзинам вдоль круга:
## максимум утопания, минимальную скорость, кадры контакта кузова с дорогой.

var _main: Node3D
var _frame := 0

const BUCKETS := 100
var _pen_max: Array[float] = []
var _pen_frames: Array[int] = []      # кадров с утопанием > 3 см
var _body_contacts: Array[int] = []   # кадров контакта кузов-дорога
var _speed_min: Array[float] = []
var _comp_max: Array[float] = []      # макс. прожатие подвески (0..1)
var _worst_pen := 0.0
var _worst_t := 0.0


func _ready() -> void:
	seed(777)
	for i in BUCKETS:
		_pen_max.append(0.0)
		_pen_frames.append(0)
		_body_contacts.append(0)
		_speed_min.append(999.0)
		_comp_max.append(0.0)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 5:
		var car: Car = _main._car
		car.is_player = false
		for i in range(1, _main._cars.size()):
			var extra: Car = _main._cars[i]
			extra.controls_enabled = false
			# alive=false: иначе автовозврат Main._check_recovery через
			# секунду вернёт «вылетевшего» соперника с угла карты обратно
			# на трассу, и тест-машина будет его таранить.
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
	var t := curve.get_closest_offset(car.global_position) \
			/ curve.get_baked_length()
	var b := clampi(int(t * BUCKETS), 0, BUCKETS - 1)

	var speed := car.linear_velocity.length()
	_speed_min[b] = minf(_speed_min[b], speed)

	for body in car.get_colliding_bodies():
		if body is StaticBody3D and not body.is_in_group("walls"):
			_body_contacts[b] += 1
			break

	# Прожатие подвески: те же лучи, что в _apply_suspension.
	var space := get_world_3d().direct_space_state
	for point: Vector3 in Car.WHEEL_POINTS:
		var start: Vector3 = car.global_transform * point
		var end: Vector3 = start \
				+ (-car.global_transform.basis.y) * car.suspension_rest
		var q := PhysicsRayQueryParameters3D.create(start, end)
		q.collision_mask = 1
		q.exclude = [car.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var comp: float = 1.0 \
					- start.distance_to(hit["position"]) / car.suspension_rest
			_comp_max[b] = maxf(_comp_max[b], comp)

	# Утопание визуальных колёс: низ колеса (центр пивота - радиус по миру)
	# против полотна строго под ним. Из луча исключаем ВСЕ машины: кузов
	# соперника над дорогой — не «полотно» (ловился как pen 2 м).
	var car_rids: Array[RID] = []
	for node in get_tree().get_nodes_in_group("cars"):
		car_rids.append((node as Car).get_rid())
	var frame_pen := 0.0
	for pivot: Node3D in car._wheel_pivots:
		var hub: Vector3 = pivot.global_position
		var radius: float = pivot.get_meta("wheel_radius")
		var q2 := PhysicsRayQueryParameters3D.create(
				hub + Vector3.UP * 2.0, hub + Vector3.DOWN * 3.0)
		q2.collision_mask = 1
		q2.exclude = car_rids
		var hit2 := space.intersect_ray(q2)
		if hit2.is_empty():
			continue
		var ground_y: float = (hit2["position"] as Vector3).y
		var pen := ground_y - (hub.y - radius)
		frame_pen = maxf(frame_pen, pen)
	_pen_max[b] = maxf(_pen_max[b], frame_pen)
	if frame_pen > 0.03:
		_pen_frames[b] += 1
	if frame_pen > _worst_pen:
		_worst_pen = frame_pen
		_worst_t = t

	if _frame > 60 * 90:
		print("=== WHEEL SINK по корзинам t (только заметные) ===")
		for i in BUCKETS:
			if _pen_max[i] > 0.02 or _body_contacts[i] > 0:
				print("t=%.2f pen_max=%.3f (кадров>3см: %d) comp=%.2f " %
						[float(i) / BUCKETS, _pen_max[i], _pen_frames[i],
						_comp_max[i]]
						+ "body_hits=%d v_min=%.1f" %
						[_body_contacts[i], _speed_min[i]])
		# Критерий: колёса не должны ЗАМЕТНО уходить под полотно.
		# 0.2 м — потолок для единичных кадров жёсткой посадки (факт при
		# фиксе 0.108); на плато утопание держится в пределах 5 см.
		var ok := _worst_pen < 0.2
		print("WHEELSINK TEST: %s (worst pen=%.3f при t=%.3f, лимит 0.2)" % [
				"PASS" if ok else "FAIL", _worst_pen, _worst_t])
		get_tree().quit(0 if ok else 1)
