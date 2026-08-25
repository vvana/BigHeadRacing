class_name TrackDecor
extends Node3D
## Декор трассы из готовых лоуполи-ассетов (BEDRILL Track Environment Free +
## Cartoon Tracks Pack): финишная арка, стартовая ферма с огнями, трибуны,
## деревья, воздушные шары, реклама и знаки перед поворотами.
## ТОЛЬКО ВИЗУАЛ: ни у одного пропса нет коллизий, всё стоит за ограждением
## (или в воздухе/на полотне без физики) — геймплей не задет.

const DIR := "res://assets/models/track_env/"
const CDIR := DIR + "cartoon/"
const TEX_DIR := CDIR + "textures/"

# Мультяшные FBX ссылаются на .psd-текстуры, которые Godot не читает, —
# назначаем PNG-версии вручную по имени материала внутри FBX.
const CARTOON_TEX := {
	"baloon": "baloon.png",
	"banners": "banners.png",
	"garages": "garages.png",
	"trees": "trees.png",
	"tyres": "tyres.png",
	"barriers": "barriers.png",
}

const TREES: Array[String] = [
	"prop_tree_A.FBX", "prop_tree_B.FBX", "prop_tree_C.FBX",
	"prop_tree_D.FBX", "prop_tree_E.FBX",
]
const BALOONS: Array[String] = [
	"prop_baloon_A.FBX", "prop_baloon_C.FBX",
	"prop_baloon_E.FBX", "prop_baloon_G.FBX",
]

var _track: TrackBuilder
var _mats := {}          # имя материала -> StandardMaterial3D (общие)
var _scenes := {}        # путь -> PackedScene
# Занятые круги (x, z, радиус) — чтобы деревья не прорастали сквозь трибуны.
var _occupied: Array[Vector3] = []


func build(track: TrackBuilder) -> void:
	_track = track
	name = "Decor"
	track.add_child(self)
	_build_start_area()
	_build_tribunes()
	_build_balloons()
	_build_roadside()
	_build_turn_signs()
	_build_road_marks()
	# В пустыне (песчаная трасса) деревья не растут.
	if track.kind != TrackBuilder.KIND_SAND:
		_build_trees()


## ---------- размещение ----------

## Стартовая зона: арка с клетчатым баннером над трассой, ферма стартовых
## огней, башня комментаторов, тент-паддок и таблички команд.
func _build_start_area() -> void:
	var pos := _axis(0.0)
	var fwd := _forward(0.0)
	var out := _outward(0.0)

	# Арка BEDRILL: пролёт 15.2 м, надо накрыть дорогу с ограждениями (~20.8).
	_spawn(DIR + "Arch_for_banner_free.fbx", pos, fwd, 1.38, true)
	# Клетчатый финишный баннер — в проём арки.
	_spawn(DIR + "Arch_banner_finish_free.fbx",
			pos + Vector3(0, 4.4 * 1.38, 0), fwd, 1.95, true)

	# Ферма стартовых огней (мультяшная): столб за правым ограждением,
	# консоль с тремя светодиодными панелями нависает над полотном.
	# У модели консоль уходит в +Z от столба — разворачиваем её К трассе.
	var gantry_pos := _axis_at_dist(-9.0) + out * (_half(0.0) + 2.0)
	gantry_pos.y = _ground_y(gantry_pos)
	_spawn(CDIR + "prop_startlights.FBX", gantry_pos, -out, 1.0, false)

	# Башня комментаторов и тент-паддок — снаружи стартовой прямой.
	var tower_pos := _axis_at_dist(18.0) + out * (_half(0.0) + 14.0)
	tower_pos.y = _ground_y(tower_pos)
	_spawn(CDIR + "prop_tower.FBX", tower_pos, -out, 0.55, false)
	_occupy(tower_pos, 7.0)

	var tent_pos := _axis_at_dist(32.0) + out * (_half(0.0) + 10.0)
	tent_pos.y = _ground_y(tent_pos)
	_spawn(CDIR + "prop_tent.FBX", tent_pos, -out, 1.0, false)
	_occupy(tent_pos, 6.0)

	# Таблички команд вдоль стартовой прямой.
	for i in 4:
		var p := _axis_at_dist(-16.0 - 6.0 * i) + out * (_half(0.0) + 1.6)
		p.y = _ground_y(p)
		_spawn(CDIR + "prop_team_%d.FBX" % (i + 1), p, -out, 1.0, false)


