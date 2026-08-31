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
# Детализация контура. Стены и полотно — тримеши из плоских фасеток; на
# стыках фасеток кузов ловит рёбра (машину «пинает» у ограждений и на
# склонах). 1536 сэмплов ≈ 0.5 м на сегмент: излом на стыке вдвое меньше,
# чем при прежних 768, — скольжение вдоль стены и переезд склонов заметно
# глаже. Меши статические, стройка и физика удвоение переносят легко.
const SAMPLES := 1536           # детализация контура (сэмплов на круг)

const GROUND_SIZE := 400.0      # сторона квадрата земли, м
const GROUND_RES := 148         # ячеек земли по стороне
const SHOULDER := 5.0           # ширина ровной обочины у дороги, м
# Обочина лежит НИЖЕ полотна: сетка земли грубее дороги, и вровень её
# треугольники пробивались сквозь асфальт (z-fighting). Просвет прячет
# ограждение, продлённое вниз на ту же величину.
const GROUND_DROP := 1.2

# ---------- Виды трасс ----------
# Трасса на заезд выбирается СЛУЧАЙНО (оффлайн — гараж, по сети — сервер,
# см. Main._pick_track_kind). Тесты, грузящие Main напрямую, ничего не
# выбирают и получают классику — регрессия детерминирована.
const KIND_GRASS := "grass"   # классика: трава, ограждения, горка
const KIND_SAND := "sand"     # пустыня: песок, БЕЗ ограждений, съезд разрешён
const KIND_NEON := "neon"     # ночной город: тёмный асфальт, неон на стенах
const KIND_SPACE := "space"   # космос: трасса среди звёзд, планеты вокруг
const KINDS: Array[String] = [KIND_GRASS, KIND_SAND, KIND_NEON, KIND_SPACE]
# Насколько дальше кромки полотна пускает автовозврат на песке: съезд на
# песок — легальная (медленная) езда, возвращаем только уехавших в дюны.
const SAND_OFFTRACK_MARGIN := 12.0

## Вид трассы. Выставить ДО добавления узла в дерево (читается в _ready).
var kind := KIND_GRASS
## Есть ли ограждения. Читают Car (_wall_slide) и Main (порог вылета).
var has_walls := true
## Запас до автовозврата за кромкой полотна (см. Main._check_recovery).
var offtrack_margin := 0.5
var _segments: Array = []     # конфигурация участков (ставится в _ready)
var _ground_drop := GROUND_DROP


static func pick_random_kind() -> String:
	return KINDS[randi() % KINDS.size()]


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
	_segments = segments_for(kind)
	if kind == KIND_SAND:
		has_walls = false
		offtrack_margin = SAND_OFFTRACK_MARGIN
		# Без стен просвет между полотном и землёй нечем прятать — обочина
		# идёт почти вровень (полотно приподнято на 0.05, ступенька 0.10 м
		# проезжается незаметно, а z-fighting'а нет — поверхности не совпадают).
		_ground_drop = 0.05
	_build_curve()
	_sample_frames()
	_build_ground()
	_build_road()
	if has_walls:
		_build_walls()
		# Светящиеся трубки по верху ограждений: фирменный вид ночного
		# города, у космической трассы — свои цвета (см. _build_neon_strips).
		if (kind == KIND_NEON or kind == KIND_SPACE) and not _headless_server():
			_build_neon_strips()
	_build_ramps()
	_build_boost_pads()
	_build_start_line()
	_build_decor()


# Трасса РОВНАЯ ВЕЗДЕ, кроме одной горки (просьба пользователя
# 2026-08-21). Механика рельефа общая: HEIGHT_KEYS задаёт профиль, ему
# следуют полотно, ограждения, обочина и декор.
const FLAT_TRACK := false

## Работаем ли выделенным сервером. Смотрим КОМАНДНУЮ СТРОКУ, а не autoload
## Net, и вот почему: TrackBuilder используется ещё и в стендах, запускаемых
## через `--script` (tools/test_curve.gd), а в режиме --script autoload'ы НЕ
## загружаются. Обращение к Net там роняет компиляцию скрипта, стенд молча
## ВИСНЕТ, и ошибка видна только в stderr. Ключ `-- --server` — то же самое
## условие, что проверяет Net.wants_server().
static func _headless_server() -> bool:
	return OS.get_cmdline_user_args().has("--server")


