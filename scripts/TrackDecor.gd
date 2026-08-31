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
	set_process(false)   # _process нужен только кометам космоса
	# КОСМОС: никаких земных строений (просьба 31.08) — ни стартовой зоны
	# с аркой и башней, ни трибун, ни обочинных пропсов, ни щитов у
	# поворотов. Остаются разметка на полотне (решётка, стрелки, осевая)
	# и космический фон: планеты, астероиды и пролетающие кометы. Старт
	# и так виден по шахматной ленте (TrackBuilder._build_start_line).
	if track.kind == TrackBuilder.KIND_SPACE:
		_build_road_marks()
		_build_space()
		return
	_build_start_area()
	_build_tribunes()
	# Ночью воздушных шаров не бывает — в городе вместо них здания.
	if track.kind != TrackBuilder.KIND_NEON:
		_build_balloons()
	_build_roadside()
	_build_turn_signs()
	_build_road_marks()
	# Деревья — только на классике: в пустыне не растут, в городе — здания.
	if track.kind == TrackBuilder.KIND_GRASS:
		_build_trees()
	if track.kind == TrackBuilder.KIND_NEON:
		_build_city()


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
	# Окно оценки кривизны — В МЕТРАХ (≈5.7 м в каждую сторону), а не в
	# сэмплах: плотность сэмплов менялась (768 → 1536 на круг), и окно в
	# сэмплах сжалось бы вдвое — углы пиков упали бы ниже порога min_abs,
	# щиты и стрелки перед поворотами пропали бы.
	var w := maxi(1, roundi(5.7 * n / length))
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
	if _track.kind == TrackBuilder.KIND_NEON \
			or _track.kind == TrackBuilder.KIND_SPACE:
		# В темноте осевая светится холодным белым — светоотражающая краска.
		dash_mat.emission_enabled = true
		dash_mat.emission = Color(0.75, 0.85, 1.0)
		dash_mat.emission_energy_multiplier = 0.9
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


## Палитра неоновых вывесок ночного города.
const NEON_COLORS: Array[Color] = [
	Color(1.0, 0.2, 0.85),   # маджента
	Color(0.15, 0.9, 1.0),   # голубой
	Color(1.0, 0.85, 0.2),   # жёлтый
	Color(0.3, 1.0, 0.45),   # зелёный
	Color(1.0, 0.45, 0.15),  # оранжевый
]


