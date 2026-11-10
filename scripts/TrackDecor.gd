class_name TrackDecor
extends Node3D
## Декор трассы из готовых лоуполи-ассетов (BEDRILL Track Environment Free +
## Cartoon Tracks Pack + Palmov Low Poly Locations + ithappy Cartoon City):
## финишная арка, стартовая ферма с огнями, трибуны, деревья, воздушные шары,
## реклама и знаки перед поворотами; в пустыне — скалы, гора-череп и кактусы;
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
var _env_named := {}     # "лист/имя" -> [Vector2 x, z] поставленных картонок


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
		var first := get_child_count()
		_build_space()
		_darken_from(first)
		_space_nebulae()
		return
	# КЛАССИКА (15.10): мир вокруг трассы — 2D из атласов ИИ-художника
	# (EnvSprites): картонки и куски земли, по вызову отрисовки на атлас
	# вместо сотен FBX. В 3D остались только стартовая арка, огни старта и разметка.
	if track.kind == TrackBuilder.KIND_GRASS:
		_build_start_gate()
		_build_road_marks()
		_build_grass_2d()
		return
	# НОЧНОЙ ГОРОД (15.10) — так же: 2D-кварталы из атласов, в 3D только
	# арка, огни старта и разметка.
	if track.kind == TrackBuilder.KIND_NEON:
		_build_start_gate()
		_build_road_marks()
		_build_neon_2d()
		return
	_build_start_area()
	# Трибуны — гоночная атрибутика: на классике, в городе и зимой. В
	# пустыне их нет — там вестерн (станция, лошади, бочки), зрителей не
	# завезли.
	if track.kind != TrackBuilder.KIND_SAND:
		_build_tribunes()
	# Ночью воздушных шаров не бывает — в городе вместо них здания; зимой
	# шары тоже не летают.
	if track.kind != TrackBuilder.KIND_NEON and track.kind != TrackBuilder.KIND_SNOW:
		_build_balloons()
	# Зимой обочины — 2D-мелочь из _build_snow_2d (сугробы, снеговики…).
	if track.kind != TrackBuilder.KIND_SNOW:
		_build_roadside()
	_build_turn_signs()
	_build_road_marks()
	# Деревья — только на классике: в пустыне не растут, в городе — здания,
	# зимой — свой еловый лес (_build_winter).
	if track.kind == TrackBuilder.KIND_GRASS:
		_build_trees()
		_build_race_extras()
	if track.kind == TrackBuilder.KIND_NEON:
		var first := get_child_count()
		_build_city()
		_darken_from(first)
		_build_street_lamps()
	if track.kind == TrackBuilder.KIND_SAND:
		_build_desert()
	if track.kind == TrackBuilder.KIND_SNOW:
		_build_snow_2d()


## ---------- размещение ----------

## Стартовая зона: арка с клетчатым баннером над трассой, ферма стартовых
## огней, башня комментаторов, тент-паддок и таблички команд.
## Всё, что добавлено в декор начиная с ребёнка first, затемнить
## (TrackBuilder.darken): город и планеты ночных трасс не высветляются
## обычным светом, которым освещены полотно и машины.
func _darken_from(first: int) -> void:
	var cache := {}
	for i in range(first, get_child_count()):
		TrackBuilder.darken(get_child(i), cache)


func _build_start_area() -> void:
	var out := _outward(0.0)
	_build_start_gate()

	# Снаружи стартовой прямой: в городе и зимой — башня комментаторов и
	# тент-паддок с табличками команд; в пустыне — вестерн-паддок:
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


## Арка с клетчатым баннером над стартом и ферма стартовых огней — всё, что
## нависает над полотном (картонкой не сделать: машины едут ПОД ними).
func _build_start_gate() -> void:
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


## ---------- классика в 2D ----------

const GRASS_SEED := 20261015
# Без class_name: новые классы не попадают в кэш классов, пока редактор
# не пересканирует проект, — грузим напрямую.
const EnvSprites := preload("res://scripts/EnvSprites.gd")
const EnvGrassAtlas := preload("res://scripts/EnvGrassAtlas.gd")
const EnvNeonAtlas := preload("res://scripts/EnvNeonAtlas.gd")
const EnvSnowAtlas := preload("res://scripts/EnvSnowAtlas.gd")
const EnvSpaceAtlas := preload("res://scripts/EnvSpaceAtlas.gd")

# Одинаковая картонка не ближе этого к такой же (м) — 23.10 игрок: «ставишь
# много одинаковых объектов рядом подряд». В лесу и аллее — свой, меньше.
const REPEAT_GAP := 22.0

# Паддок команд снаружи стартовой прямой: [лист, имя, отметка вдоль оси от
# старта (м), отступ за обочину (м)]. Как пит-лейн: бригады и боксы у
# самой дороги, тягачи и дома на колёсах за ними, машины безопасности —
# позади старта.
const GRASS_PADDOCK := [
	["stadium", "control_tower", 6.0, 13.0], ["stadium", "leaderboard", -3.0, 5.0],
	["pit", "canopy", 16.0, 4.0], ["pit", "crew_red", 22.0, 2.5],
	["pit", "garages", 32.0, 9.0], ["pit", "crew_blue", 41.0, 2.5],
	["pit", "fuel_cart", 47.0, 3.0], ["pit", "tyre_stack", 51.0, 3.0],
	["pit", "transporter", 58.0, 10.0], ["pit", "motorhome", 72.0, 10.0],
	["pit", "hauler", 86.0, 9.0],
	["pit", "pace_car", -18.0, 3.5], ["pit", "safety_truck", -28.0, 4.0],
	["pit", "tow_truck", -40.0, 5.0], ["pit", "pickup_trailer", -54.0, 6.0],
]

# Главная трибуна вдоль стартовой прямой напротив паддока: секции по
# порядку от −40 м шагом 10 м. Разные секции и мачты вперемешку, через
# одну отражены — не «одна картинка 13 раз подряд».
const GRASS_GRANDSTAND := [
	"light_tower", "stand", "stand_covered", "stand", "billboard",
	"stand_covered", "stand", "stand_covered", "light_tower",
]

# Зоны круга (доли от старта): у каждой своя тема — мир читается местами,
# а не одной россыпью. [t0, t1, сторона (1 — снаружи кольца, −1 — в
# инфилде, 0 — обе), набор, штук, повтор не ближе (м)].
const GRASS_ZONES := [
	[0.10, 0.30, -1, "camp", 30, REPEAT_GAP],     # кемпинг болельщиков
	[0.30, 0.44, 0, "park", 22, 12.0],            # аллея
	[0.44, 0.62, 1, "fair", 24, REPEAT_GAP],      # ярмарка у трибун
	[0.62, 0.78, 0, "service", 14, REPEAT_GAP],   # служебная зона
	[0.78, 0.92, -1, "parking", 22, 14.0],        # стоянка болельщиков
]
# Наборы зон: [лист, имя, вес, можно отражать].
const GRASS_SETS := {
	"camp": [
		["infield", "camper", 3.0, true], ["infield", "tent", 3.0, true],
		["infield", "picnic_tent", 2.0, true], ["infield", "fans_pickup", 2.0, true],
		["stadium", "toilets", 1.0, false], ["infield", "banners", 1.0, false],
		["infield", "bush", 1.0, true],
	],
	"park": [
		["infield", "poplars", 3.0, false], ["infield", "bush", 3.0, true],
		["infield", "topiary", 1.0, false], ["infield", "banners", 0.5, false],
	],
	"fair": [
		["stadium", "concession", 2.0, false], ["stadium", "merch_trailer", 2.0, true],
		["stadium", "ticket_booth", 1.0, false], ["stadium", "toilets", 1.0, false],
		["infield", "tyre_balloon", 1.0, false], ["infield", "banners", 1.5, false],
		["stadium", "arch", 0.5, false], ["infield", "picnic_tent", 1.0, true],
	],
	"service": [
		["pit", "tow_truck", 1.0, true], ["pit", "safety_truck", 1.0, true],
		["pit", "hauler", 1.0, true], ["pit", "pickup_trailer", 1.0, true],
		["infield", "medic_tent", 1.0, false], ["infield", "helipad", 0.5, true],
		["pit", "tyre_stack", 1.0, true], ["pit", "fuel_cart", 0.5, true],
	],
	"parking": [
		["infield", "parked_cars", 4.0, true], ["infield", "fans_pickup", 1.0, true],
		["infield", "camper", 1.0, true], ["infield", "bush", 2.0, true],
		["infield", "poplars", 1.0, false], ["infield", "topiary", 0.5, false],
	],
}
# Зелень по всему кругу, чтобы между зонами не было голого поля.
const GRASS_GREEN := [
	["infield", "poplars", 2.0, false], ["infield", "bush", 3.0, true],
	["infield", "topiary", 1.0, false],
]


## Классика: дешёвый стадионный трек (23.10, игрок: «больше гоночной
## трассы, как NASCAR и прочие дешёвые гонки, а не гонка в деревне»; форма
## трассы прежняя). Весь мир вокруг — картонки из атласов ИИ-художника
## (EnvSprites), разложенные как уровень: старт с паддоком и главной
## трибуной, по кругу — зоны (кемпинг, аллея, ярмарка, служебная, стоянка),
## у поворотов — шинные стенки, вдоль круга — трибуны, щиты, мачты.
## Порядок важен: сначала привязанное к трассе, потом зоны и зелень. Всё
## через общие занятые круги (_occupy) и запрет повтора рядом (_env_repeat_ok).
func _build_grass_2d() -> void:
	var env := EnvSprites.new(_iso_basis(), EnvGrassAtlas.SHEETS)
	var rng := RandomNumberGenerator.new()
	rng.seed = GRASS_SEED
	_grass_paddock(env)
	_grass_stands(env)
	_grass_corners(env, rng)
	for z: Array in GRASS_ZONES:
		_env_scatter(env, rng, GRASS_SETS[z[3]], int(z[4]), 3.0, 16.0,
				float(z[5]), float(z[0]), float(z[1]), int(z[2]))
	_env_scatter(env, rng, GRASS_GREEN, 30, 8.0, 24.0, 12.0)
	env.commit(self)


func _grass_paddock(env: EnvSprites) -> void:
	var out := _outward(0.0)
	var edge := _half(0.0) + TrackBuilder.SHOULDER
	for item: Array in GRASS_PADDOCK:
		var sheet: String = item[0]
		var what: String = item[1]
		var r := env.width(sheet, what) * 0.5
		var p := _axis_at_dist(float(item[2])) + out * (edge + float(item[3]) + r)
		if _env_free(p, r, 0.5):
			_env_put(env, sheet, what, p)
	# Флагман — у финишной черты по другую сторону, напротив стартовых огней.
	var fr := env.width("stadium", "flagman") * 0.5
	var fp := _axis_at_dist(3.0) - out * (edge + 1.5 + fr)
	if _env_free(fp, fr, 0.5):
		_env_put(env, "stadium", "flagman", fp)


