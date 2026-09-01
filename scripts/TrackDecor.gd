class_name TrackDecor
extends Node3D
## Декор трассы из готовых лоуполи-ассетов (BEDRILL Track Environment Free +
## Cartoon Tracks Pack + Palmov Low Poly Locations + ithappy Cartoon City):
## финишная арка, стартовая ферма с огнями, трибуны, деревья, воздушные шары,
## реклама и знаки перед поворотами; в пустыне — пирамиды, сфинкс и кактусы;
## в ночном городе — мультяшные здания со светящимися окнами и светофоры.
## ТОЛЬКО ВИЗУАЛ: ни у одного пропса нет коллизий, всё стоит за ограждением
## (или в воздухе/на полотне без физики) — геймплей не задет.

const DIR := "res://assets/models/track_env/"
const CDIR := DIR + "cartoon/"
const TEX_DIR := CDIR + "textures/"
const PDIR := DIR + "palmov/"     # Palmov Island: пустыня (одна палитра)
const CITY_DIR := DIR + "city/"   # ithappy Cartoon City: здания, светофоры

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
	# Трибуны — гоночная атрибутика: на классике и в городе. В пустыне их
	# нет — там вестерн (станция, лошади, бочки), зрителей не завезли.
	if track.kind != TrackBuilder.KIND_SAND:
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
		_build_race_extras()
	if track.kind == TrackBuilder.KIND_NEON:
		_build_city()
		_build_street_lamps()
	if track.kind == TrackBuilder.KIND_SAND:
		_build_desert()


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

	# Снаружи стартовой прямой: на классике и в городе — башня комментаторов
	# и тент-паддок с табличками команд; в пустыне — вестерн-паддок:
	# водонапорная башня, телега, коновязь с лошадьми и бочки.
	if _track.kind == TrackBuilder.KIND_SAND:
		var tank_pos := _axis_at_dist(18.0) + out * (_half(0.0) + 14.0)
		tank_pos.y = _ground_y(tank_pos)
		_spawn(PDIR + "water_tank.fbx", tank_pos, -out, 1.1, false)
		_occupy(tank_pos, 7.0)

		var cart_pos := _axis_at_dist(32.0) + out * (_half(0.0) + 9.0)
		cart_pos.y = _ground_y(cart_pos)
		_spawn(PDIR + "cart.fbx", cart_pos, _forward(0.0), 1.0, false)
		_occupy(cart_pos, 5.0)

		var hitch_pos := _axis_at_dist(-14.0) + out * (_half(0.0) + 6.0)
		hitch_pos.y = _ground_y(hitch_pos)
		_spawn(PDIR + "hitching_post.fbx", hitch_pos, -out, 1.0, false)
		for i in 2:
			var hp := hitch_pos + _forward(0.0) * (2.2 * i - 1.1) - out * 1.6
			hp.y = _ground_y(hp)
			_spawn(PDIR + ("horse_brown.fbx" if i == 0 else "horse_white.fbx"),
					hp, out, 1.0, false)
		_occupy(hitch_pos, 5.0)

		for i in 4:
			var p := _axis_at_dist(-26.0 - 5.0 * i) + out * (_half(0.0) + 2.0)
			p.y = _ground_y(p)
			_spawn(PDIR + (["barrel_a.fbx", "box_a.fbx", "barrel_b.fbx",
					"box_b.fbx"][i]), p, -out, 1.0, false)
		return

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


