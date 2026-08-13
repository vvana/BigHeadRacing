class_name CarModelLibrary
extends RefCounted
## Выдёргивает отдельные машинки из общих GLB-паков.
## Устройство паков: все машины лежат сеткой в одном файле, детали одной
## машины стоят в одной точке-слоте (геометрия — в вершинах), колёса
## называются *_wheel_front*/*_wheel_back*. Ориентация и оси у паков
## разные, поэтому:
##  - AABB считаем с учётом поворота узлов (пак HW35 — Z-up);
##  - «перёд» определяем по переднему колесу и при нужде разворачиваем на PI
##    (в Godot «вперёд» — это -Z).

const GLB_PATHS: Array[String] = [
	"res://assets/models/hotwheels/source/Turbo Driver Cars.glb",
	"res://assets/models/highway35/source/HW35 cars.glb",
]

## Идентификаторы машин = подстроки в именах деталей (без учёта регистра).
## Пак Turbo Driver (8 шт., variant 1 = текстуры "TSH"):
##   stock, rd, sharky, invader, arachno, dk, dakar, jt
## Пак Highway 35 (35 шт.):
##   24seven, backdraft, ballistik, corvette, coupe, deora, elcamino, f150,
##   irocfirebird, krazy8s, megaduty, motocrossed, muscletone, nomad,
##   powerocket, powerpipes, powerpistons, rageous, redbaron, roadrocket,
##   roadrunner, sidedraft, silverbullet, slingshot, sweet16, switchback,
##   tbird, thunderbolt, toyotarsc, twinmill, vulture, wildthing, zotic
const CAR_IDS: Array[String] = [
	"stock", "rd", "sharky", "invader", "arachno", "dk", "dakar", "jt",
	"24seven", "backdraft", "ballistik", "corvette", "coupe", "deora",
	"elcamino", "f150", "irocfirebird", "krazy8s", "megaduty", "motocrossed",
	"muscletone", "nomad", "powerocket", "powerpipes", "powerpistons",
	"rageous", "redbaron", "roadrocket", "roadrunner", "sidedraft",
	"silverbullet", "slingshot", "sweet16", "switchback", "tbird",
	"thunderbolt", "toyotarsc", "twinmill", "vulture", "wildthing", "zotic",
]


## Собирает визуал машины car_id: Node3D с деталями, отцентрованный,
## носом вперёд (-Z), длиной target_length метров, низом на base_y.
## variant — номер слота, если машина встречается в паке несколько раз
## (в Turbo Driver каждая есть в двух рядах текстур).
## Вернёт null, если машина не нашлась ни в одном паке.
static func build(
	car_id: String,
	target_length := 3.2,
	base_y := -0.35,
	variant := 0
) -> Node3D:
	for path in GLB_PATHS:
		var model := _build_from(path, car_id.to_lower(), target_length, base_y, variant)
		if model:
			return model
	push_warning("CarModelLibrary: машина '%s' не найдена" % car_id)
	return null


static func _build_from(
	glb_path: String,
	car_id: String,
	target_length: float,
	base_y: float,
	variant: int
) -> Node3D:
	var scene: PackedScene = load(glb_path)
	if scene == null:
		return null
	var src := scene.instantiate()

	# Слоты, где стоит деталь с именем машины (может быть несколько рядов).
	var needle := "_%s_" % car_id
	var slots: Array[Vector3] = []
	for child in src.get_children():
		if child is MeshInstance3D \
				and String(child.name).to_lower().begins_with(needle) \
				and not slots.has(child.position):
			slots.append(child.position)
	if slots.is_empty():
		src.free()
		return null
	slots.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.z > b.z)
	var slot: Vector3 = slots[clampi(variant, 0, slots.size() - 1)]

	# Собираем все детали слота; AABB — с учётом поворота узла (Z-up-паки).
	var container := Node3D.new()
	container.name = "CarModel_" + car_id
	var parts: Array[Dictionary] = []
	var combined := AABB()
	var front_z := 0.0
	var first := true
	for child in src.get_children():
		if child is MeshInstance3D and child.position.distance_to(slot) < 0.01:
			var copy: MeshInstance3D = child.duplicate()
			copy.position = Vector3.ZERO
			var aabb: AABB = copy.transform * copy.mesh.get_aabb()
			combined = aabb if first else combined.merge(aabb)
			first = false
			parts.append({
				"copy": copy,
				"aabb": aabb,
				"is_wheel": String(copy.name).to_lower().contains("wheel"),
			})
			if String(copy.name).to_lower().contains("wheel_front"):
				front_z = aabb.get_center().z
	src.free()

	var s := target_length / combined.size.z
	var flipped := front_z > 0.0  # модель смотрит в +Z — надо развернуть

	# Колёса оборачиваем в пивоты по центру ступицы, чтобы их можно было
	# крутить (spin вокруг X пивота) и поворачивать рулём (вокруг Y).
	for p in parts:
		var copy: MeshInstance3D = p["copy"]
		if p["is_wheel"]:
			var hub: Vector3 = (p["aabb"] as AABB).get_center()
			var pivot := Node3D.new()
			pivot.name = "WheelPivot_" + copy.name
			pivot.position = hub
			copy.position = -hub
			pivot.add_child(copy)
			pivot.set_meta("wheel_radius", (p["aabb"] as AABB).size.y * 0.5 * s)
			pivot.set_meta("is_front",
					String(copy.name).to_lower().contains("front"))
			# При развороте контейнера на PI локальная ось X смотрит
			# в другую сторону — знак вращения колёс меняется.
			pivot.set_meta("spin_sign", -1.0 if flipped else 1.0)
			container.add_child(pivot)
		else:
			container.add_child(copy)

	container.scale = Vector3.ONE * s
	var center := combined.get_center()
	if flipped:
		container.rotation.y = PI
		container.position = Vector3(
			center.x * s,
			base_y - combined.position.y * s,
			center.z * s
		)
	else:
		container.position = Vector3(
			-center.x * s,
			base_y - combined.position.y * s,
			-center.z * s
		)
	return container
