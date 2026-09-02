class_name CarModelLibrary
extends RefCounted
## Собирает визуальные модели машин.
## Парк (2026-09-02): 15 советских машин (Low Poly Soviet Car Pack, Unity)
## с 10 цветами-скинами каждая + 8 машин Unity «Low Poly Car Vehicle Pack»
## (без скинов). Все — из одиночных FBX (один файл = одна машина).
## Поддержка общих GLB-паков (_build_from) оставлена на случай новых паков.

# Общие GLB-паки. ПУСТ с 2026-09-02: hot-wheels-паки удалены.
const GLB_PATHS: Array[String] = []

# ---- Советский пак: id машины + цвет = отдельный FBX ----
# Файл: SOVIET_DIR/<id>/<id>_<color>.fbx. Цвет сидит в UV (общая
# текстура-палитра albedo.png); материал FBX текстуру НЕ несёт — её
# назначает _soviet_material(). Устройство файла: кузов + 4 узла-колеса
# (*wheel_fl/fr/bl/br) с осью в ступице — колёса оборачиваются в пивоты
# и крутятся (collect_wheels/_animate_wheels в Car.gd). Нос у всех в +Z.
const SOVIET_DIR := "res://assets/models/sovietcars/source"
const SOVIET_COLORS: Array[String] = [
	"black", "blue", "gray", "green", "lightblue",
	"purple", "red", "sand", "white", "yellow",
]
const SOVIET_IDS: Array[String] = [
	"vz01", "vz02", "vz21", "vz03", "vz04", "vz05", "vz06", "vz07",
	"vz05r", "vz08", "vz09", "vz099", "gz21", "gz24", "vz31",
]
## Цвет по умолчанию (пока игрок не выбрал свой) — у всех разный, чтобы
## сетка выбора выглядела пёстро.
const DEFAULT_COLORS := {
	"vz01": "red", "vz02": "lightblue", "vz21": "green", "vz03": "white",
	"vz04": "blue", "vz05": "yellow", "vz06": "sand", "vz07": "purple",
	"vz05r": "red", "vz08": "gray", "vz09": "lightblue", "vz099": "black",
	"gz21": "white", "gz24": "black", "vz31": "green",
}

## Машины из ОДИНОЧНЫХ файлов БЕЗ скинов (Unity «Low Poly Car Vehicle
## Pack»): один файл — одна машина ЦЕЛЬНЫМ мешем, узлов-колёс нет
## (колёса запечены в кузов и не крутятся — collect_wheels это
## переживает). Нос у всех в +Z. Цвета сидят в материалах FBX.
const SINGLE_CAR_PATHS := {
	"fastback": "res://assets/models/unitycars/source/Car-1.fbx",
	"godfather": "res://assets/models/unitycars/source/Car-2.fbx",
	"lemans": "res://assets/models/unitycars/source/Car-3.fbx",
	"superbird": "res://assets/models/unitycars/source/Car-4.fbx",
	"chevelle": "res://assets/models/unitycars/source/Car-5.fbx",
	"diablo": "res://assets/models/unitycars/source/Car-6.fbx",
	"dragster": "res://assets/models/unitycars/source/Car-7.fbx",
	"safari": "res://assets/models/unitycars/source/Car-8.fbx",
}

## БАЗОВЫЕ идентификаторы машин (без цвета) — порядок сетки гаража:
## сперва 3 стартовые, дальше по порядку открытия (GameState.CAR_UNLOCKS).
const CAR_IDS: Array[String] = [
	"vz01", "vz02", "vz21",
	"vz03", "vz04", "vz05", "vz06", "vz07", "vz05r", "vz08", "vz09",
	"vz099", "gz21", "gz24", "vz31",
	"fastback", "safari", "chevelle", "godfather", "lemans", "superbird",
	"dragster", "diablo",
]


# ---- Скины: разбор и сборка id вида "vz01_red" ----

## База полного id: "vz01_red" → "vz01"; id без цвета возвращается как есть.
static func base_id(id: String) -> String:
	var cut := id.rfind("_")
	if cut > 0 and SOVIET_COLORS.has(id.substr(cut + 1)):
		return id.substr(0, cut)
	return id


## Цвет полного id: "vz01_red" → "red"; нет суффикса — цвет по умолчанию.
static func color_of_id(id: String) -> String:
	var cut := id.rfind("_")
	if cut > 0 and SOVIET_COLORS.has(id.substr(cut + 1)):
		return id.substr(cut + 1)
	return default_color(base_id(id))


## Есть ли у машины скины-цвета (советский пак).
static func has_skins(base: String) -> bool:
	return SOVIET_IDS.has(base)