## Мелочь вдоль обочин — с шагом по кругу, чередуя стороны и виды. Всё за
## ограждением. Набор ТЕМАТИЧЕСКИЙ: на классике — гоночная атрибутика
## (флаги, шины, конусы, реклама), в пустыне — вестерн (бочки, ящики,
## деревянные вешки, кактусы), в городе — светофоры, урны, остановки и
## билборды. Фонарные столбы — ТОЛЬКО в ночном городе (_build_street_lamps),
## и там они светят по-настоящему.
func _build_roadside() -> void:
	var length: float = _track._curve.get_baked_length()
	var kinds: Array = [
		[DIR + "Flag_free.fbx", 1.0, true],
		[CDIR + "prop_tyre_4x1_A.FBX", 1.0, false],
		[DIR + "Cone_free.fbx", 1.0, true],
		[CDIR + "prop_adbox_A.FBX", 1.4, false],
		[DIR + "Tire_free.fbx", 1.0, true],
		[CDIR + "prop_adbox_B.FBX", 1.4, false],
		[CDIR + "prop_tyre_1x1_A.FBX", 1.0, false],
		[CDIR + "prop_adbox_C.FBX", 1.4, false],
	]
	if _track.kind == TrackBuilder.KIND_SAND:
		kinds = [
			[PDIR + "barrel_a.fbx", 1.0, false],
			[PDIR + "wooden_post.fbx", 1.0, false],
			[PDIR + "box_a.fbx", 1.0, false],
			[PDIR + "cactus_b.fbx", 1.1, false],
			[PDIR + "barrel_b.fbx", 1.0, false],
			[PDIR + "wooden_post.fbx", 1.0, false],
			[PDIR + "box_b.fbx", 1.0, false],
			[PDIR + "stone_a.fbx", 1.2, false],
		]
	# В городе обочина городская: светофоры (эмиссивные — светятся в ночи),
	# урны, автобусные остановки и билборды вместо флагов и конусов.
	elif _track.kind == TrackBuilder.KIND_NEON:
		kinds = [
			[CITY_DIR + "traffic_light_c.fbx", 1.0, false],
			[CITY_DIR + "trash_can_a.fbx", 1.0, false],
			[CITY_DIR + "bus_stop.fbx", 1.0, false, true],
			[CITY_DIR + "billboard_wide.fbx", 0.9, false],
			[CITY_DIR + "traffic_light_a.fbx", 0.85, false],
			[CITY_DIR + "trash_can_b.fbx", 1.0, false],
			[CITY_DIR + "traffic_light_b.fbx", 0.85, false],
			[CITY_DIR + "billboard_a.fbx", 0.62, false],
		]
	var step := 18.0
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
		# 4-й элемент — разворот на 180° (у остановки «спина» в +Z:
		# без разворота она стояла к дороге глухой стенкой).
		var face := side if kind.size() > 3 and kind[3] else -side
		_spawn(String(kind[0]), p, face, float(kind[1]), bool(kind[2]))


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
## за 12 м до вершины. На гоночных трассах (классика и город) перед щитом —
## мультяшные таблички отсчёта дистанции 3-2-1 (как на настоящих трассах).
func _build_turn_signs() -> void:
	var n := _track._pts.size()
	var length: float = _track._curve.get_baked_length()
	var racing := _track.kind == TrackBuilder.KIND_GRASS \
			or _track.kind == TrackBuilder.KIND_NEON
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
		if not racing:
			continue
		for k in 3:   # 1 — ближе всех к повороту, 3 — дальше всех
			var td := float(i) / n - (22.0 + 10.0 * k) / length
			var dp := _axis(td) + side * (_half(td) + 1.5)
			dp.y = _ground_y(dp)
			_spawn(CDIR + "prop_distance_%d.FBX" % (k + 1), dp,
					-_forward(td), 1.0, false)


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


## ---------- гоночные экстры классики ----------

