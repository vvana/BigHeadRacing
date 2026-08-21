class_name TrackBuilder
extends Node3D
## Процедурно строит кольцевую трассу с перепадами высот: рельефную землю,
## полотно дороги (с собственной коллизией), сплошное ограждение по краям,
## трамплины и финишный створ. Всё из кода, без внешних ассетов.

# Полотно переменной ширины (см. SEGMENTS): на прямых широкое, в шпильке
# и крутых поворотах узкое. TRACK_HALF_WIDTH — МАКСИМУМ: по нему считаются
# обочина, порог вылета и расстановка декора, чтобы в узких местах они
# просто отходили дальше от кромки, а не резали полотно.
const TRACK_HALF_WIDTH := 11.0  # максимальная полуширина полотна, м
const MIN_HALF_WIDTH := 6.0     # самое узкое место (шпилька), м
const WALL_HEIGHT := 2.6   # заметно выше высоты прыжка (~1.9 м) — не улететь
const WALL_THICKNESS := 0.5
const SAMPLES := 768            # детализация контура (сэмплов на круг)

const GROUND_SIZE := 400.0      # сторона квадрата земли, м
const GROUND_RES := 148         # ячеек земли по стороне
const SHOULDER := 5.0           # ширина ровной обочины у дороги, м
# Обочина лежит НИЖЕ полотна: сетка земли грубее дороги, и вровень её
# треугольники пробивались сквозь асфальт (z-fighting). Просвет прячет
# ограждение, продлённое вниз на ту же величину.
const GROUND_DROP := 1.2

var _curve := Curve3D.new()
# Предрассчитанные точки контура и векторы «вправо» в каждой из них.
var _pts := PackedVector3Array()
var _rights := PackedVector3Array()
var _widths := PackedFloat32Array()   # полуширина в каждом сэмпле
# Ключи ширины: [доля круга, полуширина]. Между ключами — плавный переход.
var _width_keys: Array[Vector2] = []
# Прямые участки как [доля начала, доля конца] — на них ставятся трамплины.
var _straights: Array[Vector2] = []


func _ready() -> void:
	_build_curve()
	_sample_frames()
	_build_ground()
	_build_road()
	_build_walls()
	_build_ramps()
	_build_start_line()
	_build_decor()


# Трасса РОВНАЯ ВЕЗДЕ, кроме одной горки (просьба пользователя
# 2026-08-21). Механика рельефа общая: HEIGHT_KEYS задаёт профиль, ему
# следуют полотно, ограждения, обочина и декор.
const FLAT_TRACK := false

## Профиль высот: одна ГОРКА и больше ничего. Пары [доля круга, высота];
## между ключами с РАЗНОЙ высотой — плавная S-кривая, с одинаковой —
## ровное место.
##
## Горка стоит на прямой 0.156…0.211 и симметрична относительно её
## середины: подъём и спуск по ~28 м, между ними короткий гребень.
## Почему именно тут: трамплины трасса ставит на серединах двух самых
## длинных прямых (_ramp_ratios → 0.564 и 0.722), и горка не должна с
## ними пересекаться — прыжок с трамплина на склоне непредсказуем.
## Стартовая прямая (0.000…0.064) тоже занята — там решётка и створ.
const HILL_TOP := 4.0          # высота гребня над остальной трассой, м
const HEIGHT_KEYS: Array = [
	[0.000, 0.0],
	[0.140, 0.0],       # подножие подъёма
	[0.178, HILL_TOP],  # заезд на гребень
	[0.190, HILL_TOP],  # гребень — короткое ровное плато
	[0.228, 0.0],       # спуск
	[1.000, 0.0],
]


## Высота по доле круга: внутри плато — константа, на переходах — плавная
## S-кривая (без изломов, но заметно круче синусоиды).
static func _profile_height(t: float) -> float:
	if FLAT_TRACK:
		return 0.0
	var f := fposmod(t, 1.0)
	for i in range(HEIGHT_KEYS.size() - 1):
		var t0: float = HEIGHT_KEYS[i][0]
		var t1: float = HEIGHT_KEYS[i + 1][0]
		if f >= t0 and f <= t1:
			var h0: float = HEIGHT_KEYS[i][1]
			var h1: float = HEIGHT_KEYS[i + 1][1]
			if is_equal_approx(h0, h1):
				return h0
			return lerpf(h0, h1, smoothstep(0.0, 1.0, (f - t0) / (t1 - t0)))
	return 0.0