## Главная трибуна вдоль стартовой прямой (GRASS_GRANDSTAND) и по кругу —
## трибуны, щиты и мачты по очереди шагом ~34 м.
func _grass_stands(env: EnvSprites) -> void:
	var length: float = _track._curve.get_baked_length()
	for i in GRASS_GRANDSTAND.size():
		_grass_stand_at(env, fposmod(-40.0 + 10.0 * i, length) / length, -1.0,
				GRASS_GRANDSTAND[i], i % 2 == 1)
	var cycle := ["stand", "billboard", "light_tower", "stand_covered",
			"billboard", "light_tower"]
	var n := int(length / 34.0)
	for i in n:
		var t := (float(i) + 0.5) / n
		if t * length < 60.0 or t * length > length - 60.0:
			continue   # стартовая прямая — главная трибуна и паддок
		_grass_stand_at(env, t, 1.0, cycle[i % cycle.size()], i % 2 == 0)


## Одна трибуна/щит/мачта у отметки t0 (или чуть дальше, если занято) на
## стороне sgn·наружу, а если там она закрыла бы полотно — на другой. У
## трибуны и щита два рисунка — лицом и тылом: лицо смотрит на трассу, и
## если трасса между ними и камерой, игрок видит тыл. У трибуны под
## навесом тыла нет — она открыта.
func _grass_stand_at(env: EnvSprites, t0: float, sgn: float, what0: String,
		mirror := false) -> void:
	for k in 8:
		var t := t0 + 0.006 * k
		for s: float in [sgn, -sgn]:
			var side := _outward(t) * s
			var what := what0
			if what == "stand" or what == "billboard":
				what += "_front" if (-side).dot(env.toward_camera()) > 0.0 else "_back"
			var r := env.width("stadium", what) * 0.5
			var p := _axis(t) + side * (_half(t) + TrackBuilder.SHOULDER + 2.5 + r)
			if not _env_free(p, r, 1.0):
				continue
			if _env_hides_track(env, p, env.height("stadium", what), r * 2.0):
				continue
			_env_put(env, "stadium", what, p, 1.0, mirror)
			return


## Повороты: на внешней стороне — шинная стенка и стопки шин вдоль дуги
## (туда вылетают), за 25 м до вершины — указатель; на прямых — флаги
## команд, реже. Шины стоят там, где им место, а не россыпью вдоль обочин.
func _grass_corners(env: EnvSprites, rng: RandomNumberGenerator) -> void:
	var n := _track._pts.size()
	var length: float = _track._curve.get_baked_length()
	var corner_t: Array[float] = []
	for pair: Array in _turn_peaks(10, 0.22):
		var t0 := float(pair[0]) / n
		corner_t.append(t0)
		var outer := 1.0 if float(pair[1]) > 0.0 else -1.0
		var k := 0
		for d: float in [-14.0, -5.0, 4.0, 13.0]:
			var t := t0 + d / length
			var what := "tyre_wall" if k % 2 == 0 else "tyre_stack"
			k += 1
			var r := env.width("pit", what) * 0.5
			var p := _axis(t) + _right(t) * outer * (_half(t)
					+ TrackBuilder.SHOULDER + 1.5 + r)
			if _env_free(p, r, 0.5):
				_env_put(env, "pit", what, p, 1.0, rng.randf() < 0.5)
		var ta := t0 - 25.0 / length
		var ar := env.width("infield", "arrow_sign") * 0.5
		var ap := _axis(ta) + _right(ta) * outer * (_half(ta) + TrackBuilder.SHOULDER
				+ 2.0 + ar)
		if _env_free(ap, ar, 0.5):
			_env_put(env, "infield", "arrow_sign", ap, 1.0,
					_forward(t0).dot(env.right()) < 0.0)
	# Флаги команд на прямых: шагом ~45 м, вдали от поворотов.
	var steps := int(length / 45.0)
	for i in steps:
		var t := (float(i) + 0.5) / steps
		var near_corner := false
		for c in corner_t:
			if absf(fposmod(t - c + 0.5, 1.0) - 0.5) * length < 30.0:
				near_corner = true
		if near_corner:
			continue
		var side := _right(t) * (1.0 if i % 2 == 0 else -1.0)
		var r := env.width("infield", "banners") * 0.5
		var p := _axis(t) + side * (_half(t) + TrackBuilder.SHOULDER + 2.0 + r)
		if _env_free(p, r, 0.5) and _env_repeat_ok("infield", "banners", p, 30.0):
			_env_put(env, "infield", "banners", p)


## Россыпь картонок list ([лист, имя, вес, можно отражать]) — count штук
## в полосе near..far м за обочиной, на отрезке круга t0..t1 (может
## переходить через старт: t1 > 1) и стороне side (1 — снаружи кольца,
## −1 — внутри, 0 — обе). Одинаковая картонка не ближе gap к такой же
## (_env_repeat_ok), высокое между камерой и полотном не ставится. Зерно
## фиксировано — трасса всегда одинаковая.
func _env_scatter(env: EnvSprites, rng: RandomNumberGenerator, list: Array,
		count: int, near: float, far: float, gap := REPEAT_GAP,
		t0 := 0.0, t1 := 1.0, side := 0) -> void:
	var placed := 0
	for _a in count * 10:
		if placed >= count:
			break
		var t := fposmod(rng.randf_range(t0, t1), 1.0)
		var dir := _outward(t)
		if side == -1 or (side == 0 and rng.randf() < 0.5):
			dir = -dir
		var item: Array = []
		var p := Vector3.ZERO
		var scale := 1.0
		var r := 0.0
		for _pick in 4:
			var cand: Array = list[_pick_weighted(list, rng, 2)]
			scale = rng.randf_range(0.9, 1.15)
			r = env.width(cand[0], cand[1], scale) * 0.5
			p = _axis(t) + dir * (_half(t) + TrackBuilder.SHOULDER
					+ rng.randf_range(near, far) + r)
			p.y = 0.0
			if _env_repeat_ok(cand[0], cand[1], p, gap):
				item = cand
				break
		if item.is_empty() or not _env_free(p, r, near):
			continue
		if _env_hides_track(env, p, env.height(item[0], item[1], scale), r * 2.0):
			continue
		_env_put(env, item[0], item[1], p, scale, bool(item[3]) and rng.randf() < 0.5)
		placed += 1


## ---------- ночной город в 2D ----------

const NEON_SEED := 20261016

# Кварталы ночного города по доле круга (23.10: «займись дизайном уровней»
# — раньше дома всех видов шли одной россыпью). Граница квартала чуть
# размыта (NEON_DISTRICT_BLUR), чтобы переход не был по линейке.
# [до t, имя квартала]; дальше последнего — снова первый.
const NEON_DISTRICTS := [
	[0.22, "downtown"], [0.48, "nightlife"], [0.74, "residential"],
	[1.0, "industrial"],
]
const NEON_DISTRICT_BLUR := 0.03
# Дома кварталов: [лист, имя, вес]. Высокие сами уходят на дальнюю от
# камеры сторону — у ближней закрыли бы полотно (_env_hides_track).
const NEON_BUILDINGS := {
	"downtown": [
		["buildings", "tower_cyan", 1.0], ["buildings", "tower_slim", 1.0],
		["buildings", "tower_round", 1.0], ["buildings", "office_curved", 1.0],
		["buildings", "skybridge", 0.7], ["buildings", "mast", 0.3],
		["buildings_tall", "tower_stepped", 1.0], ["buildings_tall", "tower_twisted", 1.0],
		["buildings_tall", "tower_checker", 1.0], ["buildings_tall", "tower_helipad", 1.0],
		["buildings_tall", "office_l", 1.0], ["buildings_tall", "twin_towers", 0.7],
		["buildings_tall", "tower_cylinder", 1.0], ["buildings_tall", "tower_crane", 0.5],
		["buildings_tall", "bank", 0.7], ["buildings_tall", "glass_cube", 1.0],
		["buildings_tall", "tower_screen", 1.0], ["buildings_tall", "tower_glassroof", 1.0],
		["buildings_tall", "center_curved", 1.0], ["buildings_tall", "tv_tower", 0.3],
		["buildings", "showroom", 0.7], ["buildings_low", "parking_booth", 0.4],
	],
	"nightlife": [
		["buildings", "nightclub", 1.5], ["buildings", "diner", 1.0],
		["buildings", "hotel", 1.0], ["buildings", "screen_store", 1.0],
		["buildings", "corner_store", 1.0], ["buildings", "showroom", 0.7],
		["buildings_mid", "gym", 1.0], ["buildings_mid", "corner_glass", 1.0],
		["buildings_mid", "pizza", 1.0], ["buildings_mid", "roof_billboard", 1.0],
		["buildings_low", "club_low", 1.0], ["buildings_low", "burger", 1.0],
		["buildings_low", "bar_low", 1.0], ["buildings_low", "shops_row", 1.0],
		["buildings_tall", "residential_tall", 0.5],
	],
	"residential": [
		["buildings_mid", "brick_fire", 1.5], ["buildings_mid", "townhouses", 1.5],
		["buildings_mid", "balconies", 1.0], ["buildings_mid", "lofts", 1.0],
		["buildings_mid", "office_violet", 0.7], ["buildings_mid", "roof_frame", 0.7],
		["buildings_mid", "pharmacy", 1.0], ["buildings_mid", "motel", 1.0],
		["buildings_mid", "mural", 1.0], ["buildings_tall", "residential_tall", 1.0],
		["buildings", "corner_store", 1.0], ["buildings_low", "shops_row", 1.0],
		["buildings_low", "garage_low", 0.7], ["buildings_low", "bar_low", 0.5],
	],
	"industrial": [
		["buildings_low", "warehouse_low", 1.5], ["buildings_low", "garage_low", 1.0],
		["buildings_low", "workshop_low", 1.5], ["buildings_low", "substation", 0.7],
		["buildings_low", "carwash_low", 1.0], ["buildings_low", "gas_shop", 1.0],
		["buildings_low", "parking_booth", 0.5], ["buildings", "tuning_shop", 1.5],
		["buildings", "car_wash", 1.0], ["buildings", "car_park", 1.0],
		["buildings_mid", "parking_deck", 1.0], ["buildings", "mast", 0.5],
	],
}

# Уличная мелочь у обочин: [имя, вес].
const NEON_STREET := [
	["bus_stop", 1.0], ["vending", 1.0], ["bench_bin", 2.0], ["barrier", 1.5],
	["cones", 2.0], ["power_pole", 1.0],
]

# Плоская мелочь на пустырях и обочинах: [имя, вес]. Стоящие такси и
# автобусы, разметка («нитро», зебра, старт) вне дороги — убраны 16.10.
const NEON_DECALS := [
	["puddle_cyan", 2.0], ["puddle_pink", 2.0], ["puddle_orange", 1.0],
	["oil_slick", 1.0], ["manhole", 2.0], ["grate", 2.0],
	["pool_violet", 1.0], ["pool_blue", 1.0], ["pool_orange", 1.0],
]

# Дом не выше этого (м на экране) — запасной вариант, когда высокий на
# этом месте закрыл бы полотно.
const NEON_LOW_BUILDING := 10.0