## Прицепить КОСМЕТИЧЕСКИЙ меш к телу. На выделенном сервере не цепляет:
## коллизия — отдельный дочерний узел, физике меш не нужен, а headless-рендер
## на каждый меш пишет в stderr «Parameter m is null» (см. _build_decor).
func _add_visual(body: Node, mesh: MeshInstance3D) -> void:
	if _headless_server():
		mesh.queue_free()
		return
	body.add_child(mesh)


## Профиль высот: одна ГОРКА и больше ничего. Пары [доля круга, высота];
## между ключами с РАЗНОЙ высотой — плавная S-кривая, с одинаковой —
## ровное место.
##
## Горка симметрична относительно середины прямой 0.156…0.211: подъём и
## спуск по ~42 м (пологие — на подъёме уклон ≤ 18%), между ними короткий
## гребень. Переходы шире самой прямой и захватывают края соседних дуг —
## это нормально, профиль применяется к оси в любом месте.
## Почему именно тут: трамплины трасса ставит на серединах двух самых
## длинных прямых (_ramp_ratios → 0.564 и 0.722), и горка не должна с
## ними пересекаться — прыжок с трамплина на склоне непредсказуем.
## Стартовая прямая (0.000…0.064) тоже занята — там решётка и створ.
const HILL_TOP := 4.0          # высота гребня над остальной трассой, м
const HEIGHT_KEYS: Array = [
	[0.000, 0.0],
	[0.122, 0.0],       # подножие подъёма
	[0.180, HILL_TOP],  # заезд на гребень
	[0.188, HILL_TOP],  # гребень — короткое ровное плато
	[0.246, 0.0],       # спуск
	[1.000, 0.0],
]