## Ночной город: небоскрёбы-коробки со светящимися окнами вокруг трассы
## и неоновые вывески на фасадах. Окна — общая эмиссивная текстура с
## ТРИПЛАНАРНОЙ проекцией ПО МИРУ: одна и та же сетка окон ложится на
## фасады коробки любого размера без UV-развёртки (масштаб узла не
## растягивает окна — проекция мировая).
## Высота зданий ограничена расстоянием до трассы (h ≤ 0.5·d): камера
## смотрит под -32° (tan ≈ 0.62), и дом у самой трассы, окажись он между
## камерой и машиной, закрыл бы обзор. С капом ближние дома низкие,
## дальние — башни: силуэт города растёт к горизонту.
func _build_city() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260825
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.06, 0.07, 0.11)
	wall_mat.emission_enabled = true
	# ВАЖНО: emission-цвет ЧЁРНЫЙ. Оператор эмиссии по умолчанию — ADD
	# (цвет + текстура): с белым цветом светился бы весь дом целиком,
	# а не окна из текстуры.
	wall_mat.emission = Color(0, 0, 0)
	wall_mat.emission_energy_multiplier = 1.5
	wall_mat.emission_texture = _window_texture(rng)
	wall_mat.uv1_triplanar = true
	wall_mat.uv1_world_triplanar = true
	# Тайл текстуры (8 окон) ≈ 18 м → окно ~2.2 м.
	wall_mat.uv1_scale = Vector3.ONE * (1.0 / 18.0)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = wall_mat
	# Крыша: трипланарная проекция кладёт окна и на ВЕРХНЮЮ грань коробки,
	# а камера смотрит сверху (-32°) — окна на крышах бросались в глаза.
	# Тёмная плита чуть шире дома прикрывает их и заодно рисует карниз.
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.045, 0.05, 0.08)
	var roof_box := BoxMesh.new()
	roof_box.size = Vector3.ONE
	roof_box.material = roof_mat

	var half := TrackBuilder.GROUND_SIZE * 0.47
	var edge := TrackBuilder.TRACK_HALF_WIDTH + TrackBuilder.SHOULDER
	var placed := 0
	var attempts := 0
	while placed < 70 and attempts < 800:
		attempts += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		var p := Vector3(x, 0, z)
		var d: float = _track.distance_from_axis(p)
		if d < edge + 9.0:
			continue
		if _is_occupied(p, 8.0):
			continue
		var w := rng.randf_range(7.0, 16.0)
		var depth := rng.randf_range(7.0, 16.0)
		var hgt := minf(rng.randf_range(9.0, 36.0), d * 0.5)
		var b := MeshInstance3D.new()
		b.mesh = box
		b.scale = Vector3(w, hgt, depth)
		b.position = Vector3(x, _ground_y(p) + hgt * 0.5 - 0.2, z)
		# Городская сетка: дома стоят почти по осям, с лёгким разбросом.
		b.rotation.y = rng.randi_range(0, 3) * PI * 0.5 \
				+ rng.randf_range(-0.06, 0.06)
		add_child(b)
		var roof := MeshInstance3D.new()
		roof.mesh = roof_box
		roof.scale = Vector3(w + 0.6, 0.5, depth + 0.6)
		roof.position = b.position + Vector3(0, hgt * 0.5 + 0.15, 0)
		roof.rotation.y = b.rotation.y
		add_child(roof)
		_occupy(b.position, maxf(w, depth) * 0.75)
		placed += 1
		# Вывеска — на фасаде к трассе, у части домов.
		if rng.randf() < 0.55:
			_add_neon_sign(b.position, w, depth, hgt, rng)


## Сетка окон для эмиссивной текстуры зданий: 8×8 окон на тайл, часть
## горит тёплым/холодным светом разной яркости, остальное темно.
func _window_texture(rng: RandomNumberGenerator) -> ImageTexture:
	const CELL := 16      # пикселей на окно (тайл 128×128 → 8×8 окон)
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	img.fill(Color(0, 0, 0))
	for wy in 8:
		for wx in 8:
			if rng.randf() > 0.38:
				continue   # тёмное окно
			var c := Color(1.0, 0.82, 0.45) if rng.randf() < 0.7 \
					else Color(0.55, 0.8, 1.0)
			c *= rng.randf_range(0.45, 1.0)
			# Само окно — с полями внутри клетки (стены между окнами).
			for py in range(CELL * wy + 4, CELL * wy + 12):
				for px in range(CELL * wx + 3, CELL * wx + 13):
					img.set_pixel(px, py, c)
	return ImageTexture.create_from_image(img)


## Неоновая вывеска: светящаяся горизонтальная плашка на фасаде здания,
## обращённом к трассе.
func _add_neon_sign(
	center: Vector3, w: float, depth: float, hgt: float,
	rng: RandomNumberGenerator
) -> void:
	var to_track: Vector3 = _track._curve.get_closest_point(center) - center
	to_track.y = 0.0
	if to_track.length_squared() < 1.0:
		return
	to_track = to_track.normalized()
	var sign_mesh := BoxMesh.new()
	sign_mesh.size = Vector3(
			rng.randf_range(3.0, minf(8.0, w * 0.8)), 1.1, 0.2)
	var mat := StandardMaterial3D.new()
	var c: Color = NEON_COLORS[rng.randi() % NEON_COLORS.size()]
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 2.4
	sign_mesh.material = mat
	var sign_node := MeshInstance3D.new()
	sign_node.mesh = sign_mesh
	add_child(sign_node)
	# Чуть перед фасадом (полудиагональ покрывает любой поворот дома).
	var off := maxf(w, depth) * 0.5 + 0.3
	sign_node.position = center + to_track * off \
			+ Vector3(0, rng.randf_range(-hgt * 0.25, hgt * 0.3), 0)
	sign_node.rotation.y = atan2(-to_track.x, -to_track.z)