## Ночной город (15.10): весь мир вокруг трассы — картонки из атласов
## ИИ-художника (EnvSprites, листы нарисованы уже ночными).
## Порядок: фонари со светофорами и щиты у полотна, уличная мелочь, дома
## вдоль трассы и россыпь на земле — через общие занятые круги.
## Плоских кусков земли из листа patches (парковки, перекрёсток, площадь…)
## нет: 16.10 игрок — «островок другой картинки не вписывается» в землю.
func _build_neon_2d() -> void:
	var env := EnvSprites.new(_iso_basis(), EnvNeonAtlas.SHEETS)
	var rng := RandomNumberGenerator.new()
	rng.seed = NEON_SEED
	_neon_lamps(env)
	_neon_signs(env)
	_neon_street(env, rng)
	_neon_buildings(env, rng)
	_neon_decals(env, rng)
	env.commit(self)


## Фонари вдоль полотна, чередуя стороны (как 3D-фонари _build_street_lamps,
## шаг 40 м), их свет на полотне — те же запечённые пятна (_lamp_pools).
## Каждый третий — светофор (без пятна). Плафон на картинке смотрит вправо;
## если полотно от фонаря левее по экрану — картинка отражается, иначе
## фонарь стоит «задом» к дороге (замечание игрока 16.10).
func _neon_lamps(env: EnvSprites) -> void:
	var length: float = _track._curve.get_baked_length()
	var step := 40.0
	var heads: Array[Vector3] = []
	for i in int(length / step):
		var d := step * (i + 0.35)
		# Стартовую прямую не трогаем — там арка и стартовые огни.
		if d < 25.0 or d > length - 20.0:
			continue
		var t := d / length
		var side := _outward(t) if i % 2 == 0 else -_outward(t)
		var p := _axis(t) + side * (_half(t) + 1.5)
		if _track.distance_from_axis(p) < _half(t) + 1.0:
			continue   # шпилька: «снаружи» уже соседний виток
		var what := "lamp" if i % 3 != 2 else \
				("traffic_red" if i % 2 == 0 else "traffic_yellow")
		_env_put(env, "street", what, p, 1.0, (-side).dot(env.right()) < 0.0)
		if what == "lamp":
			heads.append(p - side * 1.44 + Vector3.UP * 5.0)
	_lamp_pools(heads)


## Неоновые стрелки перед крутыми поворотами (на внешней стороне, стрелка
## смотрит туда, куда уходит дорога на экране) и щиты лицом/тылом к камере.
func _neon_signs(env: EnvSprites) -> void:
	var n := _track._pts.size()
	var length: float = _track._curve.get_baked_length()
	for pair: Array in _turn_peaks(5, 0.30):
		var i: int = pair[0]
		var t := float(i) / n - 20.0 / length
		var right := _right(t)
		var side := right if pair[1] > 0.0 else -right
		var r := env.width("street", "neon_arrow") * 0.5
		var p := _axis(t) + side * (_half(t) + TrackBuilder.SHOULDER + r)
		if not _env_free(p, r, 0.0):
			continue
		var after := _forward(float(i) / n + 20.0 / length)
		_env_put(env, "street", "neon_arrow", p, 1.0, after.dot(env.right()) < 0.0)
	for t0: float in [0.15, 0.40, 0.65, 0.90]:
		for k in 10:
			var t := t0 + 0.021 * k
			var out := _outward(t)
			var what := "billboard_front" if (-out).dot(env.toward_camera()) > 0.0 \
					else "billboard_back"
			var r := env.width("street", what) * 0.5
			var p := _axis(t) + out * (_half(t) + TrackBuilder.SHOULDER + 2.0 + r)
			if _env_free(p, r, 1.0):
				_env_put(env, "street", what, p)
				break


## Улица: дома шагом ~10 м по обе стороны, в паре метров за обочиной —
## в кадре рядом с машинами (16.10: «дома далеко, их не видно»). Какие
## дома — решает квартал (NEON_DISTRICTS); одинаковый дом не ближе
## REPEAT_GAP к такому же. Высокое не ставится между камерой и полотном
## (закрыло бы машины): на таком месте пробуется низкий дом квартала, не
## влез и он — низкий отступает от дороги по 4 м, пока крыша не уйдёт с
## полотна (23.10: раньше ближняя к камере сторона стояла почти пустой).
func _neon_buildings(env: EnvSprites, rng: RandomNumberGenerator) -> void:
	var length: float = _track._curve.get_baked_length()
	var n := int(length / 10.0)
	var low := {}
	for d: String in NEON_BUILDINGS:
		low[d] = NEON_BUILDINGS[d].filter(func(it: Array) -> bool:
			return env.height(it[0], it[1]) <= NEON_LOW_BUILDING)
	for i in n:
		var t := (float(i) + 0.5) / n
		for sgn: float in [1.0, -1.0]:
			if rng.randf() < 0.15:
				continue   # проулок
			var district := _neon_district(t + rng.randf_range(
					-NEON_DISTRICT_BLUR, NEON_DISTRICT_BLUR))
			var side := _right(t) * sgn
			for attempt in 6:
				var list: Array = NEON_BUILDINGS[district] if attempt == 0 \
						else low[district]
				if list.is_empty():
					break
				var item: Array = list[_pick_weighted(list, rng, 2)]
				var sheet: String = item[0]
				var what: String = item[1]
				var scale := rng.randf_range(0.9, 1.1)
				var r := env.width(sheet, what, scale) * 0.5
				var back := 4.0 * maxf(0.0, attempt - 2.0)
				var p := _axis(t) + side * (_half(t) + TrackBuilder.SHOULDER
						+ rng.randf_range(1.5, 4.0) + back + r)
				p.y = 0.0
				if not _env_repeat_ok(sheet, what, p, REPEAT_GAP):
					continue
				if not _env_free(p, r, 1.5):
					continue
				if _env_hides_track(env, p, env.height(sheet, what, scale),
						r * 2.0):
					continue
				_env_put(env, sheet, what, p, scale)
				break


## Квартал ночного города в точке круга t.
func _neon_district(t: float) -> String:
	t = fposmod(t, 1.0)
	for d: Array in NEON_DISTRICTS:
		if t < float(d[0]):
			return d[1]
	return NEON_DISTRICTS[0][1]


## Уличная мелочь у обочин: остановки, автоматы, скамейки, заграждения,
## конусы, столбы — шагом ~30 м, сторона случайная.
func _neon_street(env: EnvSprites, rng: RandomNumberGenerator) -> void:
	var length: float = _track._curve.get_baked_length()
	var n := int(length / 30.0)
	for i in n:
		var t := (float(i) + rng.randf_range(0.2, 0.8)) / n
		var side := _right(t) * (1.0 if rng.randf() < 0.5 else -1.0)
		var what: String = NEON_STREET[_pick_weighted(NEON_STREET, rng)][0]
		var r := env.width("street", what) * 0.5
		var p := _axis(t) + side * (_half(t) + TrackBuilder.SHOULDER
				+ rng.randf_range(1.0, 5.0) + r)
		if _env_free(p, r, 0.5) and _env_repeat_ok("street", what, p, 40.0):
			_env_put(env, "street", what, p, 1.0, rng.randf() < 0.5)


## Лужи, люки, решётки, пятна света — россыпь по пустырям у трассы.
## Плоские, друг на друга не ложатся; картонки могут стоять поверх.
func _neon_decals(env: EnvSprites, rng: RandomNumberGenerator) -> void:
	var taken: Array[Vector3] = []
	var placed := 0
	for _a in 600:
		if placed >= 70:
			break
		var what: String = NEON_DECALS[_pick_weighted(NEON_DECALS, rng)][0]
		var r := env.extent("decals", what) * 0.5
		var p: Vector3 = _near_axis(rng, r + 0.5, r + 30.0)[0]
		if not _env_free(p, r, 0.5):
			continue
		var clash := false
		for q in taken:
			if Vector2(p.x - q.x, p.z - q.z).length() < r + q.y:
				clash = true
				break
		if clash:
			continue
		taken.append(Vector3(p.x, r, p.z))
		env.flat("decals", what, p, _track._ground_height, 1.0,
				rng.randf() * TAU, 2)
		placed += 1


## ---- что камера вообще может показать ----
# Камера идёт за машиной по трассе и не вращается: всё, что она когда-либо
# покажет, — её окно, протянутое вдоль оси круга. Картонки и куски вне этой
# полосы игрок не увидит никогда — их не ставим (23.10, игрок: «зачем
# ставить объекты туда, где камеры никогда не смотрят»).
const VIEW_HALF_H := 13.0 + 3.0   # полвысоты окна (ortho 26) + машина у борта и лаг слежения
const VIEW_HALF_W := 25.0 + 3.0   # полширины окна при экране до 2:1
const VIEW_CELL := 2.0            # клетка карты видимости, м экрана
var _view_grid := PackedByteArray()
var _view_org := Vector2.ZERO
var _view_n := Vector2i.ZERO
var _view_b: Basis


## Карта видимости в координатах экрана (ось x и y камеры): клетка = 1,
## если её показывает камера над какой-нибудь точкой оси.
func _view_build() -> void:
	_view_b = _iso_basis()
	var curve := _track._curve
	var length := curve.get_baked_length()
	var pts: Array[Vector2] = []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var d := 0.0
	while d < length:
		var q := curve.sample_baked(d)
		var s := Vector2(q.dot(_view_b.x), q.dot(_view_b.y))
		pts.append(s)
		lo = lo.min(s)
		hi = hi.max(s)
		d += 4.0
	var ext := Vector2(VIEW_HALF_W, VIEW_HALF_H)
	_view_org = lo - ext - Vector2.ONE * VIEW_CELL
	var span := (hi - lo + ext * 2.0) / VIEW_CELL
	_view_n = Vector2i(int(ceil(span.x)) + 3, int(ceil(span.y)) + 3)
	_view_grid.resize(_view_n.x * _view_n.y)
	_view_grid.fill(0)
	var cw := int(ceil(VIEW_HALF_W / VIEW_CELL))
	var ch := int(ceil(VIEW_HALF_H / VIEW_CELL))
	for s in pts:
		var cx := int((s.x - _view_org.x) / VIEW_CELL)
		var cy := int((s.y - _view_org.y) / VIEW_CELL)
		for y in range(maxi(cy - ch, 0), mini(cy + ch + 1, _view_n.y)):
			var row := y * _view_n.x
			for x in range(maxi(cx - cw, 0), mini(cx + cw + 1, _view_n.x)):
				_view_grid[row + x] = 1


## Попадёт ли когда-нибудь в кадр точка p (с полушириной r на экране).
func _on_screen(p: Vector3, r: float) -> bool:
	if _view_n == Vector2i.ZERO:
		_view_build()
	var sy := p.dot(_view_b.y)
	var sx := p.dot(_view_b.x)
	var cy := int(floor((sy - _view_org.y) / VIEW_CELL))
	if cy < 0 or cy >= _view_n.y:
		return false
	for dx: float in [-r, 0.0, r]:
		var cx := int(floor((sx + dx - _view_org.x) / VIEW_CELL))
		if cx >= 0 and cx < _view_n.x and _view_grid[cy * _view_n.x + cx] == 1:
			return true
	return false


## Нет ли такой же картонки (лист + имя) ближе gap к точке p — чтобы рядом
## не стояли подряд одинаковые (23.10, замечание игрока).
func _env_repeat_ok(sheet: String, what: String, p: Vector3, gap: float) -> bool:
	var key := sheet + "/" + what
	if not _env_named.has(key):
		return true
	for q: Vector2 in _env_named[key]:
		if Vector2(p.x - q.x, p.z - q.y).length() < gap:
			return false
	return true