static func default_color(base: String) -> String:
	return DEFAULT_COLORS.get(base, "red")


## Полный id скина: база + цвет ("vz01" + "red" → "vz01_red").
## Для машин без скинов цвет игнорируется.
static func skin_id(base: String, color: String) -> String:
	if not has_skins(base):
		return base
	if not SOVIET_COLORS.has(color):
		color = default_color(base)
	return "%s_%s" % [base, color]


## Пул для ботов: по одному СЛУЧАЙНОМУ цвету на каждую машину, перемешан.
## Боты замков не знают — ездят на чём угодно (так заезд пёстрый, а
## игрок видит будущие покупки вживую). RNG — СВОЙ: глобальный поток
## randf/randi питает детерминированные регрессионные стенды, пул не
## должен его сдвигать (TestWeapons ловил).
static func shuffled_bot_pool() -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out: Array[String] = []
	for base in CAR_IDS:
		out.append(skin_id(base,
				SOVIET_COLORS[rng.randi_range(0, SOVIET_COLORS.size() - 1)]))
	for i in range(out.size() - 1, 0, -1):   # Фишер–Йетс на своём RNG
		var j := rng.randi_range(0, i)
		var tmp := out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


# Кэш РАСПАКОВАННЫХ файлов: путь → корень инстанциированной сцены (вне
# дерева, живёт до конца игры). Инстанциация — сотни узлов и сотни мс;
# без кэша раздача ростера замораживала клиент (см. историю в PROGRESS).
static var _pack_cache: Dictionary = {}

# Общий материал советского пака (текстура-палитра + эмиссия стёкол).
static var _soviet_mat: StandardMaterial3D


static func _pack_src(path: String) -> Node:
	if not _pack_cache.has(path):
		var scene: PackedScene = load(path)
		_pack_cache[path] = scene.instantiate() if scene else null
	return _pack_cache[path]


## FBX советского пака приходит БЕЗ текстуры (в Unity она сидела во
## внешнем .mat): albedo — общая палитра, цвет машины выбирают UV.
## Фильтр NEAREST: на палитре линейная фильтрация тянет соседние цвета.
static func _soviet_material() -> StandardMaterial3D:
	if _soviet_mat == null:
		var m := StandardMaterial3D.new()
		# ВАЖНО: обе текстуры перегоняются в ImageTexture. 2D-импортированная
		# CompressedTexture2D в слоте эмиссии НЕ биндится (шейдер читает
		# чистый белый — все машины заливало серым +0.5; поймано пробой
		# пикселей 02.09).
		var alb: Texture2D = load(
				"res://assets/models/sovietcars/Materials/Textures/albedo.png")
		m.albedo_texture = ImageTexture.create_from_image(alb.get_image())
		# Текстура назначена кодом (импорт «для 2D», линейный) — без
		# force_srgb краски выцветают в пастель (красный → розовый).
		m.albedo_texture_force_srgb = true
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		# Немного блеска (засветку давала эмиссия, не спекуляр — см. ниже),
		# но и не зеркало: узкий блик, краска остаётся насыщенной.
		m.roughness = 0.6
		m.metallic = 0.0
		m.metallic_specular = 0.4
		var em: Texture2D = load(
				"res://assets/models/sovietcars/Materials/Textures/emission.png")
		if em:
			m.emission_enabled = true
			m.emission_texture = ImageTexture.create_from_image(em.get_image())
			# ВАЖНО: оператор эмиссии по умолчанию — ADD (цвет emission
			# ПРИБАВЛЯЕТСЯ к текстуре). Белый тут заливал все машины серым
			# +0.5 (чёрная выглядела светло-серой); базовый цвет — чёрный,
			# светятся только фары/стопы из текстуры.
			m.emission = Color.BLACK
			m.emission_energy_multiplier = 0.5
		_soviet_mat = m
	return _soviet_mat


## Собирает визуал машины car_id: Node3D с деталями, отцентрованный,
## носом вперёд (-Z), длиной target_length метров, низом на base_y.
## car_id может нести цвет ("vz01_red"); без цвета — цвет по умолчанию.
## variant — номер слота для общих GLB-паков (сейчас не используется).
## Вернёт null, если машина не нашлась.
static func build(
	car_id: String,
	target_length := 3.2,
	base_y := -0.35,
	variant := 0
) -> Node3D:
	var t0 := Time.get_ticks_msec()
	var id := car_id.to_lower()
	var base := base_id(id)
	var model: Node3D = null
	if SOVIET_IDS.has(base):
		var path := "%s/%s/%s_%s.fbx" % [
				SOVIET_DIR, base, base, color_of_id(id)]
		model = _build_single(path, id, target_length, base_y,
				_soviet_material())
	elif SINGLE_CAR_PATHS.has(base):
		model = _build_single(
				String(SINGLE_CAR_PATHS[base]), base, target_length, base_y)
	else:
		for path in GLB_PATHS:
			model = _build_from(path, base, target_length, base_y, variant)
			if model:
				break
	if model:
		var dt := Time.get_ticks_msec() - t0
		if dt > 100:
			print("[slow] CarModelLibrary.build('%s') занял %d мс" % [car_id, dt])
		return model
	push_warning("CarModelLibrary: машина '%s' не найдена" % car_id)
	return null