## КОНФИГУРАЦИЯ ТРАССЫ — последовательность участков «черепахой»:
##   ["S", длина, полуширина_в_конце]           — прямая
##   ["A", радиус, угол°, полуширина_в_конце]   — дуга (+ вправо, − влево)
## Длина -1.0 у прямой = «свободная»: подбирается в _solve_free_lengths(),
## чтобы кольцо замкнулось ТОЧНО (см. там). Свободных должно быть ровно две,
## и их направления не должны быть параллельны.
##
## СУММА УГЛОВ ДУГ ОБЯЗАНА БЫТЬ ±360° — иначе на стыке будет излом.
## При правке углов пересчитать: сумма правых минус сумма левых = 360.
## Минимальный радиус ~19 м: он должен быть заметно больше полуширины в
## этом месте, иначе внутренняя кромка полотна схлопнется.
const SEGMENTS: Array = [
	["S", -1.0, 11.0],           # 0  СТАРТОВАЯ ПРЯМАЯ (свободная), широкая
	["A", 45.0, 85.0, 9.5],      # 1  быстрый правый
	["S", 40.0, 10.5],           # 2  короткая прямая
	["A", 28.0, -45.0, 8.0],     # 3  шикана: влево
	["A", 28.0, 45.0, 7.5],      # 4  шикана: вправо (сужается к шпильке)
	["S", 30.0, 7.0],            # 5  подход к шпильке — уже
	["A", 19.0, 150.0, 6.0],     # 6  ШПИЛЬКА — самое узкое место
	["S", 35.0, 9.0],            # 7  выход со шпильки, расширяется
	["A", 40.0, -85.0, 10.0],    # 8  длинный левый
	["S", -1.0, 11.0],           # 9  ДЛИННАЯ ПРЯМАЯ (свободная), широкая
	["A", 32.0, 95.0, 8.5],      # 10 средний правый
	["S", 45.0, 8.0],            # 11 прямая, сужается к крутому повороту
	["A", 26.0, 105.0, 6.5],     # 12 КРУТОЙ правый — узко
	["S", 28.0, 9.0],            # 13 выход, расширяется
	["A", 50.0, -65.0, 10.0],    # 14 пологий левый изгиб
	["A", 36.0, 75.0, 10.0],     # 15 выход на стартовую прямую
]

const TURTLE_STEP := 3.0   # шаг опорных точек вдоль трассы, м


## Замкнутый контур из прямых и дуг (см. SEGMENTS): настоящие прямые
## участки, крутые повороты и шпилька — вместо прежней «дышащей» окружности.
## Точки ставятся часто (TURTLE_STEP), касательные — строго по ходу
## движения: на прямых это даёт идеальную прямую, на дугах — точную дугу.
func _build_curve() -> void:
	var free_lens := _solve_free_lengths()
	var walk := _walk(free_lens)
	var points: Array[Vector3] = walk["points"]
	var dirs: Array[Vector3] = walk["dirs"]
	_width_keys = walk["width_keys"]
	_straights = walk["straights"]

	# Центрируем контур: «черепаха» стартует из нуля и уходит в сторону,
	# а земля/скайбокс построены вокруг начала координат.
	var lo := points[0]
	var hi := points[0]
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	var center := (lo + hi) * 0.5
	center.y = 0.0

	for i in points.size():
		var p := points[i] - center
		_curve.add_point(p)
		# Касательная безье длиной шаг/3 вдоль направления движения:
		# кубический сегмент тогда точно повторяет прямую или дугу.
		var t := dirs[i] * (TURTLE_STEP / 3.0)
		_curve.set_point_in(i, -t)
		_curve.set_point_out(i, t)
	# Curve3D.closed появился только в 4.4 — замыкаем дублем первой точки.
	_curve.add_point(points[0] - center)
	_curve.set_point_in(_curve.point_count - 1, -dirs[0] * (TURTLE_STEP / 3.0))
	_curve.set_point_out(_curve.point_count - 1, dirs[0] * (TURTLE_STEP / 3.0))