## Трибуны на внешней стороне, «лицом» (сиденьями) к трассе. У модели
## BEDRILL зрители смотрят в +Z, у мультяшных — в -Z (флаг flip).
## После установки трибуна отодвигается так, чтобы её ближайшая точка
## была не ближе 1.5 м к ограждению (см. _push_outside).
func _build_tribunes() -> void:
	for item: Array in [
		[0.06, DIR + "Tribune_free.fbx", 1.0, 10.0, true, false],
		[0.55, DIR + "Tribune_free.fbx", 1.0, 10.0, true, false],
		[0.75, CDIR + "prop_seats_big.FBX", 0.62, 9.0, false, true],
	]:
		var t: float = item[0]
		var pos := _axis(t)
		var out := _outward(t)
		var p := pos + out * (_half(t) + float(item[3]))
		p.y = _ground_y(p)
		var facing := out if bool(item[5]) else -out
		var node := _spawn(String(item[1]), p, facing, float(item[2]),
				bool(item[4]))
		if node:
			_push_outside(node, out,
					_half(t) + TrackBuilder.WALL_THICKNESS + 1.5)
			_occupy(node.position, 10.0)


## Воздушные шары — крупный фон, парят снаружи трассы.
func _build_balloons() -> void:
	var i := 0
	for t: float in [0.12, 0.32, 0.5, 0.68, 0.9]:
		var pos := _axis(t)
		var out := _outward(t)
		var p := pos + out * (28.0 + 8.0 * (i % 3))
		p.y = _ground_y(p) + 17.0 + 4.0 * (i % 3)
		_spawn(CDIR + BALOONS[i % BALOONS.size()], p, out, 0.45, false)
		i += 1


## Мелочь вдоль обочин: флаги, конусы, шины, реклама, фонари — с шагом
## по кругу, чередуя стороны и виды. Всё за ограждением.
func _build_roadside() -> void:
	var length: float = _track._curve.get_baked_length()
	var kinds: Array = [
		[DIR + "Flag_free.fbx", 1.0, true],
		[CDIR + "prop_tyre_4x1_A.FBX", 1.0, false],
		[DIR + "Cone_free.fbx", 1.0, true],
		[CDIR + "prop_adbox_A.FBX", 1.4, false],
		[DIR + "Tire_free.fbx", 1.0, true],
		[CDIR + "prop_adbox_B.FBX", 1.4, false],
		[DIR + "Pole_light_free.fbx", 0.8, true],
		[CDIR + "prop_adbox_C.FBX", 1.4, false],
	]
	var step := 21.0
	var n := int(length / step)
	for i in n:
		var d := step * (i + 0.5)
		# Стартовую прямую не захламляем — там своя застройка.
		if d < 40.0 or d > length - 30.0:
			continue
		var t := d / length
		var pos := _axis(t)
		var side := _outward(t) if i % 2 == 0 else -_outward(t)
		var p := pos + side * (_half(t) + 1.7)
		p.y = _ground_y(p)
		var kind: Array = kinds[i % kinds.size()]
		_spawn(String(kind[0]), p, -side, float(kind[1]), bool(kind[2]))


## Пики кривизны контура — самые крутые повороты. Возвращает массив
## пар [индекс сэмпла, знаковый угол] (угол > 0 — поворот влево).
func _turn_peaks(max_count: int, min_abs: float) -> Array:
	var pts: PackedVector3Array = _track._pts
	var n := pts.size()
	var length: float = _track._curve.get_baked_length()
	var w := 6  # окно оценки кривизны, сэмплов в каждую сторону
	var angles := PackedFloat32Array()
	angles.resize(n)
	for i in n:
		var v1 := pts[i] - pts[(i - w + n) % n]
		var v2 := pts[(i + w) % n] - pts[i]
		v1.y = 0.0
		v2.y = 0.0
		if v1.length_squared() < 1e-6 or v2.length_squared() < 1e-6:
			angles[i] = 0.0
		else:
			angles[i] = v1.signed_angle_to(v2, Vector3.UP)

	# Пики с минимальным разносом 35 м, не ближе 25 м к старту.
	var picked: Array = []
	var order := range(n)
	order.sort_custom(func(a: int, b: int) -> bool:
		return absf(angles[a]) > absf(angles[b]))
	var min_gap := int(35.0 / (length / n))
	for i: int in order:
		if absf(angles[i]) < min_abs or picked.size() >= max_count:
			break
		var d := length * i / n
		if d < 25.0 or d > length - 25.0:
			continue
		var ok := true
		for pair: Array in picked:
			var j: int = pair[0]
			if mini(absi(i - j), n - absi(i - j)) < min_gap:
				ok = false
				break
		if ok:
			picked.append([i, angles[i]])
	return picked