## Классика — «домашний ипподром»: дополнительные трибуны (Palmov),
## мачты стадионного освещения (днём не горят — просто антураж гоночного
## комплекса) и широкие рекламные щиты вдоль полотна.
func _build_race_extras() -> void:
	# [t по кругу, путь, масштаб, отступ от полотна, полурадиус пропса].
	# Точка проверяется ГЛОБАЛЬНО (_track.distance_from_axis): контур
	# извилистый, и «наружу» от одного участка может стоять соседний виток —
	# без проверки трибуна ложилась прямо на полотно. Не влезло — пробуем
	# ту же вещь чуть дальше по кругу.
	for item: Array in [
		[0.30, PDIR + "grandstand_b.fbx", 1.5, 8.0, 8.0],
		[0.42, PDIR + "grandstand_a.fbx", 1.5, 8.0, 6.5],
		[0.88, CDIR + "prop_seats_small.FBX", 0.62, 9.0, 5.0],
		[0.18, CITY_DIR + "billboard_wide.fbx", 1.0, 4.0, 4.5],
		[0.48, CITY_DIR + "billboard_wide.fbx", 1.0, 4.0, 4.5],
		[0.70, CITY_DIR + "billboard_wide.fbx", 1.0, 4.0, 4.5],
		[0.05, PDIR + "stadium_light.fbx", 1.3, 12.0, 2.0],
		[0.35, PDIR + "stadium_light.fbx", 1.3, 12.0, 2.0],
		[0.56, PDIR + "stadium_light.fbx", 1.3, 12.0, 2.0],
		[0.78, PDIR + "stadium_light.fbx", 1.3, 12.0, 2.0],
	]:
		var off: float = item[3]
		var foot: float = item[4]
		for k in 10:
			var t: float = float(item[0]) + 0.021 * k
			var out := _outward(t)
			var p := _axis(t) + out * (_half(t) + off)
			var d: float = _track.distance_from_axis(p)
			if d < TrackBuilder.TRACK_HALF_WIDTH + 1.5 + foot:
				continue
			if _is_occupied(p, foot):
				continue
			p.y = _ground_y(p)
			var node := _spawn(String(item[1]), p, -out, float(item[2]), false)
			if node != null:
				_push_outside(node, out, _half(t) + 2.5)
				_occupy(node.position, foot)
			break


## ---------- уличные фонари ночного города ----------

## Фонарные столбы ЕСТЬ ТОЛЬКО ЗДЕСЬ — и они светят по-настоящему:
## тёплый OmniLight без теней у головки каждого фонаря. Шаг крупный,
## чтобы огней было ~15-18 на круг — дёшево и достаточно.
func _build_street_lamps() -> void:
	var length: float = _track._curve.get_baked_length()
	var step := 40.0
	var n := int(length / step)
	for i in n:
		var d := step * (i + 0.35)
		# Стартовую прямую не трогаем — там арка и стартовые огни.
		if d < 25.0 or d > length - 20.0:
			continue
		var t := d / length
		var side := _outward(t) if i % 2 == 0 else -_outward(t)
		var p := _axis(t) + side * (_half(t) + 1.5)
		p.y = _ground_y(p)
		var lamp := _spawn(DIR + "Pole_light_free.fbx", p, -side, 0.8, true)
		if lamp == null:
			continue
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.85, 0.55)
		light.light_energy = 3.2
		light.omni_range = 19.0
		light.shadow_enabled = false
		lamp.add_child(light)
		# Головка фонаря: вверх и к полотну (+Z локально — к трассе;
		# позиция в локальных координатах, масштаб узла 0.8 её ужмёт).
		light.position = Vector3(0, 5.8, 1.8)


## ---------- пустыня (Palmov Island) ----------

const CACTI: Array[String] = [
	"cactus_a.fbx", "cactus_b.fbx", "cactus_c.fbx",
	"cactus_d.fbx", "cactus_e.fbx", "cactus_f.fbx",
]
const DESERT_STONES: Array[String] = [
	"stone_a.fbx", "stone_b.fbx", "stone_c.fbx", "stone_d.fbx",
]
const DRY_TREES: Array[String] = ["dry_tree_a.fbx", "dry_tree_b.fbx"]
const DESERT_GRASS: Array[String] = ["grass_yellow_a.fbx", "grass_yellow_b.fbx"]
const DESERT_CRATES: Array[String] = [
	"barrel_a.fbx", "barrel_b.fbx", "box_a.fbx", "box_b.fbx",
]
const HORSES: Array[String] = ["horse_brown.fbx", "horse_white.fbx"]
const PALMS: Array[String] = ["palm_large.fbx", "palm_bent.fbx"]