## Закроет ли картонка высоты h (ширины w) полотно: она стоит между камерой
## и дорогой, и дорога попадает в полосу земли, которую она загораживает.
func _env_hides_track(env: EnvSprites, p: Vector3, h: float, w: float) -> bool:
	var reach := env.hide_reach(h)
	for lateral: float in [-0.5, 0.0, 0.5]:
		var base := p + env.right() * (w * lateral)
		var s := 2.0
		while s < reach:
			var q := base + env.away() * s
			if _track.distance_from_axis(q) < _track.half_width_at_pos(q) + 1.0:
				return true
			s += 3.0
	return false

## Свободна ли точка под картонку/кусок радиуса r: в пределах земли, в
## зоне, которую камера когда-нибудь покажет (_on_screen), не ближе margin
## к обочине любого витка, не в чужом занятом круге.
func _env_free(p: Vector3, r: float, margin: float) -> bool:
	var half := TrackBuilder.GROUND_SIZE * 0.47
	if absf(p.x) > half - r or absf(p.z) > half - r:
		return false
	return _on_screen(p, r) and _clear_of_track(p, r + margin) 			and not _is_occupied(p, r)


## Картонка в точке p (высота — по рельефу) + занятый круг по её ширине.
func _env_put(env: EnvSprites, sheet: String, what: String, p: Vector3,
		scale := 1.0, mirror := false) -> void:
	p.y = _ground_y(p)
	env.sprite(sheet, what, p, scale, mirror)
	_occupy(p, env.width(sheet, what, scale) * 0.5)
	var key := sheet + "/" + what
	if not _env_named.has(key):
		_env_named[key] = []
	_env_named[key].append(Vector2(p.x, p.z))


