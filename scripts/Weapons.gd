class_name Weapons
extends RefCounted
## Реестр видов оружия. В руках может быть только ОДНО оружие: одно даётся
## на старте, дальше — из боксов на трассе (случайный вид).

enum {
	MINE,       # мина: наехал — взрыв, всех расталкивает
	ROCKET,     # ракета вперёд: уничтожает машину, в которую врезалась
	OIL,        # масляное пятно: наехавшего заносит
	MAGNET,     # магнит: все машины разово притягивает к использовавшему
	LASER,      # лазер: один луч, уничтожает всех на пути
	FREEZE,     # ледышка: попавший синеет и едет медленно, дебаф заразен
	AIRSTRIKE,  # авиаудар по лидеру: тени → через секунду ракеты сверху
	BOOST,      # ускорение самому себе на время
}
const COUNT := 8

const NAMES := {
	MINE: "Мина",
	ROCKET: "Ракета",
	OIL: "Масло",
	MAGNET: "Магнит",
	LASER: "Лазер",
	FREEZE: "Заморозка",
	AIRSTRIKE: "Авиаудар",
	BOOST: "Ускорение",
}

# Мультяшные иконки (GUI Pack Cartoon) — для слота оружия в HUD.
const ICONS := {
	MINE: "res://assets/ui/w_mine.png",
	ROCKET: "res://assets/ui/w_rocket.png",
	OIL: "res://assets/ui/w_oil.png",
	MAGNET: "res://assets/ui/w_magnet.png",
	LASER: "res://assets/ui/w_laser.png",
	FREEZE: "res://assets/ui/w_freeze.png",
	AIRSTRIKE: "res://assets/ui/w_airstrike.png",
	BOOST: "res://assets/ui/w_boost.png",
}


static func random_weapon() -> int:
	return randi() % COUNT


static func display_name(kind: int) -> String:
	return NAMES.get(kind, "—")


static func icon(kind: int) -> Texture2D:
	if not ICONS.has(kind):
		return null
	return load(ICONS[kind])
