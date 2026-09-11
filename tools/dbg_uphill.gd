extends Node3D
## Разбор жалобы 11.09 «на трассе с перепадами высот, на подъёме машина
## немного уходит под текстуру»: ведём машину ИИ по травяной трассе и на
## подножии/подъёме горки (доля круга 0.10…0.20) печатаем покадрово —
## прожатие подвески по колёсам, клиренс днища над полотном, утопание низа
## визуального колеса, вертикальную скорость и тангаж.

var _main: Node3D
var _frame := 0
var _laps := 0
var _prev_t := 0.0
var _printed := 0


func _ready() -> void:
	seed(777)
	GameState.track_kind = TrackBuilder.KIND_GRASS
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 5:
		var car: Car = _main._car
		car.is_player = false
		car.weapon = -1
		for i in range(1, _main._cars.size()):
			var extra: Car = _main._cars[i]
			extra.controls_enabled = false
			extra.alive = false
			extra.weapon = -1
			extra.global_transform = Transform3D(Basis.IDENTITY,
					Vector3(120.0 + i * 6.0, 2.0, 120.0))
			extra.linear_velocity = Vector3.ZERO
	if _frame < 60:
		return
	var car: Car = _main._car
	var curve: Curve3D = _main._track._curve
	var length := curve.get_baked_length()
	var t := curve.get_closest_offset(car.global_position) / length
	if t < _prev_t - 0.5:
		_laps += 1
	_prev_t = t
	if t < 0.10 or t > 0.21:
		return
	var space := get_world_3d().direct_space_state
	var comps := PackedStringArray()
	var worst_comp := 0.0
	for point: Vector3 in Car.WHEEL_POINTS:
		var start: Vector3 = car.global_transform * point
		var q := PhysicsRayQueryParameters3D.create(start,
				start + (-car.global_transform.basis.y) * car.suspension_rest)
		q.collision_mask = 1
		q.exclude = [car.get_rid()]
		var hit := space.intersect_ray(q)
		var comp := 0.0
		if not hit.is_empty():
			comp = 1.0 - start.distance_to(hit["position"]) / car.suspension_rest
		worst_comp = maxf(worst_comp, comp)
		comps.append("%.2f" % comp)
	# Клиренс днища (нижняя кромка корпуса на -0.12 в осях машины).
	var belly: Vector3 = car.global_transform * Vector3(0.0, -0.12, 0.0)
	var bq := PhysicsRayQueryParameters3D.create(belly + Vector3.UP * 2.0,
			belly + Vector3.DOWN * 3.0)
	bq.collision_mask = 1
	bq.exclude = [car.get_rid()]
	var bhit := space.intersect_ray(bq)
	var clearance := 99.0
	if not bhit.is_empty():
		clearance = belly.y - (bhit["position"] as Vector3).y
	var touching := false
	for body in car.get_colliding_bodies():
		if body is StaticBody3D and not body.is_in_group("walls"):
			touching = true
			break
	# Утопание низа визуального колеса.
	var car_rids: Array[RID] = []
	for node in get_tree().get_nodes_in_group("cars"):
		car_rids.append((node as Car).get_rid())
	var pen := 0.0
	for pivot: Node3D in car._wheel_pivots:
		var hub: Vector3 = pivot.global_position
		var radius: float = pivot.get_meta("wheel_radius")
		var q2 := PhysicsRayQueryParameters3D.create(
				hub + Vector3.UP * 2.0, hub + Vector3.DOWN * 3.0)
		q2.collision_mask = 1
		q2.exclude = car_rids
		var h2 := space.intersect_ray(q2)
		if h2.is_empty():
			continue
		pen = maxf(pen, (h2["position"] as Vector3).y - (hub.y - radius))
	var pitch := rad_to_deg(car.global_transform.basis.z.y)
	# Утопание КАРТИНКИ кузова: низ модели (base_y = −0.35 от её начала)
	# против полотна под машиной.
	var body_pen := 0.0
	var model: Node3D = car._model
	if model != null and is_instance_valid(model) and not bhit.is_empty():
		body_pen = (bhit["position"] as Vector3).y \
				- (model.global_position.y - 0.35)
	print(("круг %d t=%.3f v=%4.1f comp=[%s] клиренс=%+.3f%s кол.утоп=%.3f "
			+ "кузов.утоп=%+.3f подъём=%.3f vy=%+.1f тангаж=%+.0f")
			% [_laps, t, car.linear_velocity.length(), ", ".join(comps),
			clearance, " КАСАНИЕ" if touching else "", pen, body_pen,
			car._body_lift, car.linear_velocity.y, pitch])
	_printed += 1
	if _laps >= 3 and t > 0.20:
		print("--- конец разбора, строк %d" % _printed)
		get_tree().quit(0)