## Проход «черепахой» по SEGMENTS: точки оси, направления и ключи ширины.
## free_lens — длины двух свободных прямых (по порядку их появления).
func _walk(free_lens: Array) -> Dictionary:
	var pos := Vector3.ZERO
	var ang := 0.0          # курс в плане, рад
	var dist := 0.0         # пройденный путь, м
	var free_i := 0
	var points: Array[Vector3] = []
	var dirs: Array[Vector3] = []
	var keys: Array[Vector2] = []
	var raw_keys: Array[Vector2] = []   # [дистанция, полуширина]
	var straights: Array[Vector2] = []  # [дистанция начала, длина] прямых
	# Старт наследует ширину последнего участка — кольцо непрерывно.
	raw_keys.append(Vector2(0.0, SEGMENTS[SEGMENTS.size() - 1][-1]))

	for seg: Array in SEGMENTS:
		if seg[0] == "S":
			var length: float = seg[1]
			if length < 0.0:
				length = free_lens[free_i]
				free_i += 1
			var steps := maxi(1, int(round(length / TURTLE_STEP)))
			var dir := Vector3(cos(ang), 0.0, sin(ang))
			straights.append(Vector2(dist, length))
			for _s in steps:
				points.append(pos)
				dirs.append(dir)
				pos += dir * (length / steps)
				dist += length / steps
		else:
			var radius: float = seg[1]
			var sweep := deg_to_rad(float(seg[2]))
			var arc: float = radius * absf(sweep)
			var steps := maxi(2, int(round(arc / TURTLE_STEP)))
			var da := sweep / steps
			# Точки — строго на окружности радиуса R: касательная в точке
			# по ТЕКУЩЕМУ курсу, а шаг — по ХОРДЕ, которая идёт под
			# половиной угла шага. Если шагать по новому курсу (а
			# касательную писать по старому), точка и её касательная
			# расходятся на полшага, безье «водит» — эффективный радиус
			# получается меньше заданного, и трасса выходит изломанной.
			var chord: float = 2.0 * radius * sin(absf(da) * 0.5)
			for _s in steps:
				points.append(pos)
				dirs.append(Vector3(cos(ang), 0.0, sin(ang)))
				var mid := ang + da * 0.5
				pos += Vector3(cos(mid), 0.0, sin(mid)) * chord
				ang += da
				dist += arc / steps
		raw_keys.append(Vector2(dist, seg[-1]))

	# Ключи ширины — в долях круга (кривая печётся своей длиной).
	for k in raw_keys:
		keys.append(Vector2(k.x / dist, k.y))
	# Прямые тоже в долях: [доля начала, доля конца].
	var straight_ratios: Array[Vector2] = []
	for s in straights:
		straight_ratios.append(Vector2(s.x / dist, (s.x + s.y) / dist))

	# Профиль высот (сейчас плоско) — по доле круга.
	for i in points.size():
		points[i].y = _profile_height(float(i) / points.size())

	return {
		"points": points, "dirs": dirs, "width_keys": keys,
		"straights": straight_ratios,
	}


## Длины двух свободных прямых, при которых кольцо замыкается точно.
## Итоговое смещение ЛИНЕЙНО зависит от этих длин (углы фиксированы), так
## что достаточно решить систему 2×2 по трём пробным проходам.
func _solve_free_lengths() -> Array:
	var e0 := _closure_error([0.0, 0.0])
	var e1 := _closure_error([1.0, 0.0]) - e0
	var e2 := _closure_error([0.0, 1.0]) - e0
	var det := e1.x * e2.y - e2.x * e1.y
	if absf(det) < 1e-6:
		push_error("TrackBuilder: свободные прямые параллельны — не замкнуть")
		return [60.0, 60.0]
	var l1 := (-e0.x * e2.y + e2.x * e0.y) / det
	var l2 := (-e1.x * e0.y + e0.x * e1.y) / det
	if l1 < 5.0 or l2 < 5.0:
		push_error("TrackBuilder: конфигурация не замыкается (прямая < 5 м)")
	return [l1, l2]


## Насколько «не сошлись» концы кольца при заданных свободных длинах.
func _closure_error(free_lens: Array) -> Vector2:
	var walk := _walk(free_lens)
	var points: Array[Vector3] = walk["points"]
	var last: Vector3 = points[points.size() - 1]
	var first: Vector3 = points[0]
	# Последняя точка — начало последнего шага, поэтому добавляем сам шаг.
	var dirs: Array[Vector3] = walk["dirs"]
	last += dirs[dirs.size() - 1] * TURTLE_STEP
	return Vector2(last.x - first.x, last.z - first.z)