## Индекс случайного элемента списка [[имя, вес, ...], ...] по весам; вес —
## в поле wi (у списков [лист, имя, вес, ...] — 2).
func _pick_weighted(list: Array, rng: RandomNumberGenerator, wi := 1) -> int:
	var total := 0.0
	for it: Array in list:
		total += float(it[wi])
	var x := rng.randf() * total
	for i in list.size():
		x -= float(list[i][wi])
		if x <= 0.0:
			return i
	return list.size() - 1


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
			# Занятость — по РЕАЛЬНОМУ габариту (16.09: «ель растёт сквозь
			# трибуну» на зиме — круг 10 м от точки постановки не покрывал
			# длинную трибуну, а у prop_seats_big якорь вообще не в центре).
			_occupy_node(node, 1.5)


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
	# Зима: ёлочки, снеговики, заснеженные камни и колодец.
	elif _track.kind == TrackBuilder.KIND_SNOW:
		kinds = [
			[PDIR + "fir_winter_small.fbx", 1.1, false],
			[PDIR + "snowman.fbx", 1.0, false],
			[PDIR + "stone_winter_a.fbx", 1.6, false],
			[PDIR + "fir_winter_medium.fbx", 0.8, false],
			[PDIR + "stones_group_winter.fbx", 0.6, false],
			[PDIR + "snowman.fbx", 0.9, false],
			[PDIR + "fir_winter_small.fbx", 1.3, false],
			[PDIR + "winter_well.fbx", 0.9, false],
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
var _peaks_cache := {}


## Пики поворотов — с кэшем: окно кривизны по 1536 точкам и сортировка
## считались дважды за постройку (щиты и стрелки просят одно и то же).
func _turn_peaks(max_count: int, min_abs: float) -> Array:
	var key := "%d:%.3f" % [max_count, min_abs]
	if not _peaks_cache.has(key):
		_peaks_cache[key] = _turn_peaks_calc(max_count, min_abs)
	return _peaks_cache[key]


func _turn_peaks_calc(max_count: int, min_abs: float) -> Array:
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
			or _track.kind == TrackBuilder.KIND_NEON \
			or _track.kind == TrackBuilder.KIND_SNOW
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
	var placed := 0
	var attempts := 0
	while placed < 90 and attempts < 600:
		attempts += 1
		var p: Vector3 = _near_axis(rng, 7.0, SCATTER_FAR)[0]
		if absf(p.x) > half or absf(p.z) > half:
			continue
		if not _clear_of_track(p, 7.0):
			continue
		if _is_occupied(p, 4.0):
			continue
		p.y = _track._ground_height(p.x, p.z)
		var yaw_dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		if yaw_dir.length_squared() < 0.01:
			yaw_dir = Vector3.FORWARD
		var scale := rng.randf_range(0.8, 1.35)
		_spawn(CDIR + TREES[rng.randi() % TREES.size()], p, yaw_dir, scale, false)
		placed += 1


## ---------- зима ----------

const FIRS: Array[String] = [
	"fir_winter_large.fbx", "fir_winter_medium.fbx", "fir_winter_small.fbx",
	"fir_winter_bent.fbx", "fir_winter_tilted.fbx",
]
const WINTER_STONES: Array[String] = [
	"stone_winter_a.fbx", "stone_winter_b.fbx", "stone_winter_c.fbx",
	"stones_group_winter.fbx",
]
const WINTER_HOUSES: Array[String] = [
	"winter_house.fbx", "winter_house_2.fbx", "winter_house_3.fbx",
]
const XMAS_BALLS: Array[String] = [
	"xmas_ball_red.fbx", "xmas_ball_blue.fbx", "xmas_ball_yellow.fbx",
]


## Зимняя трасса (15.09): еловый лес вокруг, заснеженные камни, деревня из
## трёх бревенчатых домов с колодцем и снеговиками, наряженная ёлка со
## звездой и шарами у старта. Всё из пака Palmov (Winter environment).
func _build_winter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260915
	# Наряженная ёлка у старта — в первом свободном месте вдоль стартовой
	# прямой (16.09: точка «46 м, снаружи» попадала ровно в трибуну с
	# t = 0.06 — ёлка росла сквозь неё; ищем по кругу с шагом 12 м).
	var length: float = _track._curve.get_baked_length()
	for k in 30:
		var d := fposmod(46.0 + 12.0 * k, length)
		var t := d / length
		var tp := _axis_at_dist(d) + _outward(t) * (_half(t) + 12.0)
		if _is_occupied(tp, 6.0) or not _clear_of_track(tp, 8.0):
			continue
		_build_xmas_tree(tp, 1.35, rng)
		break
	_build_winter_village(rng)
	# Россыпь: [набор файлов, штук, отступ от кромки, масштаб от, масштаб до]
	for item: Array in [
		[FIRS, 120, 6.0, 0.85, 1.5],
		[WINTER_STONES, 34, 4.0, 0.9, 1.7],
		["snowman.fbx", 10, 5.0, 0.9, 1.1],
	]:
		var files: Array = item[0] if item[0] is Array else [item[0]]
		var count: int = item[1]
		var margin: float = item[2]
		var half := TrackBuilder.GROUND_SIZE * 0.47
		var placed := 0
		var attempts := 0
		while placed < count and attempts < count * 8:
			attempts += 1
			var p: Vector3 = _near_axis(rng, margin, SCATTER_FAR)[0]
			if absf(p.x) > half or absf(p.z) > half:
				continue
			if not _clear_of_track(p, margin):
				continue
			if _is_occupied(p, 3.0):
				continue
			p.y = _ground_y(p)
			_spawn(PDIR + String(files[rng.randi() % files.size()]), p,
					_rand_yaw(rng), rng.randf_range(float(item[3]), float(item[4])),
					false)
			placed += 1


## Наряженная ёлка: большая ель, звезда на макушке, шары по конусу.
## У шаров якорь СВЕРХУ (висят на нитке) — ставим прямо на «ветку».
func _build_xmas_tree(p: Vector3, scale: float, rng: RandomNumberGenerator) -> void:
	p.y = _ground_y(p)
	_spawn(PDIR + "fir_winter_large.fbx", p, _rand_yaw(rng), scale, false)
	_occupy(p, 4.0 * scale)
	var h := 7.98 * scale        # высота модели ели
	var r0 := 2.5 * scale        # радиус кроны у земли
	_spawn(PDIR + "star_bethlehem.fbx", p + Vector3(0, h - 0.15 * scale, 0),
			_forward(0.0), scale * 1.2, false)
	for i in 14:
		var k := 0.25 + 0.5 * (float(i) / 14.0)     # доля высоты
		var ang := float(i) * 2.399 + 0.4            # золотой угол — равномерно
		var rr := r0 * (1.0 - k) * 0.85
		var bp := p + Vector3(cos(ang) * rr, h * k, sin(ang) * rr)
		_spawn(PDIR + XMAS_BALLS[i % XMAS_BALLS.size()], bp, _rand_yaw(rng),
				scale * 1.6, false)


## Деревня: три дома полукругом лицом к площади, на площади — колодец и
## ёлка поменьше, рядом снеговики. Одна сцена в свободном секторе.
func _build_winter_village(rng: RandomNumberGenerator) -> void:
	var half := TrackBuilder.GROUND_SIZE * 0.47
	for attempt in 120:
		# Площадь деревни — в 18 м от кромки, снаружи кольца: дома по дуге
		# ещё на 12 м дальше, всё в пределах SCATTER_FAR.
		var na := _near_axis(rng, 18.0, 18.0, true)
		var c: Vector3 = na[0]
		if absf(c.x) > half - 18.0 or absf(c.z) > half - 18.0:
			continue
		if not _clear_of_track(c, 18.0):
			continue
		if _is_occupied(c, 22.0):
			continue
		# Дома — по дуге со стороны, дальней от трассы; фасадом к площади.
		var away: Vector3 = _outward(float(na[1]))
		for i in WINTER_HOUSES.size():
			var a := (float(i) - 1.0) * 0.95
			var dir := away.rotated(Vector3.UP, a)
			var hp := c + dir * 12.0
			if not _clear_of_track(hp, 6.0):
				continue
			hp.y = _ground_y(hp)
			_spawn(PDIR + WINTER_HOUSES[i], hp, -dir, 1.0, false)
			_occupy(hp, 6.0)
		var wp := c + away.rotated(Vector3.UP, 1.9) * 4.0
		wp.y = _ground_y(wp)
		_spawn(PDIR + "winter_well.fbx", wp, -away, 1.0, false)
		_occupy(wp, 2.5)
		_build_xmas_tree(c + away.rotated(Vector3.UP, -2.2) * 4.0, 0.9, rng)
		for i in 2:
			var sp := c + away.rotated(Vector3.UP, 3.0 + 0.6 * i) * (7.0 + 3.0 * i)
			sp.y = _ground_y(sp)
			_spawn(PDIR + "snowman.fbx", sp, away, 1.0, false)
			_occupy(sp, 1.5)
		_occupy(c, 20.0)
		return


## ---------- зима в 2D ----------

const SNOW_SEED := 20261023

# Участки круга (доли от старта; t1 > 1 — через старт): густой лес, поля
# между ними — с деревнями и снежными забавами. [t0, t1, набор, штук,
# повтор не ближе (м)]. Раньше (утро 23.10) всё одной россыпью по кругу.
const SNOW_ZONES := [
	[0.12, 0.40, "forest", 85, 9.0],
	[0.58, 0.86, "forest", 85, 9.0],
	[0.40, 0.58, "field", 22, REPEAT_GAP],
	[0.86, 1.12, "field", 22, REPEAT_GAP],
]
# Наборы: [лист, имя, вес, можно отражать].
const SNOW_SETS := {
	"forest": [
		["nature", "spruce_tall", 4.0, true], ["nature", "fir_group", 3.0, true],
		["nature", "fir_small", 3.0, true], ["nature", "birch_frost", 1.0, true],
		["nature", "bush_snow", 1.5, true], ["nature", "rocks", 0.5, true],
		["nature", "stump_ice", 0.5, true], ["nature", "oak_bare", 0.5, true],
	],
	"field": [
		["nature", "drift", 2.0, true], ["nature", "rocks", 1.5, true],
		["nature", "boulder", 1.5, true], ["nature", "bush_snow", 1.0, true],
		["nature", "rowan", 1.0, true], ["nature", "oak_bare", 1.0, true],
		["nature", "birch_frost", 1.0, true], ["nature", "snowman", 1.0, true],
		["nature", "snow_fort", 0.5, true], ["nature", "fir_small", 1.0, true],
	],
}
# Мелочь у самых обочин: [лист, имя, вес, можно отражать].
const SNOW_ROADSIDE := [
	["nature", "snowman", 2.0, true], ["nature", "drift", 2.0, true],
	["nature", "firewood", 1.0, true], ["nature", "rocks", 1.0, true],
	["nature", "snow_fort", 0.7, true], ["nature", "pump_frozen", 0.3, true],
	["village", "logs", 1.0, true], ["village", "sleigh", 0.5, true],
	["village", "ski_rack", 0.7, false],
]
# Деревня: дома полукругом с дальней от трассы стороны, на площади — своё.
const SNOW_HOUSES := ["cabin", "cottage", "lodge", "log_hut", "barn", "garage_snow"]
const SNOW_SQUARE := ["well", "rink", "jeep", "water_tower", "logs", "sleigh"]
# Деревни — по одной на поле: [t0, t1].
const SNOW_VILLAGES := [[0.43, 0.55], [0.89, 0.98]]
# Плоское на снегу: [имя, вес].
const SNOW_DECALS := [["drift_ridge", 2.0], ["snow_pile", 2.0], ["ice_pieces", 1.0]]


## Зима (23.10): лес, деревни и мелочь — картонки из атласов ИИ-художника
## вместо FBX-ёлок, камней и домов Palmov, разложенные участками (лес —
## поле с деревней — лес — поле с деревней). Старт, трибуны и знаки
## поворотов пока 3D (зимнего листа гонки нет). Наряженная ёлка у старта —
## первой, как раньше (в первое свободное место вдоль стартовой прямой).
func _build_snow_2d() -> void:
	var env := EnvSprites.new(_iso_basis(), EnvSnowAtlas.SHEETS)
	var rng := RandomNumberGenerator.new()
	rng.seed = SNOW_SEED
	var length: float = _track._curve.get_baked_length()
	var tr := env.width("village", "xmas_tree") * 0.5
	for k in 30:
		var d := fposmod(46.0 + 12.0 * k, length)
		var t := d / length
		var tp := _axis_at_dist(d) + _outward(t) * (_half(t) + 8.0 + tr)
		if _env_free(tp, tr, 6.0):
			_env_put(env, "village", "xmas_tree", tp, 1.2)
			break
	for v: Array in SNOW_VILLAGES:
		_snow_village(env, rng, float(v[0]), float(v[1]))
	_env_scatter(env, rng, SNOW_ROADSIDE, 40, 1.0, 6.0, 30.0)
	for z: Array in SNOW_ZONES:
		_env_scatter(env, rng, SNOW_SETS[z[2]], int(z[3]), 3.0, 24.0,
				float(z[4]), float(z[0]), float(z[1]))
	_snow_decals(env, rng)
	env.commit(self)


## Деревня снаружи кольца на отрезке t0..t1: площадь в 16–22 м от обочины,
## дома дугой с дальней от трассы стороны (все разные), на площади —
## колодец, каток, машина и т.п. Дом, который закрыл бы полотно, не ставится.
func _snow_village(env: EnvSprites, rng: RandomNumberGenerator, t0: float,
		t1: float) -> void:
	for _attempt in 120:
		var t := rng.randf_range(t0, t1)
		var away := _outward(t)
		var c := _axis(t) + away * (_half(t) + TrackBuilder.SHOULDER
				+ rng.randf_range(16.0, 22.0))
		c.y = 0.0
		if not _env_free(c, 6.0, 6.0):
			continue
		var houses := SNOW_HOUSES.duplicate()
		for i in houses.size():
			var j := rng.randi_range(i, houses.size() - 1)
			var tmp: String = houses[i]
			houses[i] = houses[j]
			houses[j] = tmp
		for i in 4:
			var what: String = houses[i]
			var r := env.width("village", what) * 0.5
			var hp := c + away.rotated(Vector3.UP, (float(i) - 1.5) * 0.7) * (8.0 + r)
			if _env_free(hp, r, 2.0) and not _env_hides_track(env, hp,
					env.height("village", what), r * 2.0):
				_env_put(env, "village", what, hp, 1.0, rng.randf() < 0.5)
		var square := SNOW_SQUARE.duplicate()
		for i in 3:
			var what: String = square.pop_at(rng.randi() % square.size())
			var r := env.width("village", what) * 0.5
			var sp := c + away.rotated(Vector3.UP, rng.randf() * TAU) * rng.randf_range(1.0, 5.0)
			if _env_free(sp, r, 2.0):
				_env_put(env, "village", what, sp, 1.0, rng.randf() < 0.5)
		return


## Сугробы и лёд — плоские, россыпью по снегу у трассы.
func _snow_decals(env: EnvSprites, rng: RandomNumberGenerator) -> void:
	var placed := 0
	for _a in 300:
		if placed >= 35:
			break
		var what: String = SNOW_DECALS[_pick_weighted(SNOW_DECALS, rng)][0]
		var scale := rng.randf_range(0.8, 1.3)
		var r := env.extent("decals", what, scale) * 0.5
		var p: Vector3 = _near_axis(rng, r + 0.5, r + 24.0)[0]
		if not _env_free(p, r, 0.5):
			continue
		env.flat("decals", what, p, _track._ground_height, scale,
				rng.randf() * TAU, 2)
		_occupy(p, r * 0.6)
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

## Фонарные столбы ЕСТЬ ТОЛЬКО ЗДЕСЬ. Шаг крупный — ~15-18 на круг.
## Свет фонарей ЗАПЕЧЁН (05.10): вместо OmniLight у головки — тёплое пятно
## на полотне под фонарём (_lamp_pools, одна сетка на все фонари). Точечный
## свет в gl_compatibility перерисовывает каждый задетый объект (а полотно —
## один объект на весь круг) — замер на телефоне: 6 мс кадра на 17 фонарях,
## 22 → 26 к/с. Чего лишились: машина под фонарём не подсвечивается.
func _build_street_lamps() -> void:
	var length: float = _track._curve.get_baked_length()
	var step := 40.0
	var n := int(length / step)
	var heads: Array[Vector3] = []
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
		# Головка фонаря: в локальных (0, 5.8, 1.8) — вверх и к полотну
		# (+Z локально — к трассе), масштаб узла 0.8. Пятно — под ней.
		heads.append(lamp.position - side * 1.8 * 0.8)
	_lamp_pools(heads)


## Пятна света фонарей на полотне: полоса по оси трассы ±POOL_R от каждой
## головки, поперёк — вся ширина полотна; яркость в вершинах — спад от
## точки под головкой (плавный, как у света с затуханием). Аддитивно и без
## освещения: стоит только закраска пятна.
const POOL_R := 9.0
const POOL_COLOR := Color(1.0, 0.78, 0.45)
const POOL_GAIN := 0.5


func _lamp_pools(heads: Array[Vector3]) -> void:
	if heads.is_empty():
		return
	var length: float = _track._curve.get_baked_length()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const ALONG := 1.0     # шаг вдоль оси, м
	const ACROSS := 8      # отрезков поперёк полотна
	for h: Vector3 in heads:
		var d0: float = _track._curve.get_closest_offset(h)
		var rows: Array = []
		var d := d0 - POOL_R
		while d <= d0 + POOL_R + 0.01:
			var t := fposmod(d, length) / length
			var c := _axis_at_dist(d)
			var r := _right(t)
			var half := _half(t)
			var row: Array = []
			for k in ACROSS + 1:
				var p := c + r * lerpf(-half, half, float(k) / ACROSS)
				# Высоко (15 см): сетка полотна своя, на изгибах и горке она местами
				# выше прямой между точками пятна — на 5 см пятно уходило под неё
				# полосами. Пятно аддитивное, осевую под ним просто подсвечивает.
				p.y = c.y + 0.15
				var f := clampf(1.0 - Vector2(p.x - h.x, p.z - h.z).length() / POOL_R,
						0.0, 1.0)
				row.append([p, f * f * POOL_GAIN])
			rows.append(row)
			d += ALONG
		for i in rows.size() - 1:
			for k in ACROSS:
				var q := [rows[i][k], rows[i][k + 1], rows[i + 1][k + 1], rows[i + 1][k]]
				for idx in [0, 1, 2, 0, 2, 3]:
					var v: Array = q[idx]
					st.set_color(Color(POOL_COLOR * float(v[1]), 1.0))
					st.add_vertex(v[0])
	var mi := MeshInstance3D.new()
	mi.name = "LampPools"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


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
## (гора-череп, скальные останцы) за трассой и россыпь кактусов, камней,
## сухих деревьев, пучков жёлтой травы, брошенных бочек-ящиков и пасущихся
## лошадей по дюнам.
## Коллизий нет: за отбойник (с 14.09) машина не попадает, декор —
## чистая картинка.
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
		var placed := 0
		var attempts := 0
		while placed < count and attempts < count * 8:
			attempts += 1
			var p: Vector3 = _near_axis(rng, margin, SCATTER_FAR)[0]
			if absf(p.x) > half or absf(p.z) > half:
				continue
			if not _clear_of_track(p, margin):
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
	var half := TrackBuilder.GROUND_SIZE * 0.47
	for attempt in 90:
		# Рельсы — в 20 м от кромки снаружи кольца, параллельно полотну;
		# станция и башня — ещё на 6…10 м дальше (задником от трассы).
		var na := _near_axis(rng, 20.0, 20.0, true)
		var p0: Vector3 = na[0]
		var t := float(na[1])
		if absf(p0.x) > half - 20.0 or absf(p0.z) > half - 20.0:
			continue
		if not _clear_of_track(p0, 20.0):
			continue
		if _is_occupied(p0, 30.0):
			continue
		var along := _forward(t)
		var side := _outward(t)
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
	var half := TrackBuilder.GROUND_SIZE * 0.47
	var placed := 0
	var attempts := 0
	while placed < 3 and attempts < 120:
		attempts += 1
		var c: Vector3 = _near_axis(rng, 10.0, SCATTER_FAR - 6.0)[0]
		if absf(c.x) > half or absf(c.z) > half:
			continue
		if not _clear_of_track(c, 10.0):
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


## Скальный останец: гроздь валунов из того же пака, раздутых до размера
## монумента, — крупная скала по центру, вокруг помельче и повёрнутые
## вразнобой. Ставится вместо египетских пирамид: на Диком Западе в
## прериях стоят камни (просьба 09.09).
func _build_rock_outcrop(rng: RandomNumberGenerator, c: Vector3,
		s: float) -> void:
	var stones: Array[String] = [
		"stone_a.fbx", "stone_b.fbx", "stone_c.fbx", "stone_d.fbx",
	]
	# stone_c — самый «башенный» из четырёх (≈1×1×1 м): в 14·s раз это
	# скала 14 м высотой при s = 1. Низ утоплен в песок, как у монументов.
	var core := 14.0 * s
	var p := Vector3(c.x, _ground_y(c) - 1.2 * s, c.z)
	_spawn(PDIR + "stone_c.fbx", p, _rand_yaw(rng), core, false)
	for k in rng.randi_range(3, 5):
		var ang := TAU * k / 5.0 + rng.randf_range(-0.5, 0.5)
		var d := core * rng.randf_range(0.35, 0.6)
		var q := c + Vector3(cos(ang) * d, 0, sin(ang) * d)
		q.y = _ground_y(q) - 0.8 * s
		_spawn(PDIR + stones[rng.randi() % stones.size()], q, _rand_yaw(rng),
				core * rng.randf_range(0.3, 0.6), false)


## Случайное направление «лица» для пропса, которому всё равно куда смотреть.
func _rand_yaw(rng: RandomNumberGenerator) -> Vector3:
	var v := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
	return v if v.length_squared() > 0.01 else Vector3.FORWARD


## Монументы пустыни: ищем каждому место в своём секторе круга — подальше
## от полотна, слегка утопив в песок (низ на дюнах неровный).
func _build_desert_monuments(rng: RandomNumberGenerator) -> void:
	var half := TrackBuilder.GROUND_SIZE * 0.47
	# [файл ("rocks" — гроздь валунов), масштаб, радиус места (м)]
	var items: Array = [
		["rocks", 1.5, 24.0],
		["skull_mountain.fbx", 2.6, 28.0],
		["rocks", 1.0, 16.0],
		["rocks", 1.25, 20.0],
	]
	for k in items.size():
		var item: Array = items[k]
		var clear: float = item[2]
		for attempt in 60:
			# Своя четверть круга у каждого монумента, отступ от кромки —
			# радиус места + 6 м: скала видна с полотна, но не нависает.
			var t := fposmod(float(k) / items.size() + rng.randf_range(-0.1, 0.1), 1.0)
			var out := _outward(t)
			var p := _axis(t) + out * (_half(t) + TrackBuilder.SHOULDER + clear + 6.0)
			p.y = 0.0
			if absf(p.x) > half or absf(p.z) > half:
				continue
			if not _clear_of_track(p, clear + 4.0):
				continue
			if _is_occupied(p, clear):
				continue
			p.y = _ground_y(p) - 0.4
			if String(item[0]) == "rocks":
				_build_rock_outcrop(rng, p, float(item[1]))
			else:
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
		var p: Vector3 = _near_axis(rng, 14.0, SCATTER_FAR + 6.0)[0]
		if absf(p.x) > half or absf(p.z) > half:
			continue
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


## Космос: планеты, шаттл, кометы и астероиды вокруг трассы. Только
## визуал, без коллизий.
##
## ГДЕ ЖИВЁТ ДЕКОР (23.09). Камера — ортографическая изометрия (IsoCamera:
## окно ~46×26 м вокруг машины, наклон 32°), горизонта и «заднего плана» у
## неё нет: всё, что попадает в кадр, проецируется на игровое поле. Высокий
## объект в кадре ложится ПОВЕРХ дороги (так висели ближние «спутники»
## до 31.08 — жалоба «планеты перед трассой»), а объект в дальнем кольце
## (150-195 м, как было 31.08-23.09) не виден НИКОГДА — зато его тень
## доставала до полотна (жалоба 23.09: «что-то отбрасывает тень на
## дорогу, но в камеру не попадает»: свет под 55° уносит тень на 0.7
## высоты вбок — тень планеты на 47 м лежала на оси трассы, тень шаттла
## на 55 м ползла по полотну ~10 % оборота; считано по
## TrackBuilder.distance_from_axis). Просьбы 23.09: «поместить их за
## трассу, чтобы хотя бы были видны», затем «не прятать планеты под
## трассу: пусть попадают в зону видимости камеры, но не перекрывают
## трассу». Решение — ставить объект по его МЕСТУ НА ЭКРАНЕ: у
## ортографической камеры объект на высоте H виден там, где лежала бы
## точка земли, сдвинутая от него на 1.6·H по диагонали к −X−Z
## («видимый след», см. _apparent). ПЛАНЕТЫ парят над пустотой рядом с
## полотном (центр на R+6 над уровнем дороги); кандидат подбирается
## так, чтобы весь видимый диск (13 точек в плоскости экрана, каждая
## спроецирована на уровень дороги) лежал ВНЕ полотна с запасом — тогда
## планета никогда не закрывает дорогу и машины — и чтобы из какой-нибудь
## точки оси в окно камеры попадало не меньше 60 % диска (_iso_visible).
## Само тело планеты тоже держится в стороне от полотна (прыгнувшая
## машина не влетит в шар). Дорога планету не заслоняет (та выше).
## Тонкость: окно камеры — ~46×26 м вокруг машины, полотно с бортами
## ±12 м, так что пустоты в кадре — полоска ~11 м сбоку от дороги (когда
## дорога идёт вдоль диагонали экрана) или ~7 м экранных «за» ней (когда
## поперёк) — планеты потому некрупные (R 4-7, кольчатые мельче), иначе
## ни в один просвет не влезут.
## ШАТТЛ летит вдоль трассы вровень с полотном (см. ниже), КОМЕТЫ
## прошивают мир под шоссе (в просветах — росчерк, под полотном скрыты).
## Тени у планет, шаттла и комет выключены (_no_shadow): планета над
## пустотой рядом с дорогой при свете под 55° бросала бы тень на
## полотно, а тень на звёздном поле не нужна.
func _build_space() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260902
	# Планеты — над пустотой, у самой трассы, каждая целиком в стороне от
	# полотна и на экране (см. заголовок). Пять цветных (одна с кольцами)
	# и «Сатурн» с двойным кольцом. Кандидат: видимый след на нормали к
	# оси в 2.5-4 м от борта плюс габарит (кольчатым — внешнее кольцо),
	# случайные отметка и сторона; само тело — на 1.6·H по диагонали
	# +X+Z от следа (высота H = R + 6). Берётся, если весь видимый диск
	# вне полотна, тело не над дорогой, до соседей ≥ 45 м, и из проб —
	# с наибольшей долей диска в окне (не меньше 60 %, кольчатым 45 %).
	var planets: Array[Vector3] = []
	var specs: Array = []   # [радиус, цвет, кольца]
	for k in 5:
		specs.append([rng.randf_range(4.0, 7.0) if k != 1 else 3.5,
				PLANET_COLORS[k], k == 1])
	# «Сатурн»: R 4 → 3.4 (23.10) — с учётом юбки платформы на 4 м ему не
	# находилось места в кадре.
	specs.append([3.4, Color(0.88, 0.74, 0.48), true])
	var length := _track._curve.get_baked_length()
	var cam_b := _iso_basis()
	for spec: Array in specs:
		var radius: float = spec[0]
		var ringed: bool = spec[2]
		# Габарит по горизонтали: у кольчатых — внешнее кольцо (2.3 R).
		var reach := radius * (2.3 if ringed else 1.0)
		var h := radius + 6.0
		var best := Vector3.INF
		var best_vis := 0.0
		# Кольчатым просветов хватает реже (габарит 2.3 R при том, что
		# на экране кольцо — узкий эллипс): проб больше, порог ниже.
		# 23.10: с учётом юбки платформы (_apparent_clear) мест меньше —
		# проб втрое больше.
		for _try in (1200 if ringed else 500):
			var off := rng.randf_range(0.0, length)
			var q := _track._curve.sample_baked(off)
			var right := _track.right_at_offset(off)
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var lat := _track.half_width_at_offset(off) + rng.randf_range(2.5, 4.0) \
					+ reach * rng.randf_range(1.0, 1.9)
			var foot := Vector3(q.x + right.x * lat * side, 0.0,
					q.z + right.z * lat * side)
			# Тело: назад по линии взгляда от следа на высоту h.
			var pos := foot + cam_b.z * (h / cam_b.z.y)
			if _track.distance_from_axis(pos) < _track.half_width_at_pos(pos) \
					+ 2.0 + reach:
				continue   # тело над дорогой (своей или другого витка)
			if not _apparent_clear(pos, reach, cam_b):
				continue   # диск на экране задел бы полотно
			var crowded := false
			for pq in planets:
				if Vector2(pq.x - pos.x, pq.z - pos.z).length() < 45.0:
					crowded = true
					break
			if crowded:
				continue
			var vis := _iso_visible(pos, reach)
			if vis > best_vis:
				best_vis = vis
				best = pos
			if vis >= 0.99:
				break
		if best_vis >= (0.45 if ringed else 0.6):   # кольчатым 0.5 → 0.45 (23.10, юбка)
			_spawn_planet(best, radius, spec[1], ringed, rng)
			planets.append(best)
		else:
			push_warning("TrackDecor: планете R=%.1f%s не нашлось места (лучшее %.2f)"
					% [radius, " с кольцами" if ringed else "", best_vis])
	# Кометы прилетают периодически, шаттл кружит по орбите, ускорители
	# кувыркаются (см. _process).
	_comet_rng.seed = 20260903
	set_process(true)
	# Космический шаттл (Palmov) летит ВДОЛЬ шоссе: в SHUTTLE_LAT от оси
	# снаружи поворотов (на прямых — где был), чуть ниже дороги (дно на
	# SHUTTLE_Y, верх около уровня полотна — за юбку не цепляет: он в
	# 5 м от борта), SHUTTLE_SPEED м/с — машины его обгоняют каждый круг
	# и видят краем кадра. Мелкий (0.5: ~8×4×11 м). Смену стороны в
	# повороте делает нырком под дорогу. См. _process.
	_shuttle = _spawn(PDIR + "space_shuttle.fbx", Vector3(0, SHUTTLE_Y, 0),
			Vector3.FORWARD, 0.5, false)
	if _shuttle != null:
		_no_shadow(_shuttle)
	# Астероиды: серые неровные глыбы (не шары — жалоба 24.09 «астероиды
	# не должны быть идеально круглыми»), парят невысоко у полотна. Ставятся
	# так же, как планеты, по месту на экране: до 24.09 они висели на 3-12 м
	# где попало в 10+ м от оси, и у ортографической камеры высокая глыба
	# ложилась на экране ПОВЕРХ дороги (след сдвинут на 1.6·H) — игрок
	# принимал их за планеты, «перекрывающие трассу». Теперь весь видимый
	# диск глыбы за бортом (_float_spot).
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.42, 0.4, 0.48)
	rock_mat.roughness = 1.0
	var rock_meshes: Array[ArrayMesh] = []
	for k in 5:
		rock_meshes.append(_rock_mesh(rng))
	var rocks: Array[Vector3] = []
	for k in 16:
		var sc := Vector3(rng.randf_range(1.0, 2.6),
				rng.randf_range(0.8, 2.0), rng.randf_range(1.0, 2.6))
		var reach := ROCK_BULGE * maxf(sc.x, maxf(sc.y, sc.z))
		var pos := _float_spot(rng, reach, 1.5, 6.0, 1.0, 9.0, cam_b,
				planets, 18.0, rocks, 9.0)
		if pos == Vector3.INF:
			continue
		var rock := MeshInstance3D.new()
		rock.name = "Asteroid"
		rock.mesh = rock_meshes[k % rock_meshes.size()]
		rock.material_override = rock_mat
		rock.scale = sc
		rock.rotation_degrees = Vector3(rng.randf_range(0, 360),
				rng.randf_range(0, 360), rng.randf_range(0, 360))
		add_child(rock, true)
		rock.position = pos
		rocks.append(pos)

	# «Космический мусор»: отработанные ракетные ускорители (Palmov)
	# дрейфуют среди астероидов и медленно кувыркаются (см. _process). Место —
	# как у астероидов; габарит — полудлина модели (кувыркается же).
	for k in 5:
		var yaw := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		if yaw.length_squared() < 0.01:
			yaw = Vector3.FORWARD
		var junk := _spawn(PDIR + "rocket_booster.fbx", Vector3.ZERO, yaw,
				rng.randf_range(0.5, 0.8), false)
		if junk == null:
			continue
		var reach := _node_reach(junk)
		var pos := _float_spot(rng, reach, 2.0, 7.0, 1.5, 9.0, cam_b,
				planets, 18.0, rocks, 10.0)
		if pos == Vector3.INF:
			junk.queue_free()
			continue
		junk.position = pos
		rocks.append(pos)
		junk.rotation.x = rng.randf_range(-0.5, 0.5)
		junk.rotation.z = rng.randf_range(-0.4, 0.4)
		_junk.append({"node": junk, "spin": Vector3(
				rng.randf_range(-0.1, 0.1), rng.randf_range(-0.15, 0.15),
				rng.randf_range(-0.1, 0.1))})