## Щиты-указатели перед крутыми поворотами: на внешней стороне поворота
## за 12 м до вершины.
func _build_turn_signs() -> void:
	var n := _track._pts.size()
	var length: float = _track._curve.get_baked_length()
	for pair: Array in _turn_peaks(5, 0.30):
		var i: int = pair[0]
		var t := float(i) / n - 12.0 / length  # за 12 м до вершины
		var pos := _axis(t)
		# Внешняя сторона поворота: поворот влево (угол > 0) — знак справа.
		var right := _right(t)
		var side := right if pair[1] > 0.0 else -right
		var p := pos + side * (_half(t) + 1.6)
		p.y = _ground_y(p)
		_spawn(DIR + "Sign_free.fbx", p, -_forward(t), 1.2, true)


## Разметка на полотне: стартовая решётка под машинами, белые стрелки
## перед поворотами (целятся в вершину — «куда ехать») и пунктирная
## осевая линия. Всё плоское, без коллизий.
func _build_road_marks() -> void:
	var length: float = _track._curve.get_baked_length()
	var n := _track._pts.size()

	# Скобы стартовой решётки — под слотами машин из Main._spawn_cars
	# (2 колонны по ±2.2 м, ряды на -2 и -7 м от линии).
	var fwd0 := _forward(0.0)
	var right0 := _right(0.0)
	for slot in 4:
		var row := slot / 2
		var col := slot % 2
		var p := _axis_at_dist(-2.0 - row * 5.0) \
				+ right0 * (2.2 if col == 1 else -2.2)
		p.y += 0.08
		_spawn(CDIR + "prop_gridline.FBX", p, fwd0, 1.0, false)

	# Стрелки: за 18 м до вершины поворота, нацелены на вершину.
	for pair: Array in _turn_peaks(5, 0.30):
		var i: int = pair[0]
		var t := float(i) / n - 18.0 / length
		var p := _axis(t)
		p.y += 0.08
		var aim: Vector3 = _axis(float(i) / n) - p
		_spawn(DIR + "Arrow_02_free.fbx", p, aim, 1.3, true)

	# Пунктирная осевая: штрих 2.4 м каждые 8 м, наклонён по профилю
	# трассы. Возле старта не рисуем — там шахматная лента и решётка.
	var dash_mesh := BoxMesh.new()
	dash_mesh.size = Vector3(0.2, 0.02, 2.4)
	var dash_mat := StandardMaterial3D.new()
	dash_mat.albedo_color = Color(0.9, 0.9, 0.88)
	dash_mesh.material = dash_mat
	var d := 12.0
	while d < length - 12.0:
		var pos := _axis_at_dist(d)
		var ahead := _axis_at_dist(d + 1.6)
		var dash := MeshInstance3D.new()
		dash.mesh = dash_mesh
		add_child(dash)
		dash.position = pos + Vector3(0, 0.075, 0)
		dash.look_at(ahead + Vector3(0, 0.075, 0))
		d += 8.0


## Деревья: случайная россыпь по холмам вокруг трассы (с фиксированным
## зерном — трасса всегда одинаковая).
func _build_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260819
	var half := TrackBuilder.GROUND_SIZE * 0.47
	var edge := TrackBuilder.TRACK_HALF_WIDTH + TrackBuilder.SHOULDER
	var placed := 0
	var attempts := 0
	while placed < 90 and attempts < 600:
		attempts += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var p := Vector3(x, 0, z)
		var d: float = _track.distance_from_axis(p)
		if d < edge + 7.0:
			continue
		if _is_occupied(p, 4.0):
			continue
		p.y = _track._ground_height(x, z)
		var yaw_dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		if yaw_dir.length_squared() < 0.01:
			yaw_dir = Vector3.FORWARD
		var scale := rng.randf_range(0.8, 1.35)
		_spawn(CDIR + TREES[rng.randi() % TREES.size()], p, yaw_dir, scale, false)
		placed += 1


## ---------- утилиты ----------

func _axis(t: float) -> Vector3:
	var length: float = _track._curve.get_baked_length()
	return _track._curve.sample_baked(fposmod(t, 1.0) * length)


## Точка оси на расстоянии d метров от старта (d может быть < 0).
func _axis_at_dist(d: float) -> Vector3:
	var length: float = _track._curve.get_baked_length()
	return _track._curve.sample_baked(fposmod(d, length))