## Машина из одиночного файла: все меши файла целиком — одна машина.
## Узлы с "wheel" в имени оборачиваются в пивоты по центру их AABB
## (ступица) — колёса крутятся и поворачиваются рулём, как у GLB-паков.
## «Перёд» определяется по переднему колесу (wheel_f при z>0 — разворот
## на PI); файлов без колёс (unitycars) это не касается — они смотрят
## в +Z и разворачиваются всегда. material — общий материал-override
## (советский пак), null — материалы файла как есть.
static func _build_single(
	path: String,
	car_id: String,
	target_length: float,
	base_y: float,
	material: Material = null
) -> Node3D:
	var src := _pack_src(path)
	if src == null:
		return null
	var items: Array[Dictionary] = []
	_collect_meshes(src, Transform3D.IDENTITY, items)
	if items.is_empty():
		return null
	var container := Node3D.new()
	container.name = "CarModel_" + car_id
	var combined := AABB()
	var front_z := 0.0
	var has_wheels := false
	var first := true
	for it in items:
		var aabb: AABB = (it["xform"] as Transform3D) \
				* ((it["node"] as MeshInstance3D).mesh as Mesh).get_aabb()
		it["aabb"] = aabb
		combined = aabb if first else combined.merge(aabb)
		first = false
		var n := String((it["node"] as Node).name).to_lower()
		if n.contains("wheel"):
			has_wheels = true
			if n.contains("wheel_f"):
				front_z = aabb.get_center().z
	var s := target_length / combined.size.z
	# Без колёс «перёд» не определить — такие файлы (unitycars) смотрят
	# в +Z; с колёсами решает знак z переднего колеса.
	var flipped := front_z > 0.0 if has_wheels else true

	for it in items:
		var copy: MeshInstance3D = (it["node"] as MeshInstance3D).duplicate()
		var xform: Transform3D = it["xform"]
		if material:
			copy.material_override = material
		if String(copy.name).to_lower().contains("wheel"):
			# Пивот в центре ступицы (AABB колеса): у части моделей
			# геометрия колеса смещена от начала узла (vz05r), поэтому
			# центр берём по мешу, а не по узлу.
			var hub: Vector3 = (it["aabb"] as AABB).get_center()
			var pivot := Node3D.new()
			pivot.name = "WheelPivot_" + copy.name
			pivot.position = hub
			copy.transform = Transform3D(xform.basis, xform.origin - hub)
			pivot.add_child(copy)
			pivot.set_meta("wheel_radius",
					(it["aabb"] as AABB).size.y * 0.5 * s)
			pivot.set_meta("is_front",
					String(copy.name).to_lower().contains("wheel_f"))
			pivot.set_meta("spin_sign", -1.0 if flipped else 1.0)
			container.add_child(pivot)
		else:
			copy.transform = xform
			container.add_child(copy)

	var center := combined.get_center()
	container.scale = Vector3.ONE * s
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


## Обход дерева файла: копит MeshInstance3D с их НАКОПЛЕННЫМ трансформом
## относительно корня (узлы файла могут быть вложены).
static func _collect_meshes(
	node: Node, xform: Transform3D, out: Array[Dictionary]
) -> void:
	var t := xform
	if node is Node3D:
		t = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append({"node": node, "xform": t})
	for child in node.get_children():
		_collect_meshes(child, t, out)


static func _build_from(
	glb_path: String,
	car_id: String,
	target_length: float,
	base_y: float,
	variant: int
) -> Node3D:
	# Пак из кэша (см. _pack_src): src ЖИВЁТ между вызовами, освобождать
	# и модифицировать его нельзя — только читать и duplicate() детали.
	var src := _pack_src(glb_path)
	if src == null:
		return null

	# Слоты, где стоит деталь с именем машины (может быть несколько рядов).
	var needle := "_%s_" % car_id
	var slots: Array[Vector3] = []
	for child in src.get_children():
		if child is MeshInstance3D \
				and String(child.name).to_lower().begins_with(needle) \
				and not slots.has(child.position):
			slots.append(child.position)
	if slots.is_empty():
		return null   # src кэширован — не освобождаем
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