## Во сколько раз выступ глыбы (_rock_mesh) дальше единичной сферы.
const ROCK_BULGE := 1.3


## Место для висящего у полотна декора с габаритом reach (радиус описанного
## шара): видимый след — на нормали к оси в lat_lo..lat_hi м от борта плюс
## габарит, высота h_lo..h_hi над дорогой, тело — назад по линии взгляда.
## Годится, если тело не над полотном, видимый диск целиком за бортом
## (_apparent_clear) и до планет не ближе planet_gap, до прочего — gap
## (по горизонтали). Не нашлось за 80 проб — Vector3.INF.
func _float_spot(rng: RandomNumberGenerator, reach: float, h_lo: float,
		h_hi: float, lat_lo: float, lat_hi: float, cam_b: Basis,
		planets: Array[Vector3], planet_gap: float, taken: Array[Vector3],
		gap: float) -> Vector3:
	var length := _track._curve.get_baked_length()
	for _try in 80:
		var off := rng.randf_range(0.0, length)
		var q := _track._curve.sample_baked(off)
		var right := _track.right_at_offset(off)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var lat := _track.half_width_at_offset(off) + rng.randf_range(lat_lo, lat_hi) 				+ reach
		var foot := Vector3(q.x + right.x * lat * side, 0.0,
				q.z + right.z * lat * side)
		var h := rng.randf_range(h_lo, h_hi) + reach
		var pos := foot + cam_b.z * (h / cam_b.z.y)
		if _track.distance_from_axis(pos) < _track.half_width_at_pos(pos) 				+ 2.0 + reach:
			continue
		if not _apparent_clear(pos, reach, cam_b):
			continue
		var ok := true
		for pq in planets:
			if Vector2(pq.x - pos.x, pq.z - pos.z).length() < planet_gap:
				ok = false
				break
		for pq in taken:
			if not ok or Vector2(pq.x - pos.x, pq.z - pos.z).length() < gap:
				ok = false
				break
		if ok:
			return pos
	return Vector3.INF