func _forward(t: float) -> Vector3:
	var length: float = _track._curve.get_baked_length()
	var off := fposmod(t, 1.0) * length
	var dir: Vector3 = _track._curve.sample_baked(fposmod(off + 0.5, length)) \
			- _track._curve.sample_baked(off)
	dir.y = 0.0
	return dir.normalized()


func _right(t: float) -> Vector3:
	return _forward(t).cross(Vector3.UP) * -1.0


## Наружу от полотна. Раньше бралось просто направление от начала координат
## — это верно только для почти круглой трассы; на контуре с шиканами и
## шпилькой (см. TrackBuilder.SEGMENTS) декор так уезжал ВНУТРЬ кольца.
## Теперь пробуем обе стороны: наружу та, где дальше до полотна (с другой
## стороны рядом соседний виток). Если обе свободны — от центра контура.
func _outward(t: float) -> Vector3:
	var pos := _axis(t)
	var right := _right(t)
	const PROBE := 26.0
	var d_right := _track.distance_from_axis(pos + right * PROBE)
	var d_left := _track.distance_from_axis(pos - right * PROBE)
	if absf(d_right - d_left) > 2.0:
		return right if d_right > d_left else -right
	var o := Vector3(pos.x, 0, pos.z)
	if o.length_squared() < 1.0:
		return right
	return right if right.dot(o.normalized()) >= 0.0 else -right


## Полуширина полотна на доле круга t (полотно переменной ширины).
func _half(t: float) -> float:
	return _track.half_width_at_ratio(t)


func _ground_y(p: Vector3) -> float:
	return _track._ground_height(p.x, p.z)


## Отодвигает пропс наружу, если хоть один угол его габарита ближе
## min_dist к оси трассы (страховка от залезания на полотно/ограждение).
func _push_outside(node: Node3D, out: Vector3, min_dist: float) -> void:
	var closest := INF
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var ab := mi.global_transform * mi.mesh.get_aabb()
		for k in 8:
			closest = minf(closest,
					_track.distance_from_axis(ab.get_endpoint(k)))
	if closest < min_dist:
		node.position += out * (min_dist - closest)


func _occupy(p: Vector3, radius: float) -> void:
	_occupied.append(Vector3(p.x, p.z, radius))


func _is_occupied(p: Vector3, extra: float) -> bool:
	for c in _occupied:
		if Vector2(p.x - c.x, p.z - c.y).length() < c.z + extra:
			return true
	return false


## Ставит пропс: pos — точка на земле (низ модели), facing — куда смотреть
## «лицом» (+Z модели), recenter — нормализовать запечённое смещение
## (модели BEDRILL сдвинуты, как лежали в их демо-сцене).
func _spawn(
	path: String, pos: Vector3, facing: Vector3, scale := 1.0, recenter := false
) -> Node3D:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var scene: PackedScene = _scenes[path]
	if scene == null:
		push_warning("TrackDecor: не загрузился %s" % path)
		return null
	var node := scene.instantiate() as Node3D
	if recenter:
		_recenter(node)
	_apply_cartoon_materials(node)
	add_child(node)
	node.scale = Vector3.ONE * scale
	node.position = pos
	var f := Vector3(facing.x, 0, facing.z)
	if f.length_squared() > 1e-6:
		node.rotation.y = atan2(f.x, f.z)
	return node


## Сдвигает содержимое так, чтобы низ модели встал в начало координат
## по y, а центр габарита — в ноль по x/z.
static func _recenter(root: Node3D) -> void:
	var merged := AABB()
	var first := true
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var ab := mi.transform * mi.mesh.get_aabb()
		merged = ab if first else merged.merge(ab)
		first = false
	if first:
		return
	var c := merged.get_center()
	var shift := Vector3(c.x, merged.position.y, c.z)
	for child in root.get_children():
		if child is Node3D:
			(child as Node3D).position -= shift


## Мультяшным мешам назначает текстуры по имени материала; светодиодам
## стартовых огней — красную эмиссию.
func _apply_cartoon_materials(root: Node3D) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src == null:
				continue
			var mat_name := src.resource_name
			if CARTOON_TEX.has(mat_name) or mat_name == "startlights":
				mi.set_surface_override_material(s, _material(mat_name))


func _material(mat_name: String) -> StandardMaterial3D:
	if _mats.has(mat_name):
		return _mats[mat_name]
	var mat := StandardMaterial3D.new()
	if mat_name == "startlights":
		mat.albedo_color = Color(0.6, 0.05, 0.05)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.1, 0.1)
		mat.emission_energy_multiplier = 1.6
	else:
		mat.albedo_texture = load(TEX_DIR + CARTOON_TEX[mat_name])
	_mats[mat_name] = mat
	return mat