## Палитра планет космической трассы.
const PLANET_COLORS: Array[Color] = [
	Color(0.85, 0.45, 0.25),   # рыжий гигант
	Color(0.35, 0.55, 0.95),   # голубая
	Color(0.8, 0.7, 0.5),      # песочная
	Color(0.55, 0.85, 0.7),    # бирюзовая
	Color(0.75, 0.4, 0.75),    # лиловая
]


## Космос: планеты и астероиды вокруг трассы. ВСЕ планеты — в дальнем
## фоне, кольцом вокруг контура (жалоба 31.08: «планеты должны быть на
## заднем фоне, а не перед трассой» — прежние ближние «спутники» в
## 30-44 м от полотна висели прямо перед камерой). Только визуал, без
## коллизий.
func _build_space() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260902
	# Дальние планеты — по кругу вокруг трассы, высоко.
	for k in 5:
		var ang := TAU * k / 5.0 + rng.randf_range(-0.25, 0.25)
		var dist := rng.randf_range(150.0, 195.0)
		var pos := Vector3(cos(ang) * dist, rng.randf_range(35.0, 90.0),
				sin(ang) * dist)
		_spawn_planet(pos, rng.randf_range(12.0, 26.0), PLANET_COLORS[k],
				k == 1, rng)   # одной из планет — кольца
	# «Сатурн» — тоже в дальнем фоне, но КРУПНЫЙ и с двойным кольцом
	# (просьба 31.08: планета с кольцом должна быть на виду). Размер
	# вместо близости: читается с любой точки трассы, полотно не заслоняет.
	_spawn_planet(Vector3(cos(0.9) * 165.0, 62.0, sin(0.9) * 165.0),
			20.0, Color(0.88, 0.74, 0.48), true, rng)
	# Кометы прилетают периодически (см. _process).
	_comet_rng.seed = 20260903
	set_process(true)
	# Астероиды: серые глыбы, парят невысоко над «пустотой».
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.42, 0.4, 0.48)
	rock_mat.roughness = 1.0
	var half := TrackBuilder.GROUND_SIZE * 0.47
	var edge := TrackBuilder.TRACK_HALF_WIDTH + TrackBuilder.SHOULDER
	var placed := 0
	var attempts := 0
	while placed < 16 and attempts < 300:
		attempts += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if _track.distance_from_axis(Vector3(x, 0, z)) < edge + 10.0:
			continue
		var rock := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 7   # гранёная «глыба», а не гладкий шар
		s.rings = 4
		rock.mesh = s
		rock.material_override = rock_mat
		rock.scale = Vector3(rng.randf_range(1.2, 3.4),
				rng.randf_range(1.0, 2.6), rng.randf_range(1.2, 3.4))
		rock.rotation_degrees = Vector3(rng.randf_range(0, 360),
				rng.randf_range(0, 360), rng.randf_range(0, 360))
		add_child(rock)
		rock.position = Vector3(x, rng.randf_range(3.0, 12.0), z)
		placed += 1


## ---- Кометы (только космос): далёкий белый росчерк, периодически
## проносящийся по небу СБОКУ от мира (жалоба 31.08: «кометы должны быть
## вдалеке в виде пролетающей белой полосы» — раньше летели прямо над
## трассой крупным болидом).
const COMET_MAX := 3          # больше одновременно не держим
const COMET_FIRST := 1.5      # первая — почти сразу после старта, с
const COMET_DIST := 260.0     # хорда пролёта: ближе к центру мира не заходит
const COMET_RUN := 220.0      # плечо пролёта в каждую сторону от хорды, м
var _comets: Array[Dictionary] = []
var _comet_timer := COMET_FIRST
var _comet_rng := RandomNumberGenerator.new()


func _process(delta: float) -> void:
	_comet_timer -= delta
	if _comet_timer <= 0.0:
		_comet_timer = _comet_rng.randf_range(5.0, 11.0)
		if _comets.size() < COMET_MAX:
			_spawn_comet()
	var i := _comets.size() - 1
	while i >= 0:
		var c: Dictionary = _comets[i]
		var node: Node3D = c["node"]
		node.position += c["vel"] * delta
		c["life"] -= delta
		if c["life"] <= 0.0:
			node.queue_free()
			_comets.remove_at(i)
		i -= 1