## Неровная гранёная глыба (радиус ~1, выступы до ROCK_BULGE): сфера,
## вершины которой сдвинуты по шуму от направления (швы и полюса сферы —
## одна точка, одно направление: трещин нет) и сплюснуты парой «сколов»;
## нормали по граням — плоская заливка, как у камня.
static func _rock_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.9
	noise.fractal_octaves = 2
	var cuts: Array[Vector3] = []
	for k in 2:
		cuts.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1),
				rng.randf_range(-1, 1)).normalized())
	var src := SphereMesh.new()
	src.radius = 1.0
	src.height = 2.0
	src.radial_segments = 12
	src.rings = 7
	var arrays := src.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var d := verts[i].normalized()
		var r := 1.0 + 0.3 * noise.get_noise_3dv(d * 1.7)
		# Скол: всё, что дальше 0.6 по направлению скола, срезано.
		for c in cuts:
			var along := d.dot(c) * r
			if along > 0.62:
				r *= 0.62 / along
		verts[i] = d * minf(r, ROCK_BULGE)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in idx:
		st.add_vertex(verts[i])
	st.generate_normals()   # вершины не общие — нормали по граням
	return st.commit()


## Радиус шара с центром в начале узла, в который помещается всё его
## содержимое (по габаритам сеток, с текущими масштабом и поворотом).
static func _node_reach(root: Node3D) -> float:
	var reach := 0.0
	var inv := root.global_transform.affine_inverse()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var ab := mi.mesh.get_aabb()
		for k in 8:
			var c := inv * (mi.global_transform * ab.get_endpoint(k))
			reach = maxf(reach, (c * root.scale).length())
	return reach


## ---- Кометы (только космос): белый росчерк, периодически проносящийся
## ПОД шоссе через весь мир (23.09; до того — по небу сбоку от мира на
## 260 м, где ортографическая камера его не видела ни разу, см.
## _build_space). Летит ровно, на 7-10 м ниже дороги (голова под юбкой
## борта, глубже — на экране уползает под дорогу): в просветах между
## витками и за бортом мелькает белой полосой, под полотном скрыт.
const COMET_MAX := 3          # больше одновременно не держим
const COMET_FIRST := 1.5      # первая — почти сразу после старта, с
const COMET_CHORD := 90.0     # хорда пролёта не дальше этого от центра мира
const COMET_RUN := 220.0      # плечо пролёта в каждую сторону от хорды, м
const SHUTTLE_LAT := 21.0     # шаттл: смещение от оси трассы, м
const SHUTTLE_Y := -3.0       # ...высота дна (чуть ниже полотна)
const SHUTTLE_SPEED := 14.0   # ...скорость вдоль трассы, м/с
var _comets: Array[Dictionary] = []
var _comet_timer := COMET_FIRST
var _comet_rng := RandomNumberGenerator.new()
var _shuttle: Node3D
var _shuttle_off := 60.0      # отметка шаттла на оси (стартует впереди)
var _shuttle_lat := SHUTTLE_LAT   # текущее боковое смещение (знак — сторона)
var _shuttle_side := 1.0
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
	# Шаттл: вдоль оси трассы со сдвигом вбок, снаружи поворотов
	# (сторона по знаку кривизны: cross(t0, t1).y > 0 — поворот налево,
	# снаружи — справа), на прямых сторона не меняется; смещение
	# перетекает плавно (~3 с) — при смене стороны он ныряет под дорогу.
	if _shuttle != null:
		var curve := _track._curve
		var length := curve.get_baked_length()
		_shuttle_off = fposmod(_shuttle_off + delta * SHUTTLE_SPEED, length)
		var q := curve.sample_baked(_shuttle_off)
		var q0 := curve.sample_baked(fposmod(_shuttle_off - 4.0, length))
		var q2 := curve.sample_baked(fposmod(_shuttle_off + 4.0, length))
		var t0 := (q - q0); t0.y = 0.0; t0 = t0.normalized()
		var t1 := (q2 - q); t1.y = 0.0; t1 = t1.normalized()
		var bend := t0.cross(t1).y
		if absf(bend) > 0.03:
			_shuttle_side = -signf(bend)
		_shuttle_lat = move_toward(_shuttle_lat, SHUTTLE_LAT * _shuttle_side,
				delta * 14.0)
		var tng := (t0 + t1).normalized()
		var left := Vector3.UP.cross(tng)
		var pos := q + left * _shuttle_lat
		pos.y = SHUTTLE_Y + sin(_shuttle_off * 0.12) * 0.6
		_shuttle.position = pos
		_shuttle.rotation.y = atan2(tng.x, tng.z)
		# Крен в сторону перетекания, как у самолёта.
		_shuttle.rotation.z = clampf((SHUTTLE_LAT * _shuttle_side - _shuttle_lat)
				* 0.02, -0.5, 0.5)
	# Ускорители медленно кувыркаются.
	for j in _junk:
		(j["node"] as Node3D).rotation += (j["spin"] as Vector3) * delta


## Комета проносится ПОД шоссе через мир: по прямой, чья ближайшая к
## центру мира точка — не дальше COMET_CHORD. Курс — касательная к этому
## кругу, без снижения (иначе за 440 м пролёта ушла бы сквозь звёздное
## поле на -SPACE_VOID_DROP).
func _spawn_comet() -> void:
	var ang := _comet_rng.randf_range(0.0, TAU)
	var chord := _comet_rng.randf_range(0.0, COMET_CHORD)
	var base := Vector3(cos(ang) * chord,
			_comet_rng.randf_range(-10.0, -7.0), sin(ang) * chord)
	# Касательное направление (по или против часовой — случайно).
	var dir := Vector3(-sin(ang), 0.0, cos(ang))
	if _comet_rng.randf() < 0.5:
		dir = -dir
	var start := base - dir * COMET_RUN
	var vel := dir * _comet_rng.randf_range(70.0, 110.0)
	var node := _make_comet()
	node.name = "Comet"
	_no_shadow(node)
	add_child(node)
	node.position = start
	node.look_at(start + vel)   # -Z по ходу, хвост построен в +Z
	# Жизни хватает пролететь плечо в обе стороны и «растаять» там.
	_comets.append({
		"node": node, "vel": vel,
		"life": COMET_RUN * 2.0 / vel.length(),
	})


## Комета: БЕЛАЯ ПОЛОСА — маленькая яркая голова и длинный тонкий
## хвост-росчерк назад (+Z), сужающийся в точку. Пролетает под шоссе в
## окне камеры (~46 м) — росчерк почти во весь экран. UNSHADED —
## светится в темноте.
func _make_comet() -> Node3D:
	var root := Node3D.new()
	var head := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.2
	s.height = 2.4
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
	cone.top_radius = 1.0    # тонкий у головы...
	cone.bottom_radius = 0.0 # ...в точку позади — росчерк движения
	cone.height = 40.0       # длинный: полоса, а не болид
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
	tail.position.z = 20.0
	root.add_child(tail)
	return root


