class_name Weapons
extends RefCounted
## Реестр видов оружия. В руках может быть только ОДНО оружие: одно даётся
## на старте, дальше — из боксов на трассе (случайный вид).

enum {
	MINE,       # мина: наехал — взрыв; эпицентр уничтожает, дальних расталкивает
	ROCKET,     # ракета вперёд: уничтожает машину, в которую врезалась
	OIL,        # масляное пятно: наехавшего заносит
	MAGNET,     # магнит: все машины разово притягивает к использовавшему
	LASER,      # лазер: один луч, уничтожает всех на пути
	FREEZE,     # ледышка: попавший синеет и едет медленно, дебаф заразен
	AIRSTRIKE,  # авиаудар по лидеру: тени → через секунду ракеты сверху
	BOOST,      # ускорение самому себе на время
	SCRAMBLE,   # глушилка: звуковая волна вперёд — у попавшего на время
	            # МЕНЯЮТСЯ МЕСТАМИ лево и право (руль инвертирован)
	SHIELD,     # щит: сфера вокруг своей машины на SHIELD_TIME — чужое
	            # оружие и бонусы не действуют; II — коснувшихся замедляет,
	            # III (красный) — коснувшихся уничтожает (см. Car.apply_shield)
}
const COUNT := 10
## Сколько держится щит, с (спецификация игрока 08.09: «5 сек»; I ступень —
## на 15 % дольше по общему правилу экономики, II и III длину не меняют).
const SHIELD_TIME := 5.0

const NAMES := {
	MINE: "Мина",
	ROCKET: "Ракета",
	OIL: "Масло",
	MAGNET: "Магнит",
	LASER: "Лазер",
	FREEZE: "Заморозка",
	AIRSTRIKE: "Авиаудар",
	BOOST: "Ускорение",
	SCRAMBLE: "Глушилка",
	SHIELD: "Щит",
}

# Восьмиугольные значки «гаражного» стиля (нарезаны из референса
# _STYLE_CORE_A_sheet_of_12_weap_2.jpg скриптом tools/gen_ui_assets.py).
const ICONS := {
	MINE: "res://assets/ui/garage/wg_mine.png",
	ROCKET: "res://assets/ui/garage/wg_rocket.png",
	OIL: "res://assets/ui/garage/wg_oil.png",
	MAGNET: "res://assets/ui/garage/wg_magnet.png",
	LASER: "res://assets/ui/garage/wg_laser.png",
	FREEZE: "res://assets/ui/garage/wg_freeze.png",
	AIRSTRIKE: "res://assets/ui/garage/wg_airstrike.png",
	BOOST: "res://assets/ui/garage/wg_boost.png",
	# Запечён tools/gen_scramble_icon.py (в листе-референсе волны не было).
	SCRAMBLE: "res://assets/ui/garage/wg_scramble.png",
	# Картинка игрока (08.09), вырезана tools/cut_shield_icon.py.
	SHIELD: "res://assets/ui/garage/wg_shield.png",
}


# ════════════════════ СТУПЕНИ ОРУЖИЯ (магазин, 08.09) ════════════════════
# У каждого вида три ступени I/II/III, покупаются в гараже ПО ПОРЯДКУ за
# монеты, каждая открывается уровнем профиля (ЭКОНОМИКА.md, раздел 7).
# Виды разбиты на группы по силе: лёгкие раньше и дешевле, тяжёлые —
# позже и дороже. Ступень — свойство ИГРОКА (GameState.weapon_upgrades),
# машина получает её набором Car.weapon_steps (по сети — в hello).
# Что даёт ступень — спецификация игрока от 04.09 (уровни I/II/III), а
# где она молчит — числовые ступени экономики (+15 % силы, +20 %
# длительности/скорости). III ступень у ЛЮБОГО вида вдобавок роняет его
# из бокса в 1.5 раза чаще (random_weapon).
const STEPS := 3
const ROMAN := ["", "I", "II", "III"]
const GROUP_OF := {
	MINE: "A", OIL: "A", BOOST: "A",
	MAGNET: "B", FREEZE: "B", SCRAMBLE: "B", SHIELD: "B",
	ROCKET: "C", LASER: "C", AIRSTRIKE: "C",
}
const GROUP_NAMES := {"A": "лёгкое", "B": "среднее", "C": "тяжёлое"}
const STEP_LEVELS := {"A": [3, 7, 14], "B": [4, 9, 18], "C": [6, 11, 22]}
const STEP_PRICES := {
	"A": [500, 1500, 4000],
	"B": [800, 2500, 6500],
	"C": [1200, 4000, 10000],
}
## Описание ступеней I, II, III (что ПРИБАВЛЯЕТ каждая к предыдущей).
const STEP_DESC := {
	MINE: ["взрыв шире на 15 %",
			"две мины — под левое и правое колесо",
			"выпадает из бокса в 1.5 раза чаще"],
	ROCKET: ["ракета крупнее: попадание на 15 % шире",
			"самонаведение — доворачивает на соперника рядом с курсом",
			"выпадает из бокса в 1.5 раза чаще"],
	OIL: ["пятно на 15 % больше",
			"наехавшего заносит и крутит (без II — только замедляет)",
			"выпадает из бокса в 1.5 раза чаще"],
	MAGNET: ["рывок сильнее на 15 %",
			"жертвы теряют всю скорость",
			"выпадает из бокса в 1.5 раза чаще"],
	LASER: ["луч шире на 15 %",
			"бьёт через всю трассу — без предела дальности",
			"луч держится дольше и выпадает в 1.5 раза чаще"],
	FREEZE: ["заморозка держится на 15 % дольше",
			"ледышка летит на 20 % быстрее",
			"выпадает из бокса в 1.5 раза чаще"],
	AIRSTRIKE: ["воронки шире на 15 %",
			"три ракеты, с упреждением по едущим впереди",
			"четыре ракеты и выпадает в 1.5 раза чаще"],
	BOOST: ["ускорение держится на 15 % дольше",
			"ускорение держится в полтора раза дольше",
			"ускоряет сильнее и выпадает в 1.5 раза чаще"],
	SCRAMBLE: ["сбитое управление держится на 15 % дольше",
			"волна летит на 30 % быстрее",
			"выпадает из бокса в 1.5 раза чаще"],
	# Щит (спецификация игрока 08.09): I — 5 с защиты (+15 % по экономике),
	# II — жёлтый щит, коснувшийся соперник теряет скорость, III — красный
	# щит, коснувшийся соперник уничтожен.
	SHIELD: ["щит держится на 15 % дольше",
			"жёлтый щит: коснувшийся соперник теряет скорость",
			"красный щит: коснувшийся соперник взрывается; выпадает в 1.5 раза чаще"],
}
const DROP_BONUS := 1.5   # вес в боксе при III ступени


