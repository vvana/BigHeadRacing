class_name CarModelLibrary
extends RefCounted
## Собирает визуальные модели машин.
## Парк (2026-09-02): 15 советских машин (Low Poly Soviet Car Pack, Unity)
## с 10 цветами-скинами каждая + 8 машин Unity «Low Poly Car Vehicle Pack»
## (без скинов) + 8 аркадных машин-конструкторов (Customizable Arcade Car
## Pack): кузов + сменные колёса/мотор/спойлер/выхлоп, 36 красок, наклейки.

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
## сетка выбора выглядела пёстро. У аркадных — цвет краски ARCADE_COLORS.
const DEFAULT_COLORS := {
	"vz01": "red", "vz02": "lightblue", "vz21": "green", "vz03": "white",
	"vz04": "blue", "vz05": "yellow", "vz06": "sand", "vz07": "purple",
	"vz05r": "red", "vz08": "gray", "vz09": "lightblue", "vz099": "black",
	"gz21": "white", "gz24": "black", "vz31": "green",
	"ac1": "red", "ac2": "cyan", "ac3": "yellow", "ac4": "green",
	"ac5": "orange", "ac6": "purple", "ac7": "blue", "ac8": "pink",
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

# ---- Аркадный пак: конструктор (Customizable Arcade Car Pack, Unity) ----
# ОДИН файл Cars.fbx со всеми деталями: 8 кузовов «Car N», 10 колёс
# «Wheel N», 10 моторов «Engine N» (на капот), 10 спойлеров «Spoiler N»,
# 10 выхлопов «Exhaust N». Машина собирается из кузова + 4 колёс + деталей
# по слотам; позиции слотов на каждом кузове — из префабов Unity
# (ARCADE_BODIES). Поверхности мешей: «body» — краска (цвет задаём мы),
# «details» — палитра ColorPalette.png (стёкла, фары, шины), «bottom» —
# днище, «sticker» — наклейка (текстуры Stickers N-M.png, по две в файле),
# «sticker line» — двойная полоса. Нос в +Z, как у остальных паков.
const ARCADE_PATH := "res://assets/models/arcadecars/source/Cars.fbx"
const ARCADE_TEX := "res://assets/models/arcadecars/textures/"
const ARCADE_IDS: Array[String] = [
	"ac1", "ac2", "ac3", "ac4", "ac5", "ac6", "ac7", "ac8",
]
## Краски: 12 цветов × 3 оттенка (1 тёмный, 2 обычный, 3 светлый) —
## значения из материалов пака (sRGB).
const ARCADE_COLORS: Array[String] = [
	"red", "orange", "yellow", "green", "turquoise", "cyan",
	"blue", "purple", "pink", "brown", "cream", "grey",
]
const ARCADE_PAINTS := {
	"red": [Color(0.4, 0, 0), Color(1, 0, 0), Color(1, 0.6, 0.6)],
	"orange": [Color(0.4, 0.2, 0), Color(1, 0.5, 0), Color(1, 0.8, 0.6)],
	"yellow": [Color(0.4, 0.4, 0), Color(1, 1, 0), Color(1, 1, 0.6)],
	"green": [Color(0, 0.4, 0), Color(0, 1, 0), Color(0.6, 1, 0.6)],
	"turquoise": [Color(0.098, 0.361, 0.276), Color(0.251, 0.902, 0.696),
			Color(0.702, 0.961, 0.879)],
	"cyan": [Color(0, 0.4, 0.4), Color(0, 1, 1), Color(0.6, 1, 1)],
	"blue": [Color(0, 0, 0.4), Color(0, 0, 1), Color(0.6, 0.6, 1)],
	"purple": [Color(0.2, 0, 0.4), Color(0.5, 0, 1), Color(0.8, 0.6, 1)],
	"pink": [Color(0.4, 0.16, 0.28), Color(1, 0.4, 0.7), Color(1, 0.76, 0.88)],
	"brown": [Color(0.2, 0.1, 0.04), Color(0.5, 0.25, 0.1), Color(0.8, 0.7, 0.64)],
	"cream": [Color(0.509, 0.447, 0.32), Color(0.774, 0.677, 0.493),
			Color(0.981, 0.893, 0.717)],
	"grey": [Color(0.113, 0.113, 0.113), Color(0.5, 0.5, 0.5),
			Color(0.943, 0.943, 0.943)],
}
## Сколько вариантов у каждой детали (индекс 1..PART_COUNT; 0 — «нет»).
const PART_COUNT := 10
## Слоты деталей → буква в id скина.
const PART_SLOTS: Array[String] = ["wheel", "engine", "spoiler", "exhaust"]
const ARCADE_KEYS := {
	"wheel": "w", "engine": "e", "spoiler": "s", "exhaust": "x",
	"sticker": "k", "line": "l", "glitter": "g",
}
## Стоковая комплектация: колёса №1, без мотора/спойлера/выхлопа,
## обычный красный, без наклеек. color_<слот> — цвет КАЖДОЙ детали
## отдельно от кузова (03.09 ночь: «цвет выбирается отдельно у каждой»):
## "" — как кузов, иначе "<цвет><оттенок>" из ARCADE_PAINTS ("grey2");
## color_line — цвет двойной полосы ("" — тёмно-серая, как в паке).
## Токен id — «p» + буква слота (ARCADE_KEYS): "-pwgrey2" диски,
## "-pered1" мотор, "-ps…" спойлер, "-px…" выхлоп, "-pl…" полоса.
## Старые токены "-p<цвет>" (один цвет на все детали) и "-c<цвет>"
## (полоса) читаются.
## Эффекты (04.09, у ВСЕХ машин, включая Unity без слотов): smoke —
## цвет дыма из-под колёс и пламени выхлопа ("" — обычный серый дым),
## neon — цвет неоновой подсветки под днищем ("" — нет). Значение —
## имя цвета ARCADE_COLORS (яркий оттенок №2), токены id "-m<цвет>"
## (дым) и "-n<цвет>" (неон); у Unity-машин это единственный хвост id
## ("fastback-mcyan"). Старые клиенты чужие токены пропускают.
const ARCADE_DEFAULT := {
	"color": "red", "shade": 2, "glitter": 0, "wheel": 1, "engine": 0,
	"spoiler": 0, "exhaust": 0, "sticker": 0, "line": 0,
	"color_wheel": "", "color_engine": "", "color_spoiler": "",
	"color_exhaust": "", "color_line": "",
	"smoke": "", "neon": "", "glass": "",
}
## Ключ эффекта → буква токена id. glass — тонировка стёкол (04.09 вечер,
## «добавить смену цвета стёкол»): у всех паков, токен "-t<цвет>".
const FX_KEYS := {"smoke": "m", "neon": "n", "glass": "t"}
## Цвета эффектов (дым, неон, тонировка): 12 красок аркадного пака + белый
## и чёрный (просьба 04.09). Белый/чёрный — только для эффектов, кузов и
## детали по-прежнему красятся ARCADE_COLORS.
const FX_COLORS: Array[String] = [
	"red", "orange", "yellow", "green", "turquoise", "cyan",
	"blue", "purple", "pink", "brown", "cream", "grey", "white", "black",
]
const FX_EXTRA_PAINT := {
	"white": Color(1.0, 1.0, 1.0),
	"black": Color(0.02, 0.02, 0.02),
}
## Слот/полоса → ключ его цвета в комплектации.
const COLOR_KEYS := {
	"wheel": "color_wheel", "engine": "color_engine",
	"spoiler": "color_spoiler", "exhaust": "color_exhaust",
	"line": "color_line",
}
## Геометрия кузовов из префабов Unity (координаты относительно кузова):
## wheel_f/wheel_r — правое переднее/заднее колесо (левое — зеркально),
## ws_f/ws_r — масштаб колёс; engine/spoiler/exhaust — [позиция, масштаб].
const ARCADE_BODIES := {
	"ac1": {"mesh": "Car 1",
		"wheel_f": Vector3(0.9, 0.22, 1.923), "wheel_r": Vector3(0.9, 0.286, -1.868),
		"ws_f": Vector3(0.956, 0.956, 0.956), "ws_r": Vector3(1.097, 1.097, 1.097),
		"engine": [Vector3(0, 1.072, 1.663), Vector3.ONE],
		"spoiler": [Vector3(0, 1.13, -2.593), Vector3.ONE],
		"exhaust": [Vector3(0, 0.099, -2.512), Vector3.ONE]},
	"ac2": {"mesh": "Car 2",
		"wheel_f": Vector3(0.86, 0.233, 1.94), "wheel_r": Vector3(0.86, 0.233, -1.641),
		"ws_f": Vector3.ONE, "ws_r": Vector3.ONE,
		"engine": [Vector3(0, 1.234, 2.043), Vector3(0.77, 0.77, 0.77)],
		"spoiler": [Vector3(0, 1.7, -2.224), Vector3(0.754, 1, 1)],
		"exhaust": [Vector3(0, 0.21, -2.613), Vector3(0.93, 1, 1)]},
	"ac3": {"mesh": "Car 3",
		"wheel_f": Vector3(0.9, 0.209, 2.345), "wheel_r": Vector3(0.88, 0.243, -2.111),
		"ws_f": Vector3(0.912, 0.912, 0.912), "ws_r": Vector3.ONE,
		"engine": [Vector3(0, 0.48, 1.749), Vector3(1.318, 1.318, 1.318)],
		"spoiler": [Vector3(0, 0.984, -2.339), Vector3(0.969, 1, 1)],
		"exhaust": [Vector3(0, 0.0, -2.673), Vector3(0.95, 1, 1)]},
	"ac4": {"mesh": "Car 4",
		"wheel_f": Vector3(0.95, 0.217, 1.666), "wheel_r": Vector3(0.95, 0.25, -1.817),
		"ws_f": Vector3(0.95, 0.932, 0.932), "ws_r": Vector3(0.982, 0.982, 0.982),
		"engine": [Vector3(0, 1.056, 1.467), Vector3.ONE],
		"spoiler": [Vector3(0, 1.669, -1.772), Vector3(0.859, 0.753, 0.753)],
		"exhaust": [Vector3(0, 0.145, -2.512), Vector3.ONE]},
	"ac5": {"mesh": "Car 5",
		"wheel_f": Vector3(0.9, 0.2, 1.85), "wheel_r": Vector3(0.9, 0.2, -1.622),
		"ws_f": Vector3(1, 0.947, 0.947), "ws_r": Vector3(1, 0.947, 0.947),
		"engine": [Vector3(0, 1.33, 1.968), Vector3(0.8, 0.8, 0.8)],
		"spoiler": [Vector3(0, 1.237, -2.64), Vector3(1.156, 0.753, 0.753)],
		"exhaust": [Vector3(0, 0.16, -2.546), Vector3.ONE]},
	"ac6": {"mesh": "Car 6",
		"wheel_f": Vector3(1.15, -0.01, 1.766), "wheel_r": Vector3(1.15, -0.01, -1.917),
		"ws_f": Vector3(1.787, 1.787, 1.787), "ws_r": Vector3(1.787, 1.787, 1.787),
		"engine": [Vector3(0, 1.75, 1.864), Vector3.ONE],
		"spoiler": [Vector3(0, 1.945, -2.479), Vector3(1.176, 1.176, 1.176)],
		"exhaust": [Vector3(0, 0.747, -2.402), Vector3(1.141, 1, 1)]},
	"ac7": {"mesh": "Car 7",
		"wheel_f": Vector3(0.9, 0.199, 1.772), "wheel_r": Vector3(0.9, 0.252, -1.756),
		"ws_f": Vector3(1, 0.93, 0.93), "ws_r": Vector3(1.062, 1.062, 1.062),
		"engine": [Vector3(0, 0.927, 2.017), Vector3.ONE],
		"spoiler": [Vector3(0, 1.088, -2.656), Vector3(1.126, 1.126, 1.126)],
		"exhaust": [Vector3(0, 0.19, -2.639), Vector3(0.98, 1, 1)]},
	"ac8": {"mesh": "Car 8",
		"wheel_f": Vector3(1.046, 0.321, 1.949), "wheel_r": Vector3(1.046, 0.321, -1.831),
		"ws_f": Vector3(1.15, 1.15, 1.15), "ws_r": Vector3(1.15, 1.15, 1.15),
		"engine": [Vector3(0, 1.539, 2.281), Vector3.ONE],
		"spoiler": [Vector3(0, 2.473, -2.597), Vector3(1.007, 1.046, 1.046)],
		"exhaust": [Vector3(-0.018, 0.32, -2.846), Vector3(1.085, 1, 1)]},
}

# ---- Аркадные детали на советских машинах (03.09.2026, вечер) ----
# Те же моторы/спойлеры/выхлопы/колёса из Cars.fbx ставятся на советский
# кузов по его геометрии (_attach_parts): позиции слотов считаются по
# габаритам и верху меша, колёса подменяются в пивотах. Набор деталей у
# каждой машины СВОЙ, подобран по характеру (классика — скромные диски и
# низкие спойлеры, «зубила» — спортивные, Нивы — внедорожные диски и
# трубы-стойки). Колёса 0 — родные, у остальных слотов 0 — пусто.
# Стоковая машина по-прежнему "vz01_red" (id без хвоста), с деталями —
# "vz01_red-w5-e3-s1-x2" (токены как у аркадных, нули опущены).
const SOVIET_PARTS := {
	"vz01": {"wheel": [2, 5, 8], "engine": [1, 3, 7], "spoiler": [1, 3],
			"exhaust": [1, 3, 6]},
	"vz02": {"wheel": [3, 5, 9], "engine": [2, 7], "spoiler": [3],
			"exhaust": [2, 5]},
	"vz21": {"wheel": [7, 8, 9], "engine": [2, 6], "spoiler": [3],
			"exhaust": [5, 7]},
	"vz03": {"wheel": [2, 3, 8], "engine": [1, 2, 5], "spoiler": [1, 6],
			"exhaust": [1, 2, 7]},
	"vz04": {"wheel": [3, 7, 9], "engine": [2, 7], "spoiler": [3],
			"exhaust": [3, 6]},
	"vz05": {"wheel": [2, 4, 5], "engine": [1, 3, 8], "spoiler": [1, 3, 6],
			"exhaust": [1, 3, 8]},
	"vz06": {"wheel": [2, 5, 8, 9], "engine": [1, 3, 7], "spoiler": [1, 3, 6],
			"exhaust": [1, 2, 6]},
	"vz07": {"wheel": [2, 3, 5], "engine": [2, 5, 7], "spoiler": [1, 6, 7],
			"exhaust": [2, 3, 8]},
	"vz05r": {"wheel": [1, 4, 6, 10], "engine": [4, 6, 10],
			"spoiler": [2, 4, 9, 10], "exhaust": [4, 6, 8]},
	"vz08": {"wheel": [1, 4, 6], "engine": [1, 4, 8], "spoiler": [2, 5, 7],
			"exhaust": [2, 4, 6]},
	"vz09": {"wheel": [1, 4, 10], "engine": [1, 6, 8], "spoiler": [2, 5, 9],
			"exhaust": [2, 6, 8]},
	"vz099": {"wheel": [4, 6, 10], "engine": [2, 4, 10], "spoiler": [2, 7, 10],
			"exhaust": [4, 6, 8]},
	"gz21": {"wheel": [7, 8, 9], "engine": [2, 5, 9], "spoiler": [3, 5],
			"exhaust": [1, 4, 7]},
	"gz24": {"wheel": [2, 7, 8], "engine": [1, 5, 9], "spoiler": [1, 3, 6],
			"exhaust": [1, 4, 7]},
	"vz31": {"wheel": [7, 8, 9], "engine": [2, 6, 10], "spoiler": [3],
			"exhaust": [5, 6, 7]},
}
## Цвет деталей советской машины по умолчанию («как кузов»): ближайшая
## краска аркадного пака к цвету палитры советского пака.
const SOVIET_PART_PAINT := {
	"black": "grey1", "blue": "blue2", "gray": "grey2", "green": "green1",
	"lightblue": "blue3", "purple": "purple1", "red": "red2", "sand": "cream2",
	"white": "grey3", "yellow": "yellow2",
}
## Ручные поправки позиций слотов советских машин, в МЕТРАХ (машина
## длиной 3.2 м; x — вправо, y — вверх, z — вперёд к носу). Эвристика
## _attach_parts даёт базу, тут — что не понравилось на снимке
## ShotCrossTuning --soviet.
const SOVIET_SLOT_FIX := {
}
## Хэтчбеки, у которых спойлер ставится на НИЖНЮЮ кромку двери багажника
## (как на настоящих тюнингованных «восьмёрках»), а не на кромку крыши.
const LOW_SPOILER_HATCH: Array[String] = ["vz08", "vz09"]

## БАЗОВЫЕ идентификаторы машин (без цвета) — порядок сетки гаража:
## сперва 3 стартовые, дальше по порядку открытия (GameState.CAR_UNLOCKS).
const CAR_IDS: Array[String] = [
	"vz01", "vz02", "vz21",
	"vz03", "vz04", "vz05", "ac1", "vz06", "vz07", "ac2", "vz05r", "vz08",
	"ac3", "vz09", "vz099", "ac4", "gz21", "gz24", "ac5", "vz31",
	"fastback", "ac6", "safari", "chevelle", "ac7", "godfather", "lemans",
	"ac8", "superbird", "dragster", "diablo",
]


# ---- Скины: разбор и сборка id ----
# Советский: "vz01_red" (база_цвет). Аркадный: "ac3-yellow2-g1-w5-e3-s0-x2-k4-l1"
# (база-краска оттенок-металлик-колёса-мотор-спойлер-выхлоп-наклейка-полоса);
# пропущенные части — из ARCADE_DEFAULT. Полный id уезжает в сетевой hello
# и определяет визуал у соперников.

static func is_arcade(base: String) -> bool:
	return ARCADE_IDS.has(base)


## Есть ли у машины слоты деталей (аркадные конструкторы и советские).
static func has_parts(base: String) -> bool:
	return is_arcade(base) or SOVIET_PARTS.has(base)


## Какие номера можно поставить в слот: аркадным — все (колёса 1..10,
## прочее 0..10), советским — 0 (родные/пусто) + подобранный набор,
## остальным — ничего.
static func slot_options(base: String, slot: String) -> Array[int]:
	var out: Array[int] = []
	if is_arcade(base):
		for i in range(1 if slot == "wheel" else 0, PART_COUNT + 1):
			out.append(i)
	elif SOVIET_PARTS.has(base):
		out.append(0)
		for i in (SOVIET_PARTS[base] as Dictionary).get(slot, []):
			out.append(int(i))
	return out


## Стоковая комплектация базы (копия): аркадная — ARCADE_DEFAULT, советская
## — родные колёса и пустые слоты; цвет — по умолчанию для базы.
static func default_cfg(base: String) -> Dictionary:
	var cfg := ARCADE_DEFAULT.duplicate()
	cfg["color"] = default_color(base)
	if not is_arcade(base):
		cfg["wheel"] = 0
	return cfg


## Голова id — до первого «-» (хвост — токены деталей).
static func _head(id: String) -> String:
	var dash := id.find("-")
	return id.substr(0, dash) if dash > 0 else id


## База полного id: "vz01_red" → "vz01", "vz01_red-w5" → "vz01",
## "ac3-…" → "ac3"; id без суффиксов возвращается как есть.
static func base_id(id: String) -> String:
	var head := _head(id)
	if ARCADE_IDS.has(head):
		return head
	var cut := head.rfind("_")
	if cut > 0 and SOVIET_COLORS.has(head.substr(cut + 1)):
		return head.substr(0, cut)
	return head


## Цвет полного id: "vz01_red" → "red"; нет суффикса — цвет по умолчанию.
static func color_of_id(id: String) -> String:
	var base := base_id(id)
	if is_arcade(base):
		return String(arcade_parse(id)["color"])
	var head := _head(id)
	var cut := head.rfind("_")
	if cut > 0 and SOVIET_COLORS.has(head.substr(cut + 1)):
		return head.substr(cut + 1)
	return default_color(base)


## Есть ли у машины скины-цвета (советский и аркадный паки).
static func has_skins(base: String) -> bool:
	return SOVIET_IDS.has(base) or is_arcade(base)


## Список цветов-скинов машины (пусто — скинов нет).
static func colors_for(base: String) -> Array[String]:
	if is_arcade(base):
		return ARCADE_COLORS
	if SOVIET_IDS.has(base):
		return SOVIET_COLORS
	var none: Array[String] = []
	return none


static func default_color(base: String) -> String:
	return DEFAULT_COLORS.get(base, "red")


## Полный id скина: база + цвет ("vz01" + "red" → "vz01_red"; аркадная —
## стоковая комплектация в этом цвете). Для машин без скинов цвет
## игнорируется.
static func skin_id(base: String, color: String) -> String:
	if is_arcade(base):
		var cfg := ARCADE_DEFAULT.duplicate()
		cfg["color"] = color if ARCADE_COLORS.has(color) else default_color(base)
		return arcade_id(base, cfg)
	if not has_skins(base):
		return base
	if not SOVIET_COLORS.has(color):
		color = default_color(base)
	return "%s_%s" % [base, color]


## Полный id ЛЮБОЙ машины из комплектации: аркадная — arcade_id;
## советская — "vz01_red" + токены НЕнулевых деталей и цвета деталей
## ("vz01_red-w5-e3-pgrey2"; сток остаётся старым коротким id — сеть и
## старые профили его понимают); прочие — база.
static func tuned_id(base: String, cfg: Dictionary) -> String:
	if is_arcade(base):
		return arcade_id(base, cfg)
	if not SOVIET_PARTS.has(base):
		# Unity-машины: база + полоса (04.09, "-l1" и её цвет "-pl…") +
		# эффекты ("fastback-l1-mred"); без них — голая база, как раньше.
		var u := _clamp_cfg(cfg, base)
		var uid := base
		if int(u["line"]) > 0:
			uid += "-l1"
		return uid + _color_tokens(u)
	var c := _clamp_cfg(cfg, base)
	var id := skin_id(base, str(c["color"]))
	for slot in PART_SLOTS:
		if int(c[slot]) > 0:
			id += "-%s%d" % [ARCADE_KEYS[slot], int(c[slot])]
	# Полоса вдоль кузова — с 04.09 и у советских (шейдерный дубль кузова).
	if int(c["line"]) > 0:
		id += "-l1"
	return id + _color_tokens(c)


## Хвост id с цветами деталей и полосы (пустые — опущены):
## "-pw<цвет>", "-pe…", "-ps…", "-px…", "-pl…".
static func _color_tokens(c: Dictionary) -> String:
	var t := ""
	for part in COLOR_KEYS:
		var spec := str(c[COLOR_KEYS[part]])
		if not spec.is_empty():
			t += "-p%s%s" % [ARCADE_KEYS[part], spec]
	return t + _fx_tokens(c)


## Хвост id с эффектами: "-m<цвет>" дым, "-n<цвет>" неон (пустые — опущены).
static func _fx_tokens(c: Dictionary) -> String:
	var t := ""
	for key in FX_KEYS:
		var color := str(c.get(key, ""))
		if FX_COLORS.has(color):
			t += "-%s%s" % [FX_KEYS[key], color]
	return t


## Разобрать полный id любой машины в комплектацию (+ "base"): аркадный —
## arcade_parse, советский — цвет из головы, детали из токенов; у прочих
## — сток.
static func parse_cfg(id: String) -> Dictionary:
	var base := base_id(id)
	if is_arcade(base):
		return arcade_parse(id)
	var cfg := default_cfg(base)
	cfg["base"] = base
	cfg["color"] = color_of_id(id)
	_parse_tokens(id.split("-"), 1, cfg)
	return _clamp_cfg(cfg, base)


## Собрать id аркадной машины из комплектации (ключи ARCADE_DEFAULT;
## пропущенные — по умолчанию, значения зажимаются в допустимые).
static func arcade_id(base: String, cfg: Dictionary) -> String:
	var c := _clamp_cfg(cfg)
	return "%s-%s%d-g%d-w%d-e%d-s%d-x%d-k%d-l%d" % [
		base, c["color"], c["shade"], c["glitter"], c["wheel"], c["engine"],
		c["spoiler"], c["exhaust"], c["sticker"], c["line"]] + _color_tokens(c)


## Разобрать id аркадной машины в комплектацию (+ "base"). Битые и
## пропущенные части — по умолчанию: чужой клиент с любым id не уронит.
static func arcade_parse(id: String) -> Dictionary:
	var cfg := ARCADE_DEFAULT.duplicate()
	var parts := id.split("-")
	cfg["base"] = parts[0]
	if parts.size() > 1:
		# Краска: имя цвета + цифра оттенка ("yellow2").
		var tok: String = parts[1]
		var col := tok.rstrip("0123456789")
		if ARCADE_COLORS.has(col):
			cfg["color"] = col
		var sh := tok.substr(col.length())
		if sh.is_valid_int():
			cfg["shade"] = int(sh)
	_parse_tokens(parts, 2, cfg)
	return _clamp_cfg(cfg)


## Токены деталей "w5", "e3", …; цвета "pw<цвет>" (диски), "pe…", "ps…",
## "px…", "pl…" (полоса); старые "p<цвет>" (все детали) и "c<цвет>"
## (полоса) → cfg.
static func _parse_tokens(parts: PackedStringArray, from: int,
		cfg: Dictionary) -> void:
	for i in range(from, parts.size()):
		var tok: String = parts[i]
		if tok.is_empty():
			continue
		var key := tok[0]
		var rest := tok.substr(1)
		if key == "p":
			var found := false
			for part in COLOR_KEYS:
				if rest.begins_with(String(ARCADE_KEYS[part])) \
						and is_paint_spec(rest.substr(1)):
					cfg[COLOR_KEYS[part]] = rest.substr(1)
					found = true
					break
			if not found and is_paint_spec(rest):
				for slot in PART_SLOTS:
					cfg[COLOR_KEYS[slot]] = rest
			continue
		if key == "c":
			cfg["color_line"] = rest
			continue
		# Эффекты: "m<цвет>" дым, "n<цвет>" неон (чужой цвет — пропуск).
		var fx_hit := false
		for fx in FX_KEYS:
			if FX_KEYS[fx] == key and FX_COLORS.has(rest):
				cfg[fx] = rest
				fx_hit = true
		if fx_hit or not rest.is_valid_int():
			continue
		for name in ARCADE_KEYS:
			if ARCADE_KEYS[name] == key:
				cfg[name] = int(rest)


## Спецификация краски "<цвет><оттенок>" ("grey2") корректна?
static func is_paint_spec(spec: String) -> bool:
	var col := spec.rstrip("0123456789")
	var sh := spec.substr(col.length())
	return ARCADE_COLORS.has(col) and sh.is_valid_int() \
			and int(sh) >= 1 and int(sh) <= 3


## Цвет по спецификации краски ("grey2" → Color); битая — fallback.
static func paint_color(spec: String, fallback := Color.GRAY) -> Color:
	if not is_paint_spec(spec):
		return fallback
	var col := spec.rstrip("0123456789")
	var shades: Array = ARCADE_PAINTS[col]
	return shades[int(spec.substr(col.length())) - 1]


## base — чья комплектация: у советских цвет из SOVIET_COLORS, колёса
## 0..10 (0 — родные); у аркадных — ARCADE_COLORS и колёса 1..10.
static func _clamp_cfg(cfg: Dictionary, base := "") -> Dictionary:
	var c := ARCADE_DEFAULT.duplicate()
	for k in cfg:
		c[k] = cfg[k]
	var soviet := SOVIET_IDS.has(base)
	if soviet:
		if not SOVIET_COLORS.has(c["color"]):
			c["color"] = default_color(base)
	elif not ARCADE_COLORS.has(c["color"]):
		c["color"] = "red"
	c["shade"] = clampi(int(c["shade"]), 1, 3)
	c["glitter"] = clampi(int(c["glitter"]), 0, 1)
	c["line"] = clampi(int(c["line"]), 0, 1)
	c["wheel"] = clampi(int(c["wheel"]), 0 if soviet else 1, PART_COUNT)
	for k in ["engine", "spoiler", "exhaust", "sticker"]:
		c[k] = clampi(int(c[k]), 0, PART_COUNT)
	for part in COLOR_KEYS:
		var k: String = COLOR_KEYS[part]
		if not is_paint_spec(str(c.get(k, ""))):
			c[k] = ""
	for fx in FX_KEYS:
		if not FX_COLORS.has(str(c.get(fx, ""))):
			c[fx] = ""
	c.erase("pcolor")
	c.erase("lcolor")
	return c


## Цвет эффекта (дым/неон) по имени из ARCADE_COLORS — яркий оттенок №2;
## чужое имя — fallback.
static func fx_color(color: String, fallback := Color.WHITE) -> Color:
	if FX_EXTRA_PAINT.has(color):
		return FX_EXTRA_PAINT[color]
	if not ARCADE_PAINTS.has(color):
		return fallback
	return (ARCADE_PAINTS[color] as Array)[1]


## Ступень улучшения, нужная для детали с номером index в слоте slot:
## 0 — сток (колёса №1; мотор/спойлер/выхлоп «нет»), дальше по три
## варианта на ступень (1–3 → I, 4–6 → II, 7–10 → III; у колёс сдвиг
## на один, т.к. №1 — стоковые).
static func part_tier(slot: String, index: int) -> int:
	var n := index - 1 if slot == "wheel" else index
	if n <= 0:
		return 0
	return mini(3, floori((n - 1) / 3.0) + 1)


## Пул для ботов: по одному СЛУЧАЙНОМУ цвету на каждую машину, перемешан;
## аркадные — со случайной комплектацией (витрина тюнинга). Боты замков
## не знают — ездят на чём угодно (так заезд пёстрый, а игрок видит
## будущие покупки вживую). RNG — СВОЙ: глобальный поток randf/randi
## питает детерминированные регрессионные стенды, пул не должен его
## сдвигать (TestWeapons ловил).
static func shuffled_bot_pool() -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out: Array[String] = []
	for base in CAR_IDS:
		if is_arcade(base):
			var cfg := {
				"color": ARCADE_COLORS[rng.randi_range(0, ARCADE_COLORS.size() - 1)],
				"shade": rng.randi_range(1, 3),
				"glitter": rng.randi_range(0, 1),
				"wheel": rng.randi_range(1, PART_COUNT),
				"engine": rng.randi_range(0, PART_COUNT),
				"spoiler": rng.randi_range(0, PART_COUNT),
				"exhaust": rng.randi_range(0, PART_COUNT),
				"sticker": rng.randi_range(0, PART_COUNT),
				"line": rng.randi_range(0, 1),
			}
			out.append(arcade_id(base, cfg))
		elif SOVIET_PARTS.has(base):
			# Советские: цвет и по случайной детали из своего набора в
			# каждом слоте (половина слотов пустые — не все «в обвесе»).
			var cfg := default_cfg(base)
			cfg["color"] = SOVIET_COLORS[rng.randi_range(0, SOVIET_COLORS.size() - 1)]
			for slot in PART_SLOTS:
				var opts := slot_options(base, slot)
				if rng.randi_range(0, 1) == 1:
					cfg[slot] = opts[rng.randi_range(1, opts.size() - 1)]
			for slot in PART_SLOTS:
				if rng.randi_range(0, 2) == 0:
					cfg[COLOR_KEYS[slot]] = "%s%d" % [
							ARCADE_COLORS[rng.randi_range(0, ARCADE_COLORS.size() - 1)],
							rng.randi_range(1, 3)]
			out.append(tuned_id(base, cfg))
		else:
			out.append(skin_id(base,
					SOVIET_COLORS[rng.randi_range(0, SOVIET_COLORS.size() - 1)]))
	# Эффекты — витрина: у каждого четвёртого бота цветной дым, у каждого
	# четвёртого — неон (любой машине, включая Unity).
	for i in out.size():
		var cfg := parse_cfg(out[i])
		var touched := false
		for fx in FX_KEYS:
			if rng.randi_range(0, 3) == 0:
				cfg[fx] = ARCADE_COLORS[rng.randi_range(0, ARCADE_COLORS.size() - 1)]
				touched = true
		if touched:
			out[i] = tuned_id(String(cfg["base"]), cfg)
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

# Аркадный пак: имя узла → MeshInstance3D в распакованном Cars.fbx,
# текстуры и материалы (общие, кэшируются по ключу).
static var _arcade_nodes: Dictionary = {}
static var _arcade_tex: Dictionary = {}
static var _arcade_mats: Dictionary = {}


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
## car_id может нести цвет ("vz01_red") или комплектацию ("ac3-…");
## без них — цвет по умолчанию / сток. Вернёт null, если машина не нашлась.
static func build(
	car_id: String,
	target_length := 3.2,
	base_y := -0.35
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
		if model and id.contains("-"):
			_attach_parts(model, base, parse_cfg(id))
	elif SINGLE_CAR_PATHS.has(base):
		model = _build_single(
				String(SINGLE_CAR_PATHS[base]), base, target_length, base_y)
	elif is_arcade(base):
		model = _build_arcade(arcade_parse(id), id, target_length, base_y)
	if model:
		var fx := parse_cfg(id)
		# Полоса вдоль кузова у НЕаркадных машин (04.09): у аркадных она в
		# UV-развёртке ("sticker line"), у советских и Unity рисуется
		# шейдером на дубле кузова (см. _attach_line).
		if not is_arcade(base) and int(fx.get("line", 0)) > 0:
			_attach_line(model, base, str(fx.get("color_line", "")))
		# Тонировка стёкол (04.09) — у всех паков, своим способом.
		var glass := str(fx.get("glass", ""))
		if FX_COLORS.has(glass):
			_apply_glass(model, base, glass)
		# Неон под днищем — часть модели: так он есть и на подиуме гаража,
		# и в лобби, и в заезде (модель едет по видимому положению машины —
		# см. Car._process, — свет не отстаёт от кузова).
		var neon := str(fx.get("neon", ""))
		if FX_COLORS.has(neon):
			_attach_underglow(model, neon, base_y)
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
			# Полуширина колеса в единицах файла — подменное аркадное
			# колесо (уже) выдвигается наружу до той же плоскости.
			pivot.set_meta("half_width", (it["aabb"] as AABB).size.x * 0.5)
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


# ---- Аркадный конструктор ----

## Меш детали по имени узла в Cars.fbx ("Car 3", "Wheel 7"…); null — нет.
static func _arcade_mesh(name: String) -> Mesh:
	if _arcade_nodes.is_empty():
		var src := _pack_src(ARCADE_PATH)
		if src == null:
			return null
		var items: Array[Dictionary] = []
		_collect_meshes(src, Transform3D.IDENTITY, items)
		for it in items:
			_arcade_nodes[String((it["node"] as Node).name)] = it["node"]
	var mi: MeshInstance3D = _arcade_nodes.get(name)
	return mi.mesh if mi else null


## Текстура пака как ImageTexture (см. грабли в _soviet_material: 2D-импорт
## в слоте материала биндится ненадёжно — перегоняем в ImageTexture).
static func _arcade_texture(file: String) -> ImageTexture:
	if not _arcade_tex.has(file):
		var t: Texture2D = load(ARCADE_TEX + file)
		_arcade_tex[file] = ImageTexture.create_from_image(t.get_image()) \
				if t else null
	return _arcade_tex[file]


## Материал по ключу (кэш): "details" — палитра, "bottom" — днище,
## "paint:<цвет><оттенок><металлик>" — краска, "sticker:<n>" — наклейка,
## "line" — двойная полоса (тёмно-серая, как в паке) / "line:<цвет><оттенок>"
## — в выбранном цвете, "hidden" — невидимая поверхность.
static func _arcade_material(key: String) -> StandardMaterial3D:
	if _arcade_mats.has(key):
		return _arcade_mats[key]
	var m := StandardMaterial3D.new()
	if key == "details":
		m.albedo_texture = _arcade_texture("ColorPalette.png")
		m.albedo_texture_force_srgb = true
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.roughness = 0.55
		m.metallic_specular = 0.4
	elif key == "bottom":
		m.albedo_texture = _arcade_texture("Bottom.png")
		m.albedo_texture_force_srgb = true
		m.roughness = 0.9
	elif key.begins_with("paint:"):
		# "paint:yellow21" → цвет yellow, оттенок 2, металлик 1.
		var spec := key.substr(6)
		var col := spec.rstrip("0123456789")
		var shade := int(spec.substr(col.length(), 1))
		var glitter := spec.ends_with("1")
		var shades: Array = ARCADE_PAINTS.get(col, ARCADE_PAINTS["red"])
		m.albedo_color = shades[clampi(shade, 1, 3) - 1]
		if glitter:
			# «Металлик»: зеркальный блик и лёгкий лак поверх краски.
			m.metallic = 0.85
			m.roughness = 0.32
			m.clearcoat_enabled = true
			m.clearcoat = 0.6
		else:
			m.metallic = 0.0
			m.roughness = 0.45
			m.metallic_specular = 0.5
	elif key.begins_with("sticker:"):
		var n := int(key.substr(8))
		var pair := floori((n - 1) / 2.0) * 2 + 1
		m.albedo_texture = _arcade_texture("Stickers %d-%d.png" % [pair, pair + 1])
		m.albedo_texture_force_srgb = true
		# В файле две наклейки друг над другом: чётная — верхняя половина.
		if n % 2 == 0:
			m.uv1_offset = Vector3(0, 0.5, 0)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.45
		m.roughness = 0.5
	elif key == "line" or key.begins_with("line:"):
		m.albedo_color = paint_color(key.substr(5), Color(0.113, 0.113, 0.113))
		m.roughness = 0.5
	else:   # hidden — все пиксели отсекаются
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.albedo_color = Color(0, 0, 0, 0)
	_arcade_mats[key] = m
	return m


## Экземпляр меша с материалами по именам поверхностей пака ("body",
## "details", "bottom", "sticker", "sticker line"): body — краска paint_key.
## paint_all — красить и "details" (у выхлопов в паке ТОЛЬКО эта поверхность,
## без флага цвет труб не менялся — жалоба 04.09; включается, когда игрок
## явно выбрал цвет выхлопа, без выбора трубы остаются палитрой пака).
static func _arcade_part(mesh: Mesh, paint_key: String, sticker: int,
		line: int, line_color := "", paint_all := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var line_key := "line:%s" % line_color if is_paint_spec(line_color) else "line"
	for i in mesh.get_surface_count():
		var mat := mesh.surface_get_material(i)
		var nm := mat.resource_name if mat else ""
		var key := ""
		match nm:
			"body": key = paint_key
			"details": key = paint_key if paint_all else "details"
			"bottom": key = "bottom"
			"sticker": key = "sticker:%d" % sticker if sticker > 0 else "hidden"
			"sticker line": key = line_key if line > 0 else "hidden"
			_: key = "details"
		mi.set_surface_override_material(i, _arcade_material(key))
	return mi


## Аркадная машина из комплектации cfg (arcade_parse): кузов + 4 колеса
## в пивотах (крутятся/рулятся, как у советских) + мотор/спойлер/выхлоп
## по слотам кузова. Все размеры — в единицах пака, потом общий масштаб
## по длине КУЗОВА (детали на длину не влияют, иначе выхлоп-ракета
## укоротил бы машину).
static func _build_arcade(cfg: Dictionary, car_id: String,
		target_length: float, base_y: float) -> Node3D:
	var base: String = cfg.get("base", "")
	if not ARCADE_BODIES.has(base):
		return null
	var geo: Dictionary = ARCADE_BODIES[base]
	var body_mesh := _arcade_mesh(String(geo["mesh"]))
	var wheel_mesh := _arcade_mesh("Wheel %d" % int(cfg["wheel"]))
	if body_mesh == null or wheel_mesh == null:
		return null
	var paint := "paint:%s%d%d" % [cfg["color"], cfg["shade"], cfg["glitter"]]
	var container := Node3D.new()
	container.name = "CarModel_" + car_id

	var body := _arcade_part(body_mesh, paint, int(cfg["sticker"]),
			int(cfg["line"]), str(cfg.get("color_line", "")))
	# Детали — каждая в своём цвете (color_<слот>), без него — в краске
	# кузова.
	var body_paint := paint
	paint = _part_paint(cfg, "wheel", body_paint)
	body.name = "Body"
	container.add_child(body)
	var body_aabb := body_mesh.get_aabb()
	var combined := body_aabb
	var s := target_length / body_aabb.size.z

	# Колёса: меш в файле сделан для одной стороны (торчит наружу по x);
	# на другую сторону — разворот на PI вокруг Y, как в префабе пака.
	var wheel_aabb := wheel_mesh.get_aabb()
	var mesh_side := signf(wheel_aabb.get_center().x)
	if mesh_side == 0.0:
		mesh_side = 1.0
	for spec in [[1, true], [-1, true], [1, false], [-1, false]]:
		var side: int = spec[0]
		var front: bool = spec[1]
		var pos: Vector3 = geo["wheel_f"] if front else geo["wheel_r"]
		pos.x = absf(pos.x) * side
		var ws: Vector3 = geo["ws_f"] if front else geo["ws_r"]
		var pivot := Node3D.new()
		pivot.name = "WheelPivot_%s%s" % ["f" if front else "r", "r" if side > 0 else "l"]
		pivot.position = pos
		var wheel := _arcade_part(wheel_mesh, paint, 0, 0)
		wheel.name = "Wheel"
		var rot := Basis.IDENTITY if float(side) == mesh_side \
				else Basis(Vector3.UP, PI)
		wheel.transform = Transform3D(rot.scaled(ws), Vector3.ZERO)
		pivot.add_child(wheel)
		pivot.set_meta("wheel_radius", wheel_aabb.size.y * 0.5 * ws.y * s)
		pivot.set_meta("is_front", front)
		pivot.set_meta("spin_sign", -1.0)   # контейнер развёрнут на PI
		container.add_child(pivot)
		combined = combined.merge(Transform3D(rot.scaled(ws), pos) * wheel_aabb)

	# Детали по слотам: индекс 0 — слот пуст.
	for slot in ["engine", "spoiler", "exhaust"]:
		var idx := int(cfg[slot])
		if idx <= 0:
			continue
		var mesh := _arcade_mesh("%s %d" % [slot.capitalize(), idx])
		if mesh == null:
			continue
		var place: Array = geo[slot]
		var part := _arcade_part(mesh, _part_paint(cfg, slot, body_paint), 0, 0,
				"", _paint_all(cfg, slot))
		part.name = slot.capitalize()
		part.transform = Transform3D(Basis.IDENTITY.scaled(place[1]), place[0])
		container.add_child(part)

	# Нос кузова в +Z — разворот на PI, как у одиночных файлов; центр по
	# кузову, низ — по колёсам (они ниже днища).
	var center := body_aabb.get_center()
	container.scale = Vector3.ONE * s
	container.rotation.y = PI
	container.position = Vector3(
		center.x * s,
		base_y - combined.position.y * s,
		center.z * s
	)
	return container


## Ключ краски детали слота: color_<слот> комплектации ("grey2" →
## "paint:grey20"), пусто — краска кузова body_paint.
static func _part_paint(cfg: Dictionary, slot: String, body_paint: String) -> String:
	var pc := str(cfg.get(COLOR_KEYS.get(slot, ""), ""))
	return "paint:%s0" % pc if is_paint_spec(pc) else body_paint


## Красить ли деталь целиком (и поверхность "details"): выхлоп — при явно
## выбранном цвете (см. _arcade_part), остальные — никогда.
static func _paint_all(cfg: Dictionary, slot: String) -> bool:
	return slot == "exhaust" \
			and is_paint_spec(str(cfg.get(COLOR_KEYS.get(slot, ""), "")))


# ---- Аркадные детали на советском кузове ----

## Радиус пробы верха для низкого спойлера хэтчбека: узкий (0.5 % длины),
## чтобы крест проб не зацепил заднее стекло выше кромки двери.
static func rs_low(len: float) -> float:
	return len * 0.005


## Верх кузова под вертикалью (x, z) — по ТРЕУГОЛЬНИКАМ меша (faces —
## тройки вершин из get_faces()), а не по вершинам: у низкополи-кузовов
## капот — один большой квад, и в столбике вершин может не быть вовсе
## (Нива, 04.09: единственной вершиной в столбике оказалась кромка
## колёсной арки, мотор ставился на высоту ступицы и тонул в капоте).
## Берётся максимум по пяти точкам — центр и крест радиусом r
## (fallback — если ни одна вертикаль ничего не пересекла).
static func _top_at(faces: PackedVector3Array, x: float, z: float,
		r: float, fallback: float) -> float:
	var top := -INF
	var pts: Array[Vector2] = [Vector2(x, z), Vector2(x + r, z),
			Vector2(x - r, z), Vector2(x, z + r), Vector2(x, z - r)]
	var n := faces.size() - faces.size() % 3
	for i in range(0, n, 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		# Барицентрические веса точки в проекции на XZ.
		var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(d) < 1e-9:
			continue                        # вертикальная грань
		for p in pts:
			var w0 := ((b.z - c.z) * (p.x - c.x) + (c.x - b.x) * (p.y - c.z)) / d
			var w1 := ((c.z - a.z) * (p.x - c.x) + (a.x - c.x) * (p.y - c.z)) / d
			var w2 := 1.0 - w0 - w1
			if w0 >= -1e-4 and w1 >= -1e-4 and w2 >= -1e-4:
				top = maxf(top, w0 * a.y + w1 * b.y + w2 * c.y)
	return top if top > -INF else fallback


## Нижняя кромка заднего бампера: x — самая кормовая z кузова (в СИСТЕМЕ
## НОСА, т.е. z*nose; меньше — дальше назад) среди вершин у продольной оси
## (±25 % ширины) не выше пояса (ступица + 30 % высоты — багажник и стёкла
## не в счёт); y — низ кузова у самой этой кормы (низ
## бампера, допуск 1 % длины). Fallback — торец габарита на высоте ступицы.
static func _bumper_edge(verts: PackedVector3Array, cx: float, aabb: AABB,
		nose: float, hub_y: float) -> Vector2:
	var half_w := aabb.size.x * 0.25
	var y_max := hub_y + aabb.size.y * 0.3
	var rear := INF
	for v in verts:
		if absf(v.x - cx) <= half_w and v.y <= y_max:
			rear = minf(rear, v.z * nose)
	if rear == INF:
		return Vector2(aabb.get_center().z * nose - aabb.size.z * 0.5, hub_y)
	var y_edge := INF
	# 1 % длины: при 2 % у Волги-24 в кромку попадало днище (на 9 см
	# впереди бампера), и трубы съезжали под кузов.
	var tol := aabb.size.z * 0.01
	for v in verts:
		if absf(v.x - cx) <= half_w and v.y <= y_max and v.z * nose <= rear + tol:
			y_edge = minf(y_edge, v.y)
	return Vector2(rear, y_edge if y_edge < INF else hub_y)


## Поставить детали cfg на собранную советскую модель (контейнер
## _build_single): позиции слотов — по геометрии кузова в ЕДИНИЦАХ ФАЙЛА
## (контейнер потом масштабируется): мотор над капотом чуть позади
## передней оси, спойлер по верху багажника у кормы, выхлоп в торце кормы
## ниже ступицы; колёса — аркадный меш в пивоте с тем же радиусом, лицом
## наружу до плоскости родного колеса. Масштаб деталей — как на аркадной
## машине той же длины. Поправки на машину — SOVIET_SLOT_FIX (в метрах).
static func _attach_parts(m: Node3D, base: String, cfg: Dictionary) -> void:
	var s_c := m.scale.x                       # единицы файла → метры
	if s_c <= 0.0:
		return
	var nose := 1.0 if m.rotation.y != 0.0 else -1.0   # нос в локальных
	var aabb := AABB()
	var first := true
	var verts := PackedVector3Array()
	var wheels: Array[Node3D] = []
	for c in m.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var a: AABB = mi.transform * mi.mesh.get_aabb()
			aabb = a if first else aabb.merge(a)
			first = false
			for v in mi.mesh.get_faces():
				verts.append(mi.transform * v)
		elif c is Node3D and c.has_meta("wheel_radius"):
			wheels.append(c as Node3D)
	if first:
		return
	var ac_body := _arcade_mesh("Car 1")
	if ac_body == null:
		return
	# Детали в единицах файла: как на аркадной машине той же длины.
	var k := aabb.size.z / ac_body.get_aabb().size.z
	var body_paint := "paint:%s0" % SOVIET_PART_PAINT.get(
			str(cfg.get("color", "")), "grey2")
	var paint := _part_paint(cfg, "wheel", body_paint)
	var cx := aabb.get_center().x
	var len := aabb.size.z
	var z_front := aabb.get_center().z + nose * len * 0.5
	var z_rear := aabb.get_center().z - nose * len * 0.5
	var axle_f_z := z_front - nose * len * 0.2
	var hub_y := aabb.position.y + aabb.size.y * 0.15
	var fix: Dictionary = SOVIET_SLOT_FIX.get(base, {})

	var widx := int(cfg.get("wheel", 0))
	var wmesh := _arcade_mesh("Wheel %d" % widx) if widx > 0 else null
	var waabb := wmesh.get_aabb() if wmesh else AABB()
	var mesh_side := signf(waabb.get_center().x) if wmesh else 1.0
	if mesh_side == 0.0:
		mesh_side = 1.0
	for pivot in wheels:
		if pivot.get_meta("is_front"):
			axle_f_z = pivot.position.z
		hub_y = pivot.position.y
		if wmesh == null:
			continue
		var radius_local: float = float(pivot.get_meta("wheel_radius")) / s_c
		var ws := radius_local / maxf(waabb.size.y * 0.5, 0.001)
		for old in pivot.get_children():
			if old is Node3D:
				(old as Node3D).visible = false
		var w := _arcade_part(wmesh, paint, 0, 0)
		w.name = "Wheel"
		var side := signf(pivot.position.x - cx)
		if side == 0.0:
			side = 1.0
		var rot := Basis.IDENTITY if side == mesh_side else Basis(Vector3.UP, PI)
		# Наружная плоскость аркадного колеса — на месте родной.
		var outer := absf(waabb.end.x if mesh_side > 0 else waabb.position.x) * ws
		var shift := (float(pivot.get_meta("half_width", outer)) - outer) * side
		w.transform = Transform3D(rot.scaled(Vector3.ONE * ws), Vector3(shift, 0, 0))
		pivot.add_child(w)

	var r := len * 0.06
	var fwd := Vector3(0, 0, nose)
	var basis := Basis.IDENTITY if nose > 0 else Basis(Vector3.UP, PI)
	for slot in ["engine", "spoiler", "exhaust"]:
		var idx := int(cfg.get(slot, 0))
		if idx <= 0:
			continue
		var mesh := _arcade_mesh("%s %d" % [slot.capitalize(), idx])
		if mesh == null:
			continue
		# Габариты меша детали в единицах кузова (по z — вперёд от её
		# начала на a.end.z, назад на -a.position.z).
		var a := mesh.get_aabb()
		var pos := Vector3.ZERO
		match slot:
			"engine":
				# На капоте чуть позади передней оси, низом по капоту.
				var ez := axle_f_z - nose * len * 0.05
				pos = Vector3(cx, _top_at(verts, cx, ez, r, aabb.end.y), ez)
			"spoiler":
				# Меш спойлера почти весь ПОЗАДИ своего начала (аркадные
				# кузова кончаются сразу за слотом); на советском кузове
				# сдвигаем вперёд, чтобы крыло не висело за багажником:
				# хвост меша — в 15 % его длины за кормой.
				var sz := z_rear + nose * (-a.position.z * 0.85) * k
				# Зубило и Девятка (04.09 вечер): крыло — у самой кормы, на
				# нижней кромке двери багажника (верх кузова там — низ двери,
				# над бампером); вперёд на крышу, как остальные хэтчбеки,
				# не идём.
				if LOW_SPOILER_HATCH.has(base):
					# Нижняя кромка двери — первая точка от кормы, где верх
					# кузова поднимается выше 52 см от низа (бампер и фонари
					# ниже, стекло выше): идём вперёд шагом 1 % длины.
					var y_lid := aabb.position.y + 0.52 / s_c
					var lz := z_rear + nose * len * 0.01
					var y_top := _top_at(verts, cx, lz, rs_low(len), aabb.end.y)
					while y_top < y_lid and (lz - z_rear) * nose < len * 0.4:
						lz += nose * len * 0.01
						y_top = _top_at(verts, cx, lz, rs_low(len), aabb.end.y)
					pos = Vector3(cx, y_top, lz)
					if fix.has(slot):
						var f0: Vector3 = fix[slot]
						pos += Vector3(f0.x, f0.y, 0) / s_c + fwd * (f0.z / s_c)
					var low := _arcade_part(mesh, _part_paint(cfg, slot, body_paint),
							0, 0, "", _paint_all(cfg, slot))
					low.name = slot.capitalize()
					low.transform = Transform3D(basis.scaled(Vector3.ONE * k), pos)
					m.add_child(low)
					continue
				# Хэтчбеки (Зубило, Девятка; жалоба 04.09): под этой точкой —
				# крутая дверь багажника, лапа вставала посреди стекла, а
				# крыло висело в воздухе. Идём вперёд шагами 2 % длины, пока
				# верх под лапой не станет пологим (подъём < 35 % на 6 %
				# длины): на седане это сразу багажник, на хэтчбеке —
				# задняя кромка крыши (лапу ставим на r за кромку, чтобы
				# целиком стояла на крыше).
				var probe := len * 0.06
				var rs := len * 0.015
				var limit := z_rear + nose * len * 0.55
				var moved := false
				while (limit - sz) * nose > 0.0:
					var y0 := _top_at(verts, cx, sz, rs, aabb.end.y)
					var y1 := _top_at(verts, cx, sz + nose * probe, rs, aabb.end.y)
					if y1 - y0 < probe * 0.35:
						break
					sz += nose * len * 0.02
					moved = true
				if moved:
					sz += nose * r
				pos = Vector3(cx, _top_at(verts, cx, sz, r, aabb.end.y), sz)
			"exhaust":
				# Трубы целиком позади начала. Сажаем их на нижнюю кромку
				# бампера (_bumper_edge: самая кормовая точка кузова не выше
				# пояса и низ кузова у неё): центр трубы — на кромке, так
				# что труба наполовину утоплена в бампер, наружу торчит
				# ~0.14 ед. пака от самой кормы. Раньше труба стояла на
				# днище в торце габарита — а низ кузова там уходит вперёд,
				# и трубы висели в воздухе (жалоба 04.09).
				var edge := _bumper_edge(verts, cx, aabb, nose, hub_y)
				var xz := (edge.x + (-a.position.z - 0.14) * k) * nose
				# Не выше 20 см от низа кузова (в единицах файла: /s_c). У
				# vz21 и vz05r кромка бампера находилась на 26-32 см — трубы
				# садились вровень с фонарями («выхлоп из фар», 04.09).
				var y_cap := aabb.position.y + 0.20 / s_c
				pos = Vector3(cx, minf(edge.y, y_cap), xz)
		if fix.has(slot):
			var f: Vector3 = fix[slot]
			pos += Vector3(f.x, f.y, 0) / s_c + fwd * (f.z / s_c)
		var part := _arcade_part(mesh, _part_paint(cfg, slot, body_paint), 0, 0,
				"", _paint_all(cfg, slot))
		part.name = slot.capitalize()
		part.transform = Transform3D(basis.scaled(Vector3.ONE * k), pos)
		m.add_child(part)


## Неоновая подсветка под днищем (04.09): пятно света на земле — плоский
## квад с радиальным градиентом в цвете неона (аддитивно, без теней —
## виден и днём) + OmniLight3D, подсвечивающий колёса и полотно (главное
## на тёмных трассах — ночной город, космос). Держатель «Underglow» —
## ребёнок модели, но в ОСЯХ МАШИНЫ: модель повёрнута и в единицах файла
## (масштаб 0.01 у FBX из Unity), поэтому держатель берёт обратный
## трансформ модели; base_y — низ модели (метры), как у build().
static func _attach_underglow(m: Node3D, color: String, base_y: float) -> void:
	var col := fx_color(color)
	var black := color == "black"
	var holder := Node3D.new()
	holder.name = "Underglow"
	holder.transform = m.transform.affine_inverse()

	var glow := MeshInstance3D.new()
	glow.name = "Glow"
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	quad.size = Vector2(2.7, 4.3)
	glow.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Чёрный «неон» — не свет, а тень под машиной: обычное смешивание
	# тёмного пятна (аддитивно чёрный невидим вовсе).
	if black:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		mat.albedo_color = Color(0.0, 0.0, 0.0, 0.8)
	else:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(col.r, col.g, col.b, 0.85)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mat.albedo_texture = _glow_texture()
	glow.material_override = mat
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# У самого низа колёс (+4 см). Было +12 см — на машинах с высокими
	# колёсами (Нива, Копейка) пятно резало шины поперёк на уровне ступицы
	# (жалоба 04.09 «неон поперёк колёс лежит»). Дорога в заезде при
	# обычном прогибе на 0–5 см выше низа модели — пятно всё ещё над ней.
	glow.position = Vector3(0.0, base_y + 0.04, 0.0)
	holder.add_child(glow)

	var light := OmniLight3D.new()
	light.name = "NeonLight"
	# Чёрный — «отрицательный» свет: гасит подсветку под днищем и колёса.
	light.light_color = Color.WHITE if black else col
	light.light_negative = black
	light.light_energy = 1.4 if black else 2.2
	light.omni_range = 3.2
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	light.position = Vector3(0.0, base_y + 0.25, 0.0)
	holder.add_child(light)
	m.add_child(holder)


# ---- Полоса вдоль кузова у советских и Unity-машин (04.09) ----
# У аркадных полоса — поверхность "sticker line" в UV-развёртке; у
# остальных паков такой развёртки нет, и полоса рисуется шейдером на
# ДУБЛЕ меша кузова, приподнятом по нормали на 4 мм (material_overlay в
# 4.3 Forward+ не рисуется — проверено стендом tools/shot_line_all.gd):
# две полосы по |x − cx| на верхних гранях (normal.y > 0.35); стёкла
# советского пака — клетка палитры (56, 81, 79) — не красятся, у Unity
# поверхности "glass"/"Black-T" на дубле невидимы.
const LINE_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec4 color : source_color = vec4(0.11, 0.11, 0.11, 1.0);
uniform float cx = 0.0;
uniform float half_w = 0.1;
uniform float gap = 0.05;
uniform float min_ny = 0.35;
uniform bool mask_glass = false;
uniform float lift = 0.0;
uniform sampler2D albedo_tex;
varying vec3 lpos;
varying vec3 lnorm;
void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
	VERTEX += NORMAL * lift;
}
void fragment() {
	float dx = abs(lpos.x - cx);
	if (dx < gap || dx > gap + 2.0 * half_w || lnorm.y < min_ny) {
		discard;
	}
	if (mask_glass) {
		vec3 t = texture(albedo_tex, UV).rgb;
		if (distance(t, vec3(56.0, 81.0, 79.0) / 255.0) < 0.04) {
			discard;
		}
	}
	ALBEDO = color.rgb;
	ROUGHNESS = 0.5;
	METALLIC = 0.0;
}
"""
static var _line_shader: Shader


## Материал-невидимка (все пиксели отсекаются) — для стёкол на дубле.
static func _hidden_material() -> StandardMaterial3D:
	var hid := StandardMaterial3D.new()
	hid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	hid.alpha_scissor_threshold = 0.5
	hid.albedo_color = Color(0, 0, 0, 0)
	return hid


## Меши КУЗОВА модели (без колёс в пивотах и без приставных деталей).
static func _body_meshes(m: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in m.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null \
				and not ["Engine", "Spoiler", "Exhaust", "Wheel"].has(String(c.name)):
			out.append(c as MeshInstance3D)
	return out


static func _attach_line(m: Node3D, _base: String, color_spec: String) -> void:
	if _line_shader == null:
		_line_shader = Shader.new()
		_line_shader.code = LINE_SHADER
	var bodies := _body_meshes(m)
	if bodies.is_empty():
		return
	var aabb := AABB()
	var first := true
	for mi in bodies:
		var a: AABB = mi.transform * mi.mesh.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
	var color := paint_color(color_spec, Color(0.113, 0.113, 0.113))
	for mi in bodies:
		var mat := ShaderMaterial.new()
		mat.shader = _line_shader
		# Центр и ширины — в ЛОКАЛЬНЫХ единицах меша (у FBX из Unity в
		# трансформе зашит масштаб 100: переводим обратным трансформом).
		var inv := mi.transform.affine_inverse()
		var kx := inv.basis.get_scale().x
		mat.set_shader_parameter("cx", (inv * Vector3(aabb.get_center().x, 0, 0)).x)
		mat.set_shader_parameter("half_w", aabb.size.x * 0.05 * kx)
		mat.set_shader_parameter("gap", aabb.size.x * 0.03 * kx)
		mat.set_shader_parameter("color", color)
		mat.set_shader_parameter("lift", 0.004 * kx / maxf(m.scale.x, 1e-6))
		var base_mat := mi.material_override as BaseMaterial3D
		if base_mat != null and base_mat.albedo_texture != null:
			mat.set_shader_parameter("mask_glass", true)
			mat.set_shader_parameter("albedo_tex", base_mat.albedo_texture)
		var dup := MeshInstance3D.new()
		dup.name = String(mi.name) + "_line"
		dup.mesh = mi.mesh
		dup.transform = mi.transform
		dup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.material_override != null:
			dup.material_override = mat
		else:
			for i in mi.mesh.get_surface_count():
				var sm := mi.mesh.surface_get_material(i)
				var nm := (sm.resource_name if sm else "").to_lower()
				if nm.contains("glass") or nm.contains("black-t"):
					dup.set_surface_override_material(i, _hidden_material())
				else:
					dup.set_surface_override_material(i, mat)
		m.add_child(dup)


# ---- Тонировка стёкол (04.09) ----
# Стекло в паках сидит по-разному: советский — одна клетка палитры
# albedo.png (56, 81, 79), аркадный — тёмно-серые ячейки палитры
# ColorPalette.png (x 436–472, y 0–26; туда же смотрят UV окон всех восьми
# кузовов — стенд tools/dump_glass_cells.gd), Unity — отдельные поверхности
# "…glass". Для палитр делаем КОПИЮ текстуры с перекрашенной клеткой и
# вешаем её только на кузов (колёса и детали остаются на общей).
const SOVIET_GLASS_CELL := Color8(56, 81, 79)
static var _glass_mats := {}   # ключ → материал


## Цвет тонировки: краска эффекта, чуть приглушённая к «стеклянному».
static func glass_tint(color: String) -> Color:
	var c := fx_color(color)
	if color == "white":
		return Color(0.86, 0.9, 0.92)
	if color == "black":
		return Color(0.06, 0.06, 0.07)
	return c.lerp(Color(0.22, 0.32, 0.31), 0.3)


static func _apply_glass(m: Node3D, base: String, color: String) -> void:
	var tint := glass_tint(color)
	if SOVIET_IDS.has(base):
		var mat := _soviet_glass_material(color, tint)
		if mat == null:
			return
		for mi in _body_meshes(m):
			if mi.material_override != null:
				mi.material_override = mat
	elif is_arcade(base):
		var body := m.get_node_or_null("Body") as MeshInstance3D
		if body == null:
			return
		var mat := _arcade_glass_material(color, tint)
		for i in body.mesh.get_surface_count():
			var sm := body.mesh.surface_get_material(i)
			if sm != null and sm.resource_name == "details":
				body.set_surface_override_material(i, mat)
	else:
		for mi in _body_meshes(m):
			for i in mi.mesh.get_surface_count():
				var sm := mi.mesh.surface_get_material(i)
				var nm := (sm.resource_name if sm else "").to_lower()
				if not nm.contains("glass"):
					continue
				var key := "unity:%s:%s" % [nm, color]
				if not _glass_mats.has(key):
					var g := (sm as BaseMaterial3D).duplicate() as BaseMaterial3D \
							if sm is BaseMaterial3D else StandardMaterial3D.new()
					g.albedo_color = tint
					g.albedo_texture = null
					_glass_mats[key] = g
				mi.set_surface_override_material(i, _glass_mats[key])


## Копия советского материала с перекрашенной клеткой стекла в палитре.
static func _soviet_glass_material(color: String, tint: Color) -> StandardMaterial3D:
	var key := "soviet:" + color
	if _glass_mats.has(key):
		return _glass_mats[key]
	var src := _soviet_material()
	var tex := src.albedo_texture as ImageTexture
	if tex == null:
		return null
	var img := tex.get_image().duplicate() as Image
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if absf(c.r - SOVIET_GLASS_CELL.r) < 0.03 and absf(c.g - SOVIET_GLASS_CELL.g) < 0.03 \
					and absf(c.b - SOVIET_GLASS_CELL.b) < 0.03:
				img.set_pixel(x, y, tint)
	var mat := src.duplicate() as StandardMaterial3D
	mat.albedo_texture = ImageTexture.create_from_image(img)
	_glass_mats[key] = mat
	return mat


## Материал "details" аркадного пака с перекрашенными стёклами в палитре:
## тёмно-серые ячейки окон (x 436–472, y 0–26) — в оттенки выбранного
## цвета с сохранением их светлоты, шины/решётки на других клетках не
## трогаются.
static func _arcade_glass_material(color: String, tint: Color) -> StandardMaterial3D:
	var key := "arcade:" + color
	if _glass_mats.has(key):
		return _glass_mats[key]
	var base := _arcade_material("details")
	var tex := base.albedo_texture as ImageTexture
	if tex == null:
		return base
	var img := tex.get_image().duplicate() as Image
	for y in range(0, mini(26, img.get_height())):
		for x in range(436, mini(472, img.get_width())):
			var c := img.get_pixel(x, y)
			var lum := (c.r + c.g + c.b) / 3.0
			if lum < 0.45:
				# Светлота ячейки (0.05–0.3) задаёт глубину тонировки.
				var k := clampf(lum / 0.3, 0.25, 1.0)
				img.set_pixel(x, y, Color(tint.r * k, tint.g * k, tint.b * k))
	var mat := base.duplicate() as StandardMaterial3D
	mat.albedo_texture = ImageTexture.create_from_image(img)
	_glass_mats[key] = mat
	return mat


## Радиальный градиент пятна неона (белый, прозрачность к краю); общий.
static var _glow_tex: GradientTexture2D


static func _glow_texture() -> GradientTexture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1.0))
		g.set_color(1, Color(1, 1, 1, 0.0))
		g.add_point(0.35, Color(1, 1, 1, 0.75))
		g.add_point(0.7, Color(1, 1, 1, 0.25))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 128
		t.height = 128
		_glow_tex = t
	return _glow_tex