## Кольца на экране: отношение малой оси эллипса к большой (0 — ребром,
## 1 — плашмя кругом) и поворот эллипса от горизонтали экрана, градусы.
const RING_OPEN := 0.25
const RING_ROLL := 22.0


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
		# Наклон — от ЭКРАНА, а не от мира (жалоба 24.09 «кольца не должны
		# быть параллельны камере»: горизонтальное кольцо под камерой с
		# наклоном 32° плюс случайный крен планеты смотрело на игрока почти
		# плашмя, кругом). Теперь на экране кольцо — узкий эллипс (сжатие
		# RING_OPEN), повёрнутый на RING_ROLL° вбок, как на снимках Сатурна.
		var b := _iso_basis()
		var tilt := asin(RING_OPEN)
		var roll := deg_to_rad(rng.randf_range(RING_ROLL - 8.0, RING_ROLL + 8.0)) 				* (1.0 if rng.randf() < 0.5 else -1.0)
		var up := (b.y * cos(tilt) + b.z * sin(tilt)).rotated(b.z, roll)
		var ax := b.x.rotated(b.z, roll)
		var ring_basis := Basis(ax, up, ax.cross(up)).orthonormalized()
		for cfg: Array in [[1.25, 1.85, 0.45], [1.95, 2.3, 0.15]]:
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = radius * float(cfg[0])
			torus.outer_radius = radius * float(cfg[1])
			ring.mesh = torus
			var rcol := col.lightened(float(cfg[2]))
			var rmat := StandardMaterial3D.new()
			rmat.albedo_color = rcol
			rmat.emission_enabled = true
			rmat.emission = rcol * 0.45
			ring.material_override = rmat
			ring.name = "PlanetRing"
			planet.add_child(ring)
			# Плоский диск (0.03 по оси кольца) в экранном наклоне.
			ring.global_basis = ring_basis * Basis.from_scale(Vector3(1.0, 0.03, 1.0))
	_no_shadow(planet)   # фон, см. _build_space


## Туманности и галактики на пустоте под платформой (23.10): плоские куски
## ИИ-художника кладутся сложением цвета поверх звёздного поля и разбивают
## его повтор (тайл 50 м). Не темнятся (_darken_from) — светятся сами.
func _space_nebulae() -> void:
	var env := EnvSprites.new(_iso_basis(), EnvSpaceAtlas.SHEETS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261023
	var names: Array = EnvSpaceAtlas.NEBULAE.keys()
	var half := TrackBuilder.GROUND_SIZE * 0.45
	var taken: Array[Vector3] = []   # x, z — центр, y — радиус
	for _a in 600:
		if taken.size() >= 26:
			break
		var what: String = names[rng.randi() % names.size()]
		var scale := rng.randf_range(0.8, 1.3)
		var r := env.extent("nebulae", what, scale) * 0.5
		var p := Vector3(rng.randf_range(-half, half), 0.0, rng.randf_range(-half, half))
		if not _on_screen(Vector3(p.x, -TrackBuilder.SPACE_VOID_DROP, p.z), r):
			continue
		var clash := false
		for q in taken:
			if Vector2(p.x - q.x, p.z - q.z).length() < (r + q.y) * 0.8:
				clash = true
				break
		if clash:
			continue
		taken.append(Vector3(p.x, r, p.z))
		env.flat("nebulae", what, p, _track._ground_height, scale,
				rng.randf() * TAU, 1)
	env.commit(self)


## ---------- утилиты ----------

## Базис ИГРОВОЙ камеры (IsoCamera: наклон и поворот — из её умолчаний):
## x — вправо по экрану, y — вверх по экрану, z — от сцены к камере.
static func _iso_basis() -> Basis:
	var cam := IsoCamera.new()
	var b := Basis.from_euler(Vector3(deg_to_rad(cam.pitch_deg),
			deg_to_rad(cam.yaw_deg), 0.0))
	cam.free()
	return b


## 13 точек диска (шар с центром p, радиус r, как он виден на экране):
## центр и окружность в плоскости экрана.
static func _disc_samples(p: Vector3, r: float, b: Basis) -> Array[Vector3]:
	var samples: Array[Vector3] = [p]
	for k in 12:
		var a := TAU * k / 12.0
		samples.append(p + (b.x * cos(a) + b.y * sin(a)) * r)
	return samples


## Плотная выборка видимого диска для проверки «не касается полотна»:
## центр, кольцо на половине радиуса и край по 24 точки — у планеты
## радиусом 20 м шаг по краю ~5 м, полотно между точками не проскочит.
static func _disc_dense(p: Vector3, r: float, b: Basis) -> Array[Vector3]:
	var samples: Array[Vector3] = [p]
	for k in 24:
		var a := TAU * k / 24.0
		var d := b.x * cos(a) + b.y * sin(a)
		samples.append(p + d * (r * 0.5))
		samples.append(p + d * r)
	return samples


## «Видимый след» точки: где на уровне дороги (y = 0) она лежит для
## ортографической камеры — точка пересечения её линии взгляда с
## плоскостью полотна.
static func _apparent(p: Vector3, b: Basis) -> Vector3:
	return p - b.z * (p.y / b.z.y)


## Не задевает ли видимый диск шара (p, r) полотно ни в одной точке —
## след каждой точки диска (_disc_dense) дальше борта с запасом 1.5 м и
## не на юбке платформы. Так висящее над пустотой никогда не ложится на
## экране поверх трассы. Юбка (SPACE_SKIRT 5 м вниз от борта) видна под
## ближним к камере бортом полосой — её след на уровне дороги лежит от
## борта К КАМЕРЕ на 5·|b.z по земле|/b.z.y ≈ 8 м; точка на ней, если
## шаг от неё ОТ камеры на 0…8 м попадает на полотно. 23.10: юбку не
## учитывали — планета у ближнего борта заходила на неё и выглядела
## наехавшей на трассу (замечание игрока).
func _apparent_clear(p: Vector3, r: float, b: Basis) -> bool:
	var away := -Vector3(b.z.x, 0.0, b.z.z)
	var skirt := TrackBuilder.SPACE_SKIRT * away.length() / b.z.y
	away = away.normalized()
	for sp in _disc_dense(p, r, b):
		var g := _apparent(sp, b)
		for k in 3:
			var q := g + away * (skirt * 0.5 * k)
			if _track.distance_from_axis(q) < _track.half_width_at_pos(q) + 1.5:
				return false
	return true


## Какая наибольшая доля диска (шар с центром p и радиусом r, как он
## виден на экране) попадает в кадр ИГРОВОЙ камеры, стоящей над
## какой-нибудь точкой оси трассы (ширину окна считаем по узкому экрану,
## 1.6 высоты). Диск — 13 точек в плоскости экрана; точка не считается,
## если линия взгляда от неё к камере упирается в дорогу (для точки под
## дорогой линия выходит на уровень полотна в стороне +X+Z) или если она
## вне окна. Заслонение от положения камеры не зависит — считается один
## раз; проверяются точки оси в ±70 м от ближайшей к p (дальше окно не
## достаёт).
func _iso_visible(p: Vector3, r: float) -> float:
	var b := _iso_basis()
	var cam := IsoCamera.new()
	var half_h := cam.ortho_size * 0.5
	cam.free()
	var half_w := half_h * 1.6
	var samples := _disc_samples(p, r, b)
	var open: Array[Vector3] = []   # точки, не заслонённые дорогой
	for sp in samples:
		if sp.y < 0.0:
			var g := _apparent(sp, b)
			if _track.distance_from_axis(g) < _track.half_width_at_pos(g) + 1.0:
				continue
		open.append(sp)
	if open.is_empty():
		return 0.0
	var curve := _track._curve
	var length := curve.get_baked_length()
	var near := curve.get_closest_offset(p)
	var best := 0
	var off := -70.0
	while off <= 70.0:
		var q := curve.sample_baked(fposmod(near + off, length))
		var n := 0
		for sp in open:
			var d := sp - q
			if absf(d.dot(b.x)) < half_w and absf(d.dot(b.y)) < half_h:
				n += 1
		best = maxi(best, n)
		off += 2.0
	return float(best) / float(samples.size())


## Выключает тени у узла и всех его MeshInstance3D-потомков (фоновый
## декор космоса, см. _build_space).
static func _no_shadow(root: Node3D) -> void:
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).cast_shadow = 				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


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
	# FORWARD × UP = RIGHT. Прежнее «* -1» давало ЛЕВО, и щиты 3-2-1
	# вставали ВНУТРИ поворота; прочие потребители симметричны.
	return _forward(t).cross(Vector3.UP)


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


## Дальше этого от КРОМКИ полотна декор не виден: камера (IsoCamera, 60 м,
## −32°) показывает ~35 м земли по бокам от машины. Раньше россыпи
## сыпались по всему квадрату земли 400×400 м, и две трети деревьев,
## камней, кактусов стояли там, куда машина не попадает (жалоба 15.09).
const SCATTER_FAR := 34.0


## Случайная точка ВОЗЛЕ полотна: доля круга t, случайная сторона,
## отступ от кромки (полуширина в этом месте + обочина) в [near, far] м.
## Возвращает [точка, t]; высота по земле не выставлена (y = 0).
func _near_axis(rng: RandomNumberGenerator, near: float, far: float,
		outward_only := false) -> Array:
	var t := rng.randf()
	var side: Vector3
	if outward_only:
		side = _outward(t)
	else:
		side = _right(t) * (1.0 if rng.randf() < 0.5 else -1.0)
	var off := _half(t) + TrackBuilder.SHOULDER + rng.randf_range(near, far)
	var p := _axis(t) + side * off
	p.y = 0.0
	return [p, t]


## Точка p, поставленная от своего витка на отступ margin, не должна
## оказаться ближе margin к ДРУГОМУ витку (шпилька, соседние прямые).
func _clear_of_track(p: Vector3, margin: float) -> bool:
	var edge: float = _track.half_width_at_pos(p) + TrackBuilder.SHOULDER
	return _track.distance_from_axis(p) >= edge + margin - 0.5


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
		if mi.mesh == null:
			continue
		var ab := mi.global_transform * mi.mesh.get_aabb()
		for k in 8:
			closest = minf(closest,
					_track.distance_from_axis(ab.get_endpoint(k)))
	if closest < min_dist:
		node.position += out * (min_dist - closest)


func _occupy(p: Vector3, radius: float) -> void:
	_occupied.append(Vector3(p.x, p.z, radius))


## Занять круг по мировому габариту уже поставленного пропса: центр —
## середина AABB, радиус — половина большей стороны по XZ плюс pad.
## Для длинных моделей (трибуны) и моделей с якорем не в центре точка
## постановки + радиус «на глаз» не годятся.
func _occupy_node(node: Node3D, pad: float) -> void:
	var merged := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var ab := mi.global_transform * mi.mesh.get_aabb()
		merged = ab if first else merged.merge(ab)
		first = false
	if first:
		_occupy(node.position, 10.0)
		return
	var c := merged.get_center()
	_occupy(Vector3(c.x, 0, c.z), maxf(merged.size.x, merged.size.z) * 0.5 + pad)


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
		if mi.mesh == null:
			continue
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
		if mi.mesh == null:
			continue
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