## Пустыня: вестерн-станция с поездом, оазисы с пальмами, дальние монументы
## (пирамиды, сфинкс, гора-череп) за трассой и россыпь кактусов, камней,
## сухих деревьев, пучков жёлтой травы, брошенных бочек-ящиков и пасущихся
## лошадей по дюнам.
## Коллизий нет: по песку разрешено ездить, машина проходит насквозь.
func _build_desert() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260901
	_build_desert_station(rng)
	_build_desert_monuments(rng)
	_build_oases(rng)
	# Россыпь: [набор файлов, штук, отступ от кромки, масштаб от, масштаб до]
	for item: Array in [
		[CACTI, 70, 5.0, 0.9, 1.6],
		[DESERT_STONES, 46, 4.0, 0.8, 2.2],
		[DRY_TREES, 20, 9.0, 1.0, 1.5],
		[DESERT_GRASS, 60, 3.0, 0.9, 1.4],
		[DESERT_CRATES, 18, 6.0, 0.9, 1.1],
		[HORSES, 6, 24.0, 0.95, 1.05],
	]:
		var files: Array[String] = item[0]
		var count: int = item[1]
		var margin: float = item[2]
		var half := TrackBuilder.GROUND_SIZE * 0.47
		var edge := TrackBuilder.TRACK_HALF_WIDTH + TrackBuilder.SHOULDER
		var placed := 0
		var attempts := 0
		while placed < count and attempts < count * 8:
			attempts += 1
			var p := Vector3(rng.randf_range(-half, half), 0,
					rng.randf_range(-half, half))
			if _track.distance_from_axis(p) < edge + margin:
				continue
			if _is_occupied(p, 2.5):
				continue
			p.y = _ground_y(p)
			var yaw := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
			if yaw.length_squared() < 0.01:
				yaw = Vector3.FORWARD
			_spawn(PDIR + files[rng.randi() % files.size()], p, yaw,
					rng.randf_range(float(item[3]), float(item[4])), false)
			placed += 1


## Вестерн-станция: рельсы, паровоз с двумя вагонами, здание станции,
## водонапорная башня, коновязь с лошадью и ящики на «перроне». Одна
## сборная сцена в свободном секторе пустыни, подальше от полотна.
func _build_desert_station(rng: RandomNumberGenerator) -> void:
	var edge := TrackBuilder.TRACK_HALF_WIDTH + TrackBuilder.SHOULDER
	var half := TrackBuilder.GROUND_SIZE * 0.47
	for attempt in 90:
		var ang := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(half * 0.45, half * 0.85)
		var p0 := Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		if absf(p0.x) > half - 20.0 or absf(p0.z) > half - 20.0:
			continue
		if _track.distance_from_axis(p0) < edge + 38.0:
			continue
		if _is_occupied(p0, 30.0):
			continue
		# Рельсы — вдоль «горизонта» (перпендикулярно лучу от центра мира),
		# станция — со стороны, дальней от центра (задником к краю мира).
		var along := Vector3(-p0.z, 0, p0.x).normalized()
		var side := Vector3(p0.x, 0, p0.z).normalized()
		# [файл, смещение вдоль рельсов, смещение вбок, лицом куда, масштаб]
		for item: Array in [
			["railway.fbx", 0.0, 0.0, along, 1.0],
			["train.fbx", -8.0, 0.0, along, 1.0],
			["wagon_passenger.fbx", 5.2, 0.0, along, 1.0],
			["wagon_freight.fbx", 18.0, 0.0, along, 1.0],
			["railway_station.fbx", 0.0, 10.0, -side, 1.0],
			["water_tank.fbx", -18.0, 6.0, -side, 1.0],
			["hitching_post.fbx", 8.0, 5.0, -side, 1.0],
			["horse_brown.fbx", 9.5, 3.6, side, 1.0],
			["barrel_a.fbx", -4.0, 4.0, along, 1.0],
			["box_a.fbx", -5.5, 4.2, along, 1.0],
			["box_b.fbx", -4.6, 5.3, along, 1.0],
		]:
			var p := p0 + along * float(item[1]) + side * float(item[2])
			p.y = _ground_y(p)
			_spawn(PDIR + String(item[0]), p, item[3], float(item[4]), false)
		_occupy(p0, 30.0)
		return


