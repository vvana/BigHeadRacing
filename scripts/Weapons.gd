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
}
const COUNT := 9

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
}


## Случайное оружие, шансы с поправкой на положение в гонке:
## - is_last: машина идёт ПОСЛЕДНЕЙ — мина и масло выпадают вдвое реже
##   (они бьют назад, а сзади никого нет);
## - behind_gap: отставание от лидера, м — сильно отставшему чаще выпадает
##   ускорение: вес растёт с 30 м отставания и к 110 м достигает ×3.
## - exclude: вид, который НЕ выдавать (то, что уже в руках: подбор бокса
##   без смены значка читался как «проехал сквозь бонус», 03.09).
## Без аргументов — равновероятно (старт заезда, стенды).
static func random_weapon(is_last := false, behind_gap := 0.0,
		exclude := -1) -> int:
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