## Полуширина полотна на доле круга t (плавные переходы между участками).
func half_width_at_ratio(t: float) -> float:
	if _width_keys.is_empty():
		return TRACK_HALF_WIDTH
	var f := fposmod(t, 1.0)
	for i in range(_width_keys.size() - 1):
		var k0 := _width_keys[i]
		var k1 := _width_keys[i + 1]
		if f >= k0.x and f <= k1.x and k1.x > k0.x:
			return lerpf(k0.y, k1.y,
					smoothstep(0.0, 1.0, (f - k0.x) / (k1.x - k0.x)))
	return _width_keys[_width_keys.size() - 1].y


## Полуширина полотна в точке кривой (offset вдоль оси, м).
func half_width_at_offset(off: float) -> float:
	var length := _curve.get_baked_length()
	if length <= 0.0:
		return TRACK_HALF_WIDTH
	return half_width_at_ratio(off / length)


## Полуширина полотна напротив мировой точки — для порогов вылета,
## ведения у стены и т.п.
func half_width_at_pos(world_pos: Vector3) -> float:
	return half_width_at_offset(_curve.get_closest_offset(world_pos))


## Равномерно сэмплирует кривую: позиции и перпендикуляры к ходу трассы.
## «Вправо» держим горизонтальным — полотно без бокового наклона.
func _sample_frames() -> void:
	var length := _curve.get_baked_length()
	for i in SAMPLES:
		var off := length * i / SAMPLES
		var pos := _curve.sample_baked(off)
		var ahead := _curve.sample_baked(fmod(off + 0.5, length))
		var dir := (ahead - pos).normalized()
		_pts.append(pos)
		_rights.append(Vector3(dir.x, 0, dir.z).normalized().cross(Vector3.UP)
				* -1.0)
		_widths.append(half_width_at_ratio(float(i) / SAMPLES))


## Квад двумя треугольниками с заданной нормалью.
static func _add_quad(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	normal: Vector3
) -> void:
	st.set_normal(normal)
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


## Высота земли в точке: у трассы — вровень с полотном (ровная обочина),
## дальше плавно уходит вниз и переходит в пологие холмы.
func _ground_height(x: float, z: float) -> float:
	var p := Vector3(x, 0, z)
	var on_curve := _curve.sample_baked(_curve.get_closest_offset(p))
	var d := Vector2(x - on_curve.x, z - on_curve.z).length()
	var edge := TRACK_HALF_WIDTH + SHOULDER
	var base := on_curve.y - GROUND_DROP
	if d <= edge:
		return base
	# За обочиной — склон вниз и рельеф, нарастающий с удалением.
	var away := d - edge
	var blend: float = clampf(away / 22.0, 0.0, 1.0)
	var hills := sin(x * 0.045) * cos(z * 0.052) * 6.0 \
			+ sin((x + z) * 0.021) * 3.0
	return base - away * 0.28 + hills * blend


func _build_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var step := GROUND_SIZE / GROUND_RES
	var half := GROUND_SIZE * 0.5

	# Высоты считаем один раз в узлах сетки — иначе 4 запроса к кривой на ячейку.
	var h := []
	h.resize(GROUND_RES + 1)
	for ix in GROUND_RES + 1:
		var row := PackedFloat32Array()
		row.resize(GROUND_RES + 1)
		var x := -half + ix * step
		for iz in GROUND_RES + 1:
			row[iz] = _ground_height(x, -half + iz * step)
		h[ix] = row

	for ix in GROUND_RES:
		for iz in GROUND_RES:
			var x0 := -half + ix * step
			var x1 := x0 + step
			var z0 := -half + iz * step
			var z1 := z0 + step
			var a := Vector3(x0, h[ix][iz], z0)
			var b := Vector3(x1, h[ix + 1][iz], z0)
			var c := Vector3(x1, h[ix + 1][iz + 1], z1)
			var d := Vector3(x0, h[ix][iz + 1], z1)
			for v in [a, b, c, a, c, d]:
				# Планарная UV по миру: тайл травы 14 м.
				st.set_uv(Vector2(v.x, v.z) * 0.07)
				# Низкочастотная вариация яркости по вершинам ломает
				# видимую повторяемость тайла (пятна «одинаково
				# расположенные» бросались в глаза).
				var shade := 1.0 + 0.09 * sin(v.x * 0.113 + v.z * 0.071) \
						+ 0.06 * sin(v.x * 0.037 - v.z * 0.059 + 2.1)
				st.set_color(Color(shade, shade, shade))
				st.add_vertex(v)
			faces.append_array([a, b, c, a, c, d])
	st.generate_normals()

	var ground := StaticBody3D.new()
	ground.name = "Ground"

	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	# Зелёные поля — трава из Cartoon Tracks Pack (пятна текстуры
	# смягчены при конвертации, см. ПРОГРЕСС.md).
	mat.albedo_texture = load(
			"res://assets/models/track_env/cartoon/textures/grass_1.png")
	mat.vertex_color_use_as_albedo = true
	mesh.material_override = mat
	ground.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	col.shape = shape
	ground.add_child(col)

	add_child(ground)