## Комета проносится ВДАЛИ: по прямой, чья ближайшая к центру мира точка —
## на COMET_DIST (за планетным кольцом, к трассе не приближается). Курс —
## касательная к этому кругу, чуть со снижением: «падающая звезда».
func _spawn_comet() -> void:
	var ang := _comet_rng.randf_range(0.0, TAU)
	var base := Vector3(cos(ang) * COMET_DIST,
			_comet_rng.randf_range(70.0, 130.0), sin(ang) * COMET_DIST)
	# Касательное направление (по или против часовой — случайно).
	var dir := Vector3(-sin(ang), 0.0, cos(ang))
	if _comet_rng.randf() < 0.5:
		dir = -dir
	dir.y = _comet_rng.randf_range(-0.25, -0.05)   # лёгкое снижение
	dir = dir.normalized()
	var start := base - dir * COMET_RUN
	var vel := dir * _comet_rng.randf_range(70.0, 110.0)
	var node := _make_comet()
	node.name = "Comet"
	add_child(node)
	node.position = start
	node.look_at(start + vel)   # -Z по ходу, хвост построен в +Z
	# Жизни хватает пролететь плечо в обе стороны и «растаять» там.
	_comets.append({
		"node": node, "vel": vel,
		"life": COMET_RUN * 2.0 / vel.length(),
	})


## Комета: БЕЛАЯ ПОЛОСА — маленькая яркая голова и длинный тонкий
## хвост-росчерк назад (+Z), сужающийся в точку. С дистанции ~260 м
## читается именно как пролетающая белая чёрточка. UNSHADED — светится
## в темноте.
func _make_comet() -> Node3D:
	var root := Node3D.new()
	var head := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.6
	s.height = 3.2
	head.mesh = s
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_color = Color(1.0, 1.0, 1.0)
	hm.emission_enabled = true
	hm.emission = Color(1.0, 1.0, 1.0)
	hm.emission_energy_multiplier = 2.6
	head.material_override = hm
	root.add_child(head)

	var tail := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 1.3    # тонкий у головы (с 260+ м — нитка)...
	cone.bottom_radius = 0.0 # ...в точку позади — росчерк движения
	cone.height = 60.0       # длинный: полоса, а не болид
	tail.mesh = cone
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.albedo_color = Color(1.0, 1.0, 1.0, 0.5)
	tm.emission_enabled = true
	tm.emission = Color(0.95, 0.97, 1.0)
	tail.material_override = tm
	# Поворот -90° вокруг X кладёт ось цилиндра (+Y) на -Z: широкий конец
	# к голове, остриё назад по +Z.
	tail.rotation_degrees.x = -90.0
	tail.position.z = 30.0
	root.add_child(tail)
	return root


## Планета: светящийся изнутри шар (иначе в темноте не видна), по желанию —
## плоские кольца в тон.
func _spawn_planet(pos: Vector3, radius: float, col: Color, ringed: bool,
		rng: RandomNumberGenerator) -> void:
	var planet := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	planet.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col * 0.45
	mat.roughness = 1.0
	planet.material_override = mat
	add_child(planet)
	planet.position = pos
	planet.rotation_degrees = Vector3(rng.randf_range(-15, 15),
			rng.randf_range(0, 360), rng.randf_range(-10, 10))
	if ringed:
		# Двойное кольцо «как у Сатурна»: широкая яркая полоса + узкая
		# потемнее с просветом (одиночный тор читался как обруч, а не диск).
		for cfg: Array in [[1.25, 1.85, 0.45], [1.95, 2.3, 0.15]]:
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = radius * float(cfg[0])
			torus.outer_radius = radius * float(cfg[1])
			ring.mesh = torus
			ring.scale.y = 0.03   # плоский диск
			var rcol := col.lightened(float(cfg[2]))
			var rmat := StandardMaterial3D.new()
			rmat.albedo_color = rcol
			rmat.emission_enabled = true
			rmat.emission = rcol * 0.45
			ring.material_override = rmat
			ring.name = "PlanetRing"
			planet.add_child(ring)
			ring.rotation_degrees = Vector3(20, 0, 10)


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