## Оазисы: 3 группы пальм с травой у подножия — зелёные пятна среди дюн.
func _build_oases(rng: RandomNumberGenerator) -> void:
	var edge := TrackBuilder.TRACK_HALF_WIDTH + TrackBuilder.SHOULDER
	var half := TrackBuilder.GROUND_SIZE * 0.47
	var placed := 0
	var attempts := 0
	while placed < 3 and attempts < 120:
		attempts += 1
		var c := Vector3(rng.randf_range(-half, half), 0,
				rng.randf_range(-half, half))
		if _track.distance_from_axis(c) < edge + 10.0:
			continue
		if _is_occupied(c, 9.0):
			continue
		for k in rng.randi_range(2, 3):
			var pa := c + Vector3(rng.randf_range(-3.0, 3.0), 0,
					rng.randf_range(-3.0, 3.0))
			pa.y = _ground_y(pa)
			var yaw := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
			_spawn(PDIR + PALMS[rng.randi() % PALMS.size()], pa,
					yaw if yaw.length_squared() > 0.01 else Vector3.FORWARD,
					rng.randf_range(0.85, 1.15), false)
		for k in 4:
			var pg := c + Vector3(rng.randf_range(-4.5, 4.5), 0,
					rng.randf_range(-4.5, 4.5))
			pg.y = _ground_y(pg)
			_spawn(PDIR + DESERT_GRASS[rng.randi() % DESERT_GRASS.size()],
					pg, Vector3.FORWARD, rng.randf_range(0.9, 1.3), false)
		_occupy(c, 8.0)
		placed += 1


## Монументы пустыни: ищем каждому место в своём секторе круга — подальше
## от полотна, слегка утопив в песок (низ на дюнах неровный).
func _build_desert_monuments(rng: RandomNumberGenerator) -> void:
	var edge := TrackBuilder.TRACK_HALF_WIDTH + TrackBuilder.SHOULDER
	var half := TrackBuilder.GROUND_SIZE * 0.47
	# [файл, масштаб, радиус занимаемого места (м) с учётом масштаба]
	var items: Array = [
		["pyramid_b.fbx", 3.2, 34.0],
		["sphinx.fbx", 2.6, 18.0],
		["pyramid_a.fbx", 2.6, 18.0],
		["skull_mountain.fbx", 2.6, 28.0],
	]
	for k in items.size():
		var item: Array = items[k]
		var clear: float = item[2]
		for attempt in 60:
			var ang := TAU * k / items.size() + rng.randf_range(-0.55, 0.55)
			var dist := rng.randf_range(half * 0.55, half * 0.95)
			var p := Vector3(cos(ang) * dist, 0, sin(ang) * dist)
			if absf(p.x) > half or absf(p.z) > half:
				continue
			if _track.distance_from_axis(p) < edge + 8.0 + clear:
				continue
			if _is_occupied(p, clear):
				continue
			p.y = _ground_y(p) - 0.4
			_spawn(PDIR + String(item[0]), p, Vector3(-p.x, 0, -p.z),
					float(item[1]), false)
			_occupy(p, clear)
			break


## ---------- ночной город (ithappy Cartoon City) ----------

const CITY_BUILDINGS: Array[Array] = [
	# файл (без .fbx), высота модели (м), полудиагональ основания (м)
	["building_grid", 51.8, 18.4],
	["building_terrace", 24.5, 21.4],
	["building_tower", 53.2, 18.8],
]