## Полотно трассы: непрерывная лента по кривой с собственной коллизией —
## именно по ней едут машины (земля под ней может уходить вниз).
func _build_road() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var lift := Vector3(0, 0.05, 0)

	for i in SAMPLES:
		var j := (i + 1) % SAMPLES
		var li := _pts[i] - _rights[i] * _widths[i] + lift
		var ri := _pts[i] + _rights[i] * _widths[i] + lift
		var lj := _pts[j] - _rights[j] * _widths[j] + lift
		var rj := _pts[j] + _rights[j] * _widths[j] + lift
		var normal := (rj - li).cross(lj - ri).normalized()
		if normal.y < 0.0:
			normal = -normal
		_add_quad(st, li, ri, rj, lj, normal)
		faces.append_array([li, ri, rj, li, rj, lj])

	var body := StaticBody3D.new()
	body.name = "Road"

	var road := MeshInstance3D.new()
	road.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.18, 0.2)
	road.material_override = mat
	body.add_child(road)

	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	col.shape = shape
	body.add_child(col)

	add_child(body)


## Ограждение — два непрерывных «бортика» (внутренняя/внешняя грань + верх),
## коллизия — точная, по тем же треугольникам.
func _build_walls() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	# Юбка вниз: закрывает просвет между полотном и опущенной обочиной.
	var skirt := Vector3(0, GROUND_DROP + 0.4, 0)
	var top := Vector3(0, WALL_HEIGHT + skirt.y, 0)
	var half_t := WALL_THICKNESS * 0.5

	for side: float in [-1.0, 1.0]:
		for i in SAMPLES:
			var j := (i + 1) % SAMPLES
			var ni := _rights[i] * side
			var nj := _rights[j] * side
			var ci := _pts[i] + ni * _widths[i] - skirt
			var cj := _pts[j] + nj * _widths[j] - skirt
			var ai := ci - ni * half_t   # грань к трассе
			var bi := ci + ni * half_t   # внешняя грань
			var aj := cj - nj * half_t
			var bj := cj + nj * half_t

			var quads: Array = [
				[ai, ai + top, aj + top, aj, -ni],        # к трассе
				[bi, bi + top, bj + top, bj, ni],         # наружу
				[ai + top, bi + top, bj + top, aj + top, Vector3.UP],  # верх
			]
			for q: Array in quads:
				_add_quad(st, q[0], q[1], q[2], q[3], q[4])
				faces.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])

	var body := StaticBody3D.new()
	body.name = "Walls"
	body.add_to_group("walls")  # Car._wall_slide узнаёт стену по группе
	# Слой 2: кузов со стенами сталкивается (mask машины включает 2),
	# а ЛУЧИ ПОДВЕСКИ стены не видят (mask 1) — иначе колёса «едут»
	# по вертикальной стене как по дороге.
	body.collision_layer = 2
	# Стены не упругие: машина не отскакивает, а выравнивается вдоль
	# ограждения и скользит (см. Car._wall_slide).
	body.physics_material_override = PhysicsMaterial.new()
	body.physics_material_override.bounce = 0.0
	body.physics_material_override.friction = 0.1

	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.2, 0.15)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	col.shape = shape
	body.add_child(col)

	add_child(body)