## Квинтическая S-кривая (smootherstep). В отличие от smoothstep у неё на
## концах нулевая и ВТОРАЯ производная: кривизна профиля входит и выходит
## плавно, без скачка вертикального ускорения на границах плато — раньше
## именно на подножии/гребне подвеска получала ступеньку нагрузки и кузов
## цеплял рёбра фасеток полотна.
static func _ease_quintic(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


## Высота по доле круга: внутри плато — константа, на переходах — плавная
## квинтическая S-кривая (см. _ease_quintic).
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
			return lerpf(h0, h1, _ease_quintic((f - t0) / (t1 - t0)))
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

## ПЕСЧАНАЯ трасса (kind == KIND_SAND): плоская пустыня без ограждений.
## Длина 685 м — сопоставима с классикой (727). Те же правила: сумма углов
## дуг ±360°, ровно две свободные прямые с непараллельными направлениями.
## Конфигурация подобрана перебором с проверкой замыкания (обе свободные
## длины положительные: 44 и 72 м) и отсутствия сближения витков < 26 м.
## Сумма углов: правые 50+110+50+135+125+30 = 500, левые 55+85 = 140 → 360. ✓
## Полотно ШИРЕ классики (просьба пользователя 2026-08-25): полуширины
## 9…11 м (максимум = TRACK_HALF_WIDTH). Витки сближаются не ближе 26 м
## по осям, так что даже при 11+11 полотна не слипаются (зазор ≥ 4 м).
const SEGMENTS_SAND: Array = [
	["S", -1.0, 11.0],           # 0  СТАРТОВАЯ ПРЯМАЯ (свободная, ~44 м)
	["A", 20.0, 50.0, 9.0],      # 1  тесный правый сразу за стартом
	["S", 30.0, 10.0],           # 2  короткая прямая
	["A", 36.0, -55.0, 10.0],    # 3  левый
	["A", 46.0, 110.0, 10.5],    # 4  размашистый правый
	["S", -1.0, 11.0],           # 5  ДЛИННАЯ ПРЯМАЯ (свободная, ~72 м)
	["A", 46.0, 50.0, 11.0],     # 6  быстрый правый
	["S", 30.0, 10.0],           # 7  прямая
	["A", 44.0, 135.0, 9.5],     # 8  длинная правая дуга
	["A", 40.0, -85.0, 10.0],    # 9  левый
	["S", 30.0, 10.5],           # 10 прямая
	["A", 50.0, 125.0, 11.0],    # 11 широкий правый
	["A", 50.0, 30.0, 11.0],     # 12 выход на стартовую прямую
]

## НОЧНОЙ ГОРОД (kind == KIND_NEON): улицы с «перекрёстками» — почти все
## повороты прямоугольные (90°), плоско, ограждения ЕСТЬ (тёмные, с
## неоновыми трубками поверху — см. _build_neon_strips). Длина 703 м —
## сопоставима с классикой (727) и песком (685). Конфигурация подобрана
## численным перебором (как песчаная): замыкание точное, обе свободные
## прямые положительные (~103 и ~107 м), витки не сближаются ближе 30 м,
## габарит 247×189 м. Сумма углов: правые 90+90+60+90+45+120 = 495,
## левые 90+45 = 135 → 495−135 = 360. ✓
const SEGMENTS_NEON: Array = [
	["S", -1.0, 10.5],           # 0  СТАРТОВЫЙ ПРОСПЕКТ (свободная, ~103 м)
	["A", 27.0, 90.0, 9.0],      # 1  прямоугольный правый (перекрёсток)
	["S", 32.0, 9.5],            # 2  квартал
	["A", 30.0, -90.0, 8.5],     # 3  прямоугольный левый
	["S", 35.0, 8.0],            # 4  улица поуже
	["A", 20.0, 90.0, 7.5],      # 5  тесный правый угол
	["A", 25.0, 60.0, 7.0],      # 6  сразу доворот — «срезанный квартал»
	["S", -1.0, 10.5],           # 7  ДЛИННЫЙ ПРОСПЕКТ (свободная, ~107 м)
	["A", 36.0, 90.0, 9.0],      # 8  широкий правый
	["S", 63.0, 8.5],            # 9  прямая с шиканой на выходе
	["A", 26.0, -45.0, 8.0],     # 10 шикана: влево
	["A", 26.0, 45.0, 8.5],      # 11 шикана: вправо
	["S", 51.0, 8.5],            # 12 прямая
	["A", 32.0, 120.0, 10.5],    # 13 размашистый выход на стартовый проспект
]

## КОСМОС (kind == KIND_SPACE): «орбитальное шоссе» — две длинные прямые
## (~110 и ~117 м) и размашистые дуги, одна тесная связка. Плоско,
## ограждения ЕСТЬ (за ними пустота со звёздами — падать некуда), по верху
## стен светящиеся полосы (см. _build_neon_strips, у космоса свои цвета).
## Длина 746 м — сопоставима с классикой (727). Конфигурация подобрана
## численным перебором (как песок и неон): замыкание точное, свободные
## прямые 109.5 и 117.0 м, витки не сближаются ближе 39 м, габарит
## 244×205 м. Сумма углов: правые 60+90+90+125+130 = 495,
## левые 50+85 = 135 → 495−135 = 360. ✓
const SEGMENTS_SPACE: Array = [
	["S", -1.0, 11.0],           # 0  СТАРТОВАЯ ПРЯМАЯ (свободная, ~110 м)
	["A", 48.0, 60.0, 10.0],     # 1  быстрый правый
	["S", 34.0, 9.0],            # 2  короткая прямая
	["A", 26.0, 90.0, 7.5],      # 3  прямоугольный правый
	["S", -1.0, 10.5],           # 4  ДЛИННАЯ ПРЯМАЯ (свободная, ~117 м)
	["A", 30.0, -50.0, 9.0],     # 5  левый
	["A", 44.0, 90.0, 11.0],     # 6  широкий правый
	["S", 46.0, 9.0],            # 7  прямая к тесной связке
	["A", 23.0, 125.0, 6.5],     # 8  ТЕСНАЯ СВЯЗКА — самое узкое место
	["S", 38.0, 9.5],            # 9  выход
	["A", 38.0, -85.0, 10.0],    # 10 длинный левый
	["A", 48.0, 130.0, 11.0],    # 11 размашистый выход на стартовую прямую
]

const TURTLE_STEP := 3.0   # шаг опорных точек вдоль трассы, м


## Конфигурация участков для вида трассы (общая точка правды: _ready и
## tools/test_curve.gd берут сегменты отсюда).
static func segments_for(kind_: String) -> Array:
	match kind_:
		KIND_SAND:
			return SEGMENTS_SAND
		KIND_NEON:
			return SEGMENTS_NEON
		KIND_SPACE:
			return SEGMENTS_SPACE
		_:
			return SEGMENTS


## Высота оси для ЭТОЙ трассы: классика — профиль с горкой, остальные
## (песок, ночной город, космос) — плоско; рельеф только на земле за полотном.
func _height_at(t: float) -> float:
	return _profile_height(t) if kind == KIND_GRASS else 0.0


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
	raw_keys.append(Vector2(0.0, _segments[_segments.size() - 1][-1]))

	for seg: Array in _segments:
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

	# Профиль высот — по доле круга (у песчаной трассы плоско).
	for i in points.size():
		points[i].y = _height_at(float(i) / points.size())

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
			# Квинтика и здесь: у smoothstep на границах ключей скачок
			# кривизны — линия ограждения получала едва заметный излом,
			# о который стукался скользящий вдоль стены кузов.
			return lerpf(k0.y, k1.y,
					_ease_quintic((f - k0.x) / (k1.x - k0.x)))
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


## Вектор «вправо» полотна у отметки off — из предрассчитанных кадров
## (_rights горизонтальны, полотно без бокового крена). Для расстановки
## бонусов/ускорителей со смещением от оси.
func right_at_offset(off: float) -> Vector3:
	if _rights.is_empty():
		return Vector3.RIGHT
	var length := _curve.get_baked_length()
	if length <= 0.0:
		return Vector3.RIGHT
	var i := int(roundf(fposmod(off, length) / length * SAMPLES)) % SAMPLES
	return _rights[i]


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
	var base := on_curve.y - _ground_drop
	if d <= edge:
		return base
	# За обочиной — склон вниз и рельеф, нарастающий с удалением.
	# На песке склон и «дюны» гораздо мягче: по песку РАЗРЕШЕНО ездить
	# (медленно), рельеф должен быть проезжаемым, а не каньоном.
	var away := d - edge
	var blend: float = clampf(away / 22.0, 0.0, 1.0)
	var hills := sin(x * 0.045) * cos(z * 0.052) * 6.0 \
			+ sin((x + z) * 0.021) * 3.0
	if kind == KIND_SAND:
		return base - away * 0.05 + hills * 0.35 * blend
	if kind == KIND_NEON:
		# Город: пустыри почти плоские — на них стоят здания (TrackDecor).
		return base - away * 0.03 + hills * 0.15 * blend
	if kind == KIND_SPACE:
		# Космос: за обочиной «пустота» уходит вниз — трасса читается как
		# парящая платформа (земля есть, но она чёрная в звёздах и ниже;
		# страховка возврата работает как всюду).
		return base - away * 0.35 + hills * 0.3 * blend
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
				# Планарная UV по миру: тайл травы 14 м; у космоса тайл
				# звёздного поля 50 м — повтор звёзд не бросается в глаза.
				st.set_uv(Vector2(v.x, v.z)
						* (0.02 if kind == KIND_SPACE else 0.07))
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
	if kind == KIND_SAND:
		# Пустыня: гравий из того же пака, тонированный в песок (средний
		# цвет текстуры (135,118,89) — тянем к тёплому песочному).
		mat.albedo_texture = load(
				"res://assets/models/track_env/cartoon/textures/gravel.png")
		mat.albedo_color = Color(1.45, 1.32, 1.05)
	elif kind == KIND_NEON:
		# Ночной город: тот же гравий, но затемнённый в холодный бетон.
		mat.albedo_texture = load(
				"res://assets/models/track_env/cartoon/textures/gravel.png")
		mat.albedo_color = Color(0.30, 0.33, 0.44)
	elif kind == KIND_SPACE:
		# Космос: земля — сама «пустота», чёрно-синее поле со звёздами и
		# пятнами туманностей (текстура печётся кодом). UNSHADED — звёзды
		# видны независимо от тусклого космического освещения.
		mat.albedo_texture = _space_ground_texture()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		# Зелёные поля — трава из Cartoon Tracks Pack (пятна текстуры
		# смягчены при конвертации, см. ПРОГРЕСС.md).
		mat.albedo_texture = load(
				"res://assets/models/track_env/cartoon/textures/grass_1.png")
	mat.vertex_color_use_as_albedo = true
	mesh.material_override = mat
	_add_visual(ground, mesh)

	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	col.shape = shape
	ground.add_child(col)

	add_child(ground)


## Звёздное поле для земли космической трассы: чёрно-синяя пустота, пятна
## туманностей и россыпь звёзд. Тайлится (края без швов — звёзды не ставим
## вплотную к кромке, туманности гаснут к краям блоба). Зерно фиксировано —
## трасса всегда одинаковая.
static func _space_ground_texture() -> ImageTexture:
	const S := 512
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260831
	var img := Image.create(S, S, false, Image.FORMAT_RGB8)
	img.fill(Color(0.012, 0.012, 0.035))
	# Туманности: мягкие радиальные пятна, складываются с фоном.
	for _n in 5:
		var cx := rng.randf_range(60, S - 60)
		var cy := rng.randf_range(60, S - 60)
		var r := rng.randf_range(45.0, 90.0)
		var tint := Color(0.10, 0.03, 0.16) if rng.randf() < 0.5 \
				else Color(0.03, 0.07, 0.16)
		for py in range(maxi(0, int(cy - r)), mini(S, int(cy + r))):
			for px in range(maxi(0, int(cx - r)), mini(S, int(cx + r))):
				var d := Vector2(px - cx, py - cy).length() / r
				if d >= 1.0:
					continue
				var k := (1.0 - d) * (1.0 - d)
				var c := img.get_pixel(px, py)
				img.set_pixel(px, py, Color(
						c.r + tint.r * k, c.g + tint.g * k, c.b + tint.b * k))
	# Звёзды: белые, голубые и тёплые, часть — «крупные» крестики 3 px.
	for _i in 420:
		var x := rng.randi_range(2, S - 3)
		var y := rng.randi_range(2, S - 3)
		var b := rng.randf_range(0.35, 1.0)
		var c := Color(b, b, b)
		var roll := rng.randf()
		if roll < 0.2:
			c = Color(b * 0.7, b * 0.85, b)        # голубоватая
		elif roll < 0.35:
			c = Color(b, b * 0.9, b * 0.65)        # тёплая
		img.set_pixel(x, y, c)
		if rng.randf() < 0.12:
			var half := c * 0.55
			img.set_pixel(x + 1, y, half)
			img.set_pixel(x - 1, y, half)
			img.set_pixel(x, y + 1, half)
			img.set_pixel(x, y - 1, half)
	return ImageTexture.create_from_image(img)


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
	# Классика — тёмный асфальт; пустыня — укатанный песок (темнее рыхлого
	# вокруг, чтобы полотно читалось); ночной город — почти чёрный асфальт,
	# на котором неон и разметка горят контрастнее.
	match kind:
		KIND_SAND:
			mat.albedo_color = Color(0.64, 0.53, 0.36)
		KIND_NEON:
			mat.albedo_color = Color(0.09, 0.09, 0.12)
		KIND_SPACE:
			# Космос: сине-фиолетовое «покрытие станции», чуть светлее
			# пустоты вокруг — полотно читается на фоне звёзд.
			mat.albedo_color = Color(0.13, 0.13, 0.22)
		_:
			mat.albedo_color = Color(0.18, 0.18, 0.2)
	road.material_override = mat
	_add_visual(body, road)

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
	# Классика — красные борта; ночной город и космос — тёмные (светящиеся
	# полосы поверху добавляет _build_neon_strips).
	match kind:
		KIND_NEON:
			mat.albedo_color = Color(0.10, 0.10, 0.16)
		KIND_SPACE:
			mat.albedo_color = Color(0.14, 0.12, 0.24)
		_:
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


## Неоновые «трубки» по верху обоих ограждений ночного города: лента
## высотой 0.18 м (верх + две боковые грани) поверх стены. Чистая
## косметика без коллизий: UNSHADED + эмиссия — в ночном окружении с
## включённым glow (см. Main._setup_environment) трубки светятся.
## Внутренний борт голубой, внешний — маджента: стороны различимы боковым
## зрением, как цветовая подсказка «куда поворачивать».
func _build_neon_strips() -> void:
	var colors := {-1.0: Color(0.15, 0.9, 1.0), 1.0: Color(1.0, 0.2, 0.85)}
	if kind == KIND_SPACE:
		# Космос: зелёный внутренний борт, фиолетовый внешний — своя пара
		# цветов, чтобы трасса не путалась с ночным городом.
		colors = {-1.0: Color(0.3, 1.0, 0.55), 1.0: Color(0.65, 0.4, 1.0)}
	const STRIP_H := 0.18
	var half_t := WALL_THICKNESS * 0.5 + 0.06
	for side: float in [-1.0, 1.0]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# Низ ленты чуть утоплен в стену — нет щели и z-fighting с верхом.
		var base := Vector3(0, WALL_HEIGHT - 0.02, 0)
		var up := Vector3(0, STRIP_H, 0)
		for i in SAMPLES:
			var j := (i + 1) % SAMPLES
			var ni := _rights[i] * side
			var nj := _rights[j] * side
			var ci := _pts[i] + ni * _widths[i] + base
			var cj := _pts[j] + nj * _widths[j] + base
			var ai := ci - ni * half_t
			var bi := ci + ni * half_t
			var aj := cj - nj * half_t
			var bj := cj + nj * half_t
			_add_quad(st, ai + up, bi + up, bj + up, aj + up, Vector3.UP)
			_add_quad(st, ai, ai + up, aj + up, aj, -ni)
			_add_quad(st, bi, bi + up, bj + up, bj, ni)
		var mesh := MeshInstance3D.new()
		mesh.mesh = st.commit()
		var mat := StandardMaterial3D.new()
		var c: Color = colors[side]
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = c
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = 2.2
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.material_override = mat
		add_child(mesh)


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
	if kind == KIND_NEON or kind == KIND_SPACE:
		# В темноте жёлтый трамплин без подсветки — чёрный кирпич: эмиссия.
		ramp_mat.emission_enabled = true
		ramp_mat.emission = Color(1.0, 0.7, 0.15)
		ramp_mat.emission_energy_multiplier = 1.1

	var length := _curve.get_baked_length()
	# Трамплины — посреди самых длинных ПРЯМЫХ (кроме стартовой, где стоит
	# решётка): на дуге трамплин сбрасывал бы машину в ограждение.
	# Стоят НЕ строго по центру: сдвиг к борту, стороны чередуются —
	# прыжок ПО ЖЕЛАНИЮ. Сдвиг крупный (≥ полтрамплина + полкорпуса):
	# едущий по оси минует трамплин ЦЕЛИКОМ — частичный наезд на боковую
	# кромку подбрасывал бы машину набок.
	var side := 1.0
	for t: float in _ramp_ratios():
		var offset := length * t
		var lateral := side \
				* maxf(0.0, minf(4.6, half_width_at_offset(offset) - 3.4))
		side = -side
		var pos := _curve.sample_baked(offset) \
				+ right_at_offset(offset) * lateral
		var ahead := _curve.sample_baked(fmod(offset + 2.0, length))
		var dir := (ahead - _curve.sample_baked(offset)).normalized()

		var ramp := StaticBody3D.new()
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(6.0, 0.4, 5.0)
		mesh.mesh = box
		mesh.material_override = ramp_mat
		_add_visual(ramp, mesh)

		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size
		col.shape = shape
		ramp.add_child(col)

		ramp.position = pos + Vector3(0, 0.4, 0)
		add_child(ramp)
		ramp.look_at(ramp.position + dir)
		ramp.rotate_object_local(Vector3.RIGHT, deg_to_rad(9.0))  # наклон-трамплин


## Отметки ускорителей вдоль оси (м) и их боковые смещения (м, вправо
## положительно) — для тестов и стендов.
var boost_pad_offsets := PackedFloat32Array()
var boost_pad_laterals := PackedFloat32Array()


## Ускорители — В НАЧАЛЕ прямых участков (наехал — буст, выгодно именно
## перед прямой). Совсем короткие прямые пропускаем, стартовую тоже: там
## решётка, створ и отсчёт. Плиты стоят НЕ по центру: сдвиг к борту,
## стороны чередуются — к бонусу надо целиться. Длинная прямая (> 55 м)
## получает ВТОРУЮ плиту дальше по ходу у другого борта. Плиты есть и на
## сервере (срабатывание — его зона ответственности), косметику BoostPad
## сам не строит в headless.
func _build_boost_pads() -> void:
	var length := _curve.get_baked_length()
	var side := 1.0
	for s: Vector2 in _straights:
		if s.x <= 0.001:
			continue   # стартовая прямая
		var run := (s.y - s.x) * length
		if run < 25.0:
			continue
		var offs: Array[float] = [fposmod(s.x * length + 6.0, length)]
		if run > 55.0:
			offs.append(fposmod(s.x * length + run * 0.6, length))
		for off: float in offs:
			# Плита 3 м шириной: смещение так, чтобы целиком осталась
			# на полотне с запасом (полуширина минус полплиты и кромка).
			var lateral := side \
					* maxf(0.0, minf(3.2, half_width_at_offset(off) - 2.6))
			side = -side
			var axis_pos := _curve.sample_baked(off)
			var ahead := _curve.sample_baked(fmod(off + 2.0, length))
			var pad := BoostPad.new()
			add_child(pad)
			pad.position = axis_pos + right_at_offset(off) * lateral \
					+ Vector3(0, 0.05, 0)
			pad.look_at(pad.position + (ahead - axis_pos).normalized())
			boost_pad_offsets.append(off)
			boost_pad_laterals.append(lateral)


## Стартово-финишный створ: шахматная клетка на полотне. Арка, баннер и
## стартовые огни — модели из ассетов (см. TrackDecor). Коллизий нет,
## поэтому на сервере не строится вовсе (см. _build_decor).
func _build_start_line() -> void:
	if _headless_server():
		return
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
## Выделенному серверу КОСМЕТИКА не нужна: он ничего не рисует. И не просто
## не нужна, а мешает — headless-рендер на каждый меш сыпет в stderr
## «Parameter m is null», journald ловит тысячи строк за секунду, включает
## rate limit и выбрасывает ВСЁ, включая наши [net]-сообщения: лог сервера
## становится бесполезным. Плюс лишние меши на однопроцессорной VDS.
func _build_decor() -> void:
	if _headless_server():
		return
	TrackDecor.new().build(self)


## Ось трассы в плане (X,Z) и полуширина полотна в тех же точках — для
## мини-карты. step — через сколько сэмплов брать точку (SAMPLES на круг).
func plan_samples(step := 8) -> Dictionary:
	var pts := PackedVector2Array()
	var half := PackedFloat32Array()
	var i := 0
	while i < _pts.size():
		pts.append(Vector2(_pts[i].x, _pts[i].z))
		half.append(_widths[i])
		i += step
	return {"points": pts, "half": half}


## Горизонтальное расстояние от точки до оси трассы (для детекта вылета).
func distance_from_axis(world_pos: Vector3) -> float:
	var p := _curve.sample_baked(_curve.get_closest_offset(world_pos))
	return Vector2(world_pos.x - p.x, world_pos.z - p.z).length()


## То же, но от ЗАРАНЕЕ ИЗВЕСТНОЙ отметки (см. closest_offset_near): для
## машины, которая уже уехала от полотна, глобальный поиск врёт.
func distance_from_axis_at(world_pos: Vector3, off: float) -> float:
	var p := _curve.sample_baked(fposmod(off, _curve.get_baked_length()))
	return Vector2(world_pos.x - p.x, world_pos.z - p.z).length()


# ─────────── ОТМЕТКА НА ОСИ ПО НЕПРЕРЫВНОСТИ ───────────
# Curve3D.get_closest_offset ищет ближайшую точку по ВСЕЙ кривой. Пока
# машина на полотне, это ровно то, что нужно. Но кольцо подходит само к
# себе (замер tools/LoopGap.tscn: 53 м на классике, 43 м на неоне, 55 м на
# песке между участками, разнесёнными по ходу гонки на сотни метров), и
# машине достаточно улететь за ограждение или проехать по песку пару
# секунд — ближайшим станет ЧУЖОЙ участок кольца. Тогда:
#   • респавн выкидывает «вперёд через пол-трассы» (он берёт +6 м от
#     найденной отметки);
#   • прогресс, круги и места скачут (Main._physics_process считает
#     разницу отметок за кадр);
#   • бот правит на чужой участок и приезжает «откуда-то сзади»;
#   • Car._clamp_heading разворачивает машину по чужой касательной.
# Поэтому отметку ищем В ОКНЕ вокруг предыдущей: за кадр физики машина
# проходит меньше метра, а окно ±45 м переживает и подброс взрывом.
# Проверка «у стены» (tools/check_axis_jump.gd) прыжков не находила — она
# и не могла: точки брались на полотне, а ломается всё именно СНАРУЖИ.
#
# ВАЖНО: пока ответ движка ПРАВДОПОДОБЕН (сдвинулся не дальше, чем машина
# физически могла проехать за кадр), берём именно его — на полотне ничего
# не меняется вовсе, и все замеры, которые от отметки зависят (ведение у
# стены, кламп курса, линия ИИ), остаются прежними до бита. Свой поиск
# включается только на «прыжке», то есть в аварии.
const OFFSET_WINDOW := 45.0   # полуширина окна поиска, м
const OFFSET_COARSE := 1.5    # шаг грубого прохода, м
# Насколько отметке позволено сдвинуться между двумя опросами. За кадр
# физики машина проезжает меньше метра даже на буст-скорости; 12 м — запас
# на пропущенные кадры, и всё равно вчетверо меньше самого короткого
# «прыжка» на чужой виток.
const OFFSET_MAX_STEP := 12.0


## Отметка на оси, ближайшая к world_pos и НЕПРЕРЫВНАЯ относительно
## prev_off. Обычный путь — ответ Curve3D.get_closest_offset; если он
## прыгнул на чужой виток, ищем сами В ОКНЕ ±OFFSET_WINDOW вокруг
## предыдущей отметки: грубый проход шагом OFFSET_COARSE и шесть уточнений
## половинным делением (точность ~2 см).
func closest_offset_near(world_pos: Vector3, prev_off: float) -> float:
	var length := _curve.get_baked_length()
	if length <= 0.0:
		return 0.0
	var naive := _curve.get_closest_offset(world_pos)
	var jump := absf(naive - fposmod(prev_off, length))
	jump = minf(jump, length - jump)
	if jump <= OFFSET_MAX_STEP:
		return naive
	var best := prev_off
	var best_d := _dist2_at(world_pos, prev_off, length)
	var steps := int(OFFSET_WINDOW * 2.0 / OFFSET_COARSE)
	for i in steps + 1:
		var off := prev_off - OFFSET_WINDOW + OFFSET_COARSE * i
		var d := _dist2_at(world_pos, off, length)
		if d < best_d:
			best_d = d
			best = off
	var span := OFFSET_COARSE
	for _i in 6:
		span *= 0.5
		var a := _dist2_at(world_pos, best - span, length)
		var b := _dist2_at(world_pos, best + span, length)
		if a < best_d and a <= b:
			best_d = a
			best -= span
		elif b < best_d:
			best_d = b
			best += span
	return fposmod(best, length)


## Квадрат расстояния от точки до оси у отметки off. Расстояние ПОЛНОЕ (с
## высотой) — ровно то, что меряет Curve3D.get_closest_offset: на трассе
## отметка обязана совпадать со старой до сантиметров, иначе поедут все
## замеры, которые от неё зависят (ведение у стены, кламп курса, линия ИИ).
## Квадрат — чтобы не звать sqrt в самом горячем цикле поиска.
func _dist2_at(world_pos: Vector3, off: float, length: float) -> float:
	return world_pos.distance_squared_to(_curve.sample_baked(fposmod(off, length)))


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
	return respawn_transform_at(_curve.get_closest_offset(world_pos))


## Респавн от ИЗВЕСТНОЙ отметки — так возвращают машину Main._respawn_car и
## Car.destroy(): у машины отметка ведётся по непрерывности
## (closest_offset_near), а глобальный поиск по позиции улетевшей за
## ограждение машины мог указать на чужой виток и выкинуть её через
## пол-трассы вперёд.
func respawn_transform_at(off: float) -> Transform3D:
	var length := _curve.get_baked_length()
	var offset := fposmod(off + 6.0, length)
	var pos := _curve.sample_baked(offset)
	var ahead := _curve.sample_baked(fposmod(offset + 3.0, length))
	var basis := Basis.looking_at((ahead - pos).normalized())
	# 0.62 м — примерно на длину покоя подвески, чтобы машина не падала
	# с высоты и не подпрыгивала при появлении.
	return Transform3D(basis, pos + Vector3(0, 0.62, 0))