## «Первая линия» города: настоящие мультяшные здания с отдельным мешем
## светящихся окон (*_night.fbx ставится в ту же точку). Кап высоты тот же,
## что у процедурных коробок: h ≤ 0.5·d — не закрывать камеру.
func _build_city_landmarks(rng: RandomNumberGenerator) -> void:
	var half := TrackBuilder.GROUND_SIZE * 0.47
	var edge := TrackBuilder.TRACK_HALF_WIDTH + TrackBuilder.SHOULDER
	var placed := 0
	var attempts := 0
	while placed < 9 and attempts < 300:
		attempts += 1
		var p := Vector3(rng.randf_range(-half, half), 0,
				rng.randf_range(-half, half))
		var d: float = _track.distance_from_axis(p)
		if d < edge + 14.0:
			continue
		var item: Array = CITY_BUILDINGS[placed % CITY_BUILDINGS.size()]
		var s: float = clampf(d * 0.5 / float(item[1]), 0.2, 0.42)
		var foot: float = float(item[2]) * s
		# Ближний угол здания не должен вылезать к полотну.
		if d - foot < edge + 8.0:
			continue
		if _is_occupied(p, foot + 6.0):
			continue
		p.y = _ground_y(p)
		var face: Vector3 = _track._curve.get_closest_point(p) - p
		var node := _spawn(CITY_DIR + String(item[0]) + ".fbx", p, face, s, false)
		if node != null:
			_spawn(CITY_DIR + String(item[0]) + "_night.fbx", p, face, s, false)
			_occupy(p, foot + 4.0)
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
	# Сначала — настоящие здания (займут место), коробки заполнят остальное.
	_build_city_landmarks(rng)
	# Пара фонтанов на «площадях» у трассы.
	for t: float in [0.25, 0.62]:
		var out := _outward(t)
		var fp := _axis(t) + out * (_half(t) + 9.0)
		fp.y = _ground_y(fp)
		if not _is_occupied(fp, 4.0):
			_spawn(CITY_DIR + "fountain.fbx", fp, -out, 1.0, false)
			_occupy(fp, 5.0)
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
		# Вывеска на фасаде к трассе: у части домов — неоновая плашка,
		# у высоких иногда — вертикальный светящийся signboard (ithappy).
		var r := rng.randf()
		if r < 0.45:
			_add_neon_sign(b.position, w, depth, hgt, rng)
		elif r < 0.65 and hgt > 13.0:
			_add_signboard(b.position, w, depth, hgt, rng)


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


## Вертикальная светящаяся вывеска (ithappy Signboard) на фасаде дома:
## меш подвешен от якоря ВНИЗ (габарит по y: -5.4…0.25), поэтому точка
## спавна — на высоте, вывеска свисает вдоль фасада.
func _add_signboard(
	center: Vector3, w: float, depth: float, hgt: float,
	rng: RandomNumberGenerator
) -> void:
	var to_track: Vector3 = _track._curve.get_closest_point(center) - center
	to_track.y = 0.0
	if to_track.length_squared() < 1.0:
		return
	to_track = to_track.normalized()
	var pos := center + to_track * (maxf(w, depth) * 0.5 + 0.4)
	pos.y = _ground_y(center) + minf(hgt - 1.0, rng.randf_range(9.0, 13.0))
	_spawn(CITY_DIR + "signboard.fbx", pos, to_track, 1.0, false)


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
	# Кометы прилетают периодически, шаттл кружит по орбите, ускорители
	# кувыркаются (см. _process).
	_comet_rng.seed = 20260903
	set_process(true)
	# Космический шаттл (Palmov) на медленной орбите вокруг мира — между
	# трассой и кольцом планет, полный оборот ~2 минуты.
	_shuttle = _spawn(PDIR + "space_shuttle.fbx",
			Vector3(cos(_shuttle_ang) * SHUTTLE_R, SHUTTLE_H,
					sin(_shuttle_ang) * SHUTTLE_R),
			Vector3.FORWARD, 2.2, false)
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

	# «Космический мусор»: отработанные ракетные ускорители (Palmov)
	# дрейфуют среди астероидов и медленно кувыркаются (см. _process).
	var junk_placed := 0
	var junk_attempts := 0
	while junk_placed < 5 and junk_attempts < 120:
		junk_attempts += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if _track.distance_from_axis(Vector3(x, 0, z)) < edge + 14.0:
			continue
		var yaw := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		if yaw.length_squared() < 0.01:
			yaw = Vector3.FORWARD
		var junk := _spawn(PDIR + "rocket_booster.fbx",
				Vector3(x, rng.randf_range(5.0, 16.0), z), yaw,
				rng.randf_range(0.5, 0.8), false)
		if junk != null:
			junk.rotation.x = rng.randf_range(-0.5, 0.5)
			junk.rotation.z = rng.randf_range(-0.4, 0.4)
			_junk.append({"node": junk, "spin": Vector3(
					rng.randf_range(-0.1, 0.1), rng.randf_range(-0.15, 0.15),
					rng.randf_range(-0.1, 0.1))})
		junk_placed += 1