## Доли круга для трамплинов: середины двух самых длинных прямых, кроме
## стартовой (первый участок, там стартовая решётка и финишный створ).
func _ramp_ratios() -> Array:
	var pool := _straights.slice(1)
	pool.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			return (a.y - a.x) > (b.y - b.x))
	var res: Array = []
	for i in mini(2, pool.size()):
		res.append((pool[i].x + pool[i].y) * 0.5)
	return res


## Пара трамплинов на прямых участках — для фирменных прыжков.
func _build_ramps() -> void:
	var ramp_mat := StandardMaterial3D.new()
	ramp_mat.albedo_color = Color(0.9, 0.75, 0.1)

	var length := _curve.get_baked_length()
	# Трамплины — посреди самых длинных ПРЯМЫХ (кроме стартовой, где стоит
	# решётка): на дуге трамплин сбрасывал бы машину в ограждение.
	for t: float in _ramp_ratios():
		var offset := length * t
		var pos := _curve.sample_baked(offset)
		var ahead := _curve.sample_baked(fmod(offset + 2.0, length))
		var dir := (ahead - pos).normalized()

		var ramp := StaticBody3D.new()
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(6.0, 0.4, 5.0)
		mesh.mesh = box
		mesh.material_override = ramp_mat
		ramp.add_child(mesh)

		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size
		col.shape = shape
		ramp.add_child(col)

		ramp.position = pos + Vector3(0, 0.4, 0)
		add_child(ramp)
		ramp.look_at(ramp.position + dir)
		ramp.rotate_object_local(Vector3.RIGHT, deg_to_rad(9.0))  # наклон-трамплин


## Стартово-финишный створ: шахматная клетка на полотне. Арка, баннер и
## стартовые огни — модели из ассетов (см. TrackDecor). Коллизий нет.
func _build_start_line() -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.94, 0.94, 0.94)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.08, 0.08, 0.09)

	var pos := _curve.sample_baked(0.0)
	var ahead := _curve.sample_baked(2.0)
	var gate := Node3D.new()
	gate.name = "FinishGate"
	add_child(gate)
	gate.position = pos
	gate.look_at(pos + (ahead - pos).normalized())

	# Шахматная лента на асфальте: 14 клеток поперёк × 2 ряда вдоль.
	# Ширина — фактическая в точке старта (полотно переменной ширины).
	var half := half_width_at_offset(0.0)
	var cols := 14
	var cell := half * 2.0 / cols
	for row in 2:
		for c in cols:
			var tile := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(cell, 0.06, cell)
			tile.mesh = box
			tile.material_override = white if (c + row) % 2 == 0 else black
			tile.position = Vector3(
				-half + cell * (c + 0.5), 0.09, (row - 0.5) * cell)
			gate.add_child(tile)


## Декор из готовых ассетов — отдельным узлом (см. TrackDecor.gd).
func _build_decor() -> void:
	TrackDecor.new().build(self)


## Горизонтальное расстояние от точки до оси трассы (для детекта вылета).
func distance_from_axis(world_pos: Vector3) -> float:
	var p := _curve.sample_baked(_curve.get_closest_offset(world_pos))
	return Vector2(world_pos.x - p.x, world_pos.z - p.z).length()


## Точка старта и направление для спавна машины.
func start_transform() -> Transform3D:
	var pos := _curve.sample_baked(0.0)
	var ahead := _curve.sample_baked(3.0)
	var dir := (ahead - pos).normalized()
	var basis := Basis.looking_at(dir)
	# 0.62 м — примерно на длину покоя подвески, чтобы машина не падала
	# с высоты и не подпрыгивала при появлении.
	return Transform3D(basis, pos + Vector3(0, 0.62, 0))


## Точка респавна: ось трассы на 6 м вперёд от ближайшей к world_pos точки
## (вперёд — чтобы не вернуть машину в ту же ловушку, где она застряла,
## например прямо на трамплин).
func respawn_transform(world_pos: Vector3) -> Transform3D:
	var length := _curve.get_baked_length()
	var offset := fposmod(_curve.get_closest_offset(world_pos) + 6.0, length)
	var pos := _curve.sample_baked(offset)
	var ahead := _curve.sample_baked(fposmod(offset + 3.0, length))
	var basis := Basis.looking_at((ahead - pos).normalized())
	# 0.62 м — примерно на длину покоя подвески, чтобы машина не падала
	# с высоты и не подпрыгивала при появлении.
	return Transform3D(basis, pos + Vector3(0, 0.62, 0))