static func group_of(kind: int) -> String:
	return GROUP_OF.get(kind, "A")


## С какого уровня профиля продаётся ступень step (1..3) этого вида.
static func step_level(kind: int, step: int) -> int:
	var lv: Array = STEP_LEVELS[group_of(kind)]
	return int(lv[clampi(step, 1, STEPS) - 1])


static func step_price(kind: int, step: int) -> int:
	var pr: Array = STEP_PRICES[group_of(kind)]
	return int(pr[clampi(step, 1, STEPS) - 1])


static func step_desc(kind: int, step: int) -> String:
	var d: Array = STEP_DESC.get(kind, [])
	var i := clampi(step, 1, STEPS) - 1
	return str(d[i]) if i < d.size() else ""


## Ступень вида из набора машины (PackedByteArray на COUNT видов; пустой
## или короткий набор — нулевые ступени: боты, старые записи).
static func step_of(steps: PackedByteArray, kind: int) -> int:
	if kind < 0 or kind >= steps.size():
		return 0
	return clampi(steps[kind], 0, STEPS)


## Имя с римской ступенью для HUD: «Ракета II» (I ступень не пишется —
## она читается как «обычная»; 0 — тоже без приписки).
static func display_name_step(kind: int, step: int) -> String:
	if step >= 2:
		return "%s %s" % [display_name(kind), ROMAN[step]]
	return display_name(kind)


## Случайное оружие, шансы с поправкой на положение в гонке:
## - is_last: машина идёт ПОСЛЕДНЕЙ — мина и масло выпадают вдвое реже
##   (они бьют назад, а сзади никого нет);
## - behind_gap: отставание от лидера, м — сильно отставшему чаще выпадает
##   ускорение: вес растёт с 30 м отставания и к 110 м достигает ×3.
## - exclude: вид, который НЕ выдавать (то, что уже в руках: подбор бокса
##   без смены значка читался как «проехал сквозь бонус», 03.09).
## - steps: ступени оружия машины — виды на III ступени выпадают в
##   DROP_BONUS раз чаще (магазин, 08.09).
## Без аргументов — равновероятно (старт заезда, стенды).
static func random_weapon(is_last := false, behind_gap := 0.0,
		exclude := -1, steps := PackedByteArray()) -> int:
	var weights: Array[float] = []
	weights.resize(COUNT)
	weights.fill(1.0)
	if exclude >= 0 and exclude < COUNT:
		weights[exclude] = 0.0
	if is_last:
		weights[MINE] = 0.5
		weights[OIL] = 0.5
	var far: float = clampf((behind_gap - 30.0) / 80.0, 0.0, 1.0)
	weights[BOOST] = 1.0 + 2.0 * far
	for kind in COUNT:
		if step_of(steps, kind) >= STEPS:
			weights[kind] *= DROP_BONUS
	var total := 0.0
	for w in weights:
		total += w
	var roll := randf() * total
	var last := COUNT - 1
	for kind in COUNT:
		if weights[kind] <= 0.0:
			continue
		last = kind
		roll -= weights[kind]
		if roll <= 0.0:
			return kind
	return last  # страховка от накопленной погрешности float


static func display_name(kind: int) -> String:
	return NAMES.get(kind, "—")


static func icon(kind: int) -> Texture2D:
	if not ICONS.has(kind):
		return null
	return load(ICONS[kind])