## ---- Кометы (только космос): далёкий белый росчерк, периодически
## проносящийся по небу СБОКУ от мира (жалоба 31.08: «кометы должны быть
## вдалеке в виде пролетающей белой полосы» — раньше летели прямо над
## трассой крупным болидом).
const COMET_MAX := 3          # больше одновременно не держим
const COMET_FIRST := 1.5      # первая — почти сразу после старта, с
const COMET_DIST := 260.0     # хорда пролёта: ближе к центру мира не заходит
const COMET_RUN := 220.0      # плечо пролёта в каждую сторону от хорды, м
const SHUTTLE_R := 150.0      # радиус орбиты шаттла (планеты — на 150-195)
const SHUTTLE_H := 55.0       # высота орбиты, м
var _comets: Array[Dictionary] = []
var _comet_timer := COMET_FIRST
var _comet_rng := RandomNumberGenerator.new()
var _shuttle: Node3D
var _shuttle_ang := 2.4       # стартовая точка орбиты — в стороне от старта
var _junk: Array[Dictionary] = []   # кувыркающиеся ускорители


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
	# Шаттл: круговая орбита с лёгкой «волной» по высоте, нос по ходу.
	if _shuttle != null:
		_shuttle_ang += delta * (TAU / 120.0)
		var pos := Vector3(cos(_shuttle_ang) * SHUTTLE_R,
				SHUTTLE_H + sin(_shuttle_ang * 3.0) * 4.0,
				sin(_shuttle_ang) * SHUTTLE_R)
		var ahead := Vector3(cos(_shuttle_ang + 0.02) * SHUTTLE_R,
				SHUTTLE_H + sin((_shuttle_ang + 0.02) * 3.0) * 4.0,
				sin(_shuttle_ang + 0.02) * SHUTTLE_R)
		_shuttle.position = pos
		_shuttle.look_at(ahead)
	# Ускорители медленно кувыркаются.
	for j in _junk:
		(j["node"] as Node3D).rotation += (j["spin"] as Vector3) * delta


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


## Материалы городских моделей ithappy, которым нужна своя настройка.
const CITY_MATS := {
	"Color": true, "Color_Glossy": true, "Emissive": true,
	"Glass": true, "Road_Signs": true, "Billboard": true,
}


## Мультяшным мешам назначает текстуры по имени материала; светодиодам
## стартовых огней — красную эмиссию. FBX Palmov и ithappy ссылаются на
## текстуры, которых Godot при импорте не нашёл, — палитры назначаются
## здесь вручную (у Palmov все материалы «texture main[.NNN]»).
func _apply_cartoon_materials(root: Node3D) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			if src == null:
				continue
			var mat_name := src.resource_name
			if mat_name.begins_with("texture main"):
				mat_name = "palmov"
			if CARTOON_TEX.has(mat_name) or mat_name == "startlights" \
					or mat_name == "palmov" or CITY_MATS.has(mat_name):
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
	elif mat_name == "palmov":
		mat.albedo_texture = load(PDIR + "texture_main.png")
		mat.roughness = 1.0
	elif mat_name == "Emissive":
		# Светящиеся окна зданий и огни светофоров: emission-цвет ЧЁРНЫЙ,
		# оператор ADD — светится сама текстура палитры.
		var tex: Texture2D = load(CITY_DIR + "texture_city.png")
		mat.albedo_texture = tex
		mat.emission_enabled = true
		mat.emission = Color(0, 0, 0)
		mat.emission_texture = tex
		mat.emission_energy_multiplier = 1.6
	elif mat_name == "Glass":
		mat.albedo_color = Color(0.16, 0.22, 0.32)
		mat.roughness = 0.15
		mat.metallic = 0.4
	elif mat_name == "Road_Signs":
		mat.albedo_texture = load(CITY_DIR + "texture_signs.png")
	elif mat_name == "Billboard":
		mat.albedo_texture = load(CITY_DIR + "texture_banners.png")
	elif CITY_MATS.has(mat_name):   # Color / Color_Glossy
		mat.albedo_texture = load(CITY_DIR + "texture_city.png")
		if mat_name == "Color_Glossy":
			mat.roughness = 0.35
	else:
		mat.albedo_texture = load(TEX_DIR + CARTOON_TEX[mat_name])
	_mats[mat_name] = mat
	return mat
