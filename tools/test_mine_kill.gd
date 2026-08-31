extends Node3D
## Автотест мины: наезд её не просто расталкивает, а УНИЧТОЖАЕТ машину
## (31.08: «пусть мина взрывает авто»). Проверяем обе половины правила:
##   1) машина в эпицентре гибнет — становится «призраком» (мигание и
##      неуязвимость) и переезжает к месту появления на трассе;
##   2) машина ДАЛЬШЕ смертельного радиуса не гибнет, а получает прежний
##      толчок взрывной волной;
##   3) событие взрыва мины с сервера (Main._rx_mine_fx) убирает у клиента
##      инертную копию мины — она о срабатывании не знает сама.
## На старом коде первая половина FAIL: наехавшего только отшвыривало.

var _main: Node3D
var _frame := 0
var _mine: Mine
var _victim: Car
var _far: Car
var _inert: Mine
var _victim_pos := Vector3.ZERO
var _far_vel := Vector3.ZERO


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	_frame += 1
	match _frame:
		20:
			_victim = _main._cars[0]
			_far = _main._cars[1]
			# Мину кладём вручную: сброс за корму сразу под собой стенду
			# не нужен — нужна взведённая мина в известной точке.
			_mine = Mine.new()
			_mine.dropper = _main._cars[2]
			_main.add_child(_mine)
			_mine.global_position = _victim.global_position \
					+ Vector3.UP * 0.2
			# Дальняя машина — за смертельным радиусом, но в радиусе взрыва.
			_far.global_position = _mine.global_position \
					+ Vector3.RIGHT * 7.0 + Vector3.UP * 0.4
			_far.linear_velocity = Vector3.ZERO
			_victim_pos = _victim.global_position
		68:
			# Заодно проверяем клиентскую половину: событие взрыва мины
			# (Main._rx_mine_fx) обязано убрать ИНЕРТНУЮ копию — она о
			# срабатывании не знает и иначе лежала бы на дороге до конца
			# жизни, пока машины рядом разлетаются «сами по себе».
			var ghost_mine := Mine.new()
			ghost_mine.inert = true
			_main.add_child(ghost_mine)
			ghost_mine.global_position = _victim_pos + Vector3.UP * 0.2
			_inert = ghost_mine
			_main._rx_mine_fx(_victim_pos)
		70:
			# Мина взводится 0.7 c и рвётся под стоящей на ней машиной.
			_far_vel = _far.linear_velocity
			var moved := _victim.global_position.distance_to(_victim_pos)
			var cleaned := not is_instance_valid(_inert) or _inert.is_queued_for_deletion()
			var ok := _victim.is_ghost() and moved > 1.0 \
					and _far_vel.length() > 3.0 and not _far.is_ghost() \
					and cleaned
			print("MINE KILL TEST: %s (жертва призрак=%s, переехала на %.1f м; "
					% ["PASS" if ok else "FAIL", str(_victim.is_ghost()), moved]
					+ "дальнюю толкнуло на %.1f м/с, призрак=%s; "
					% [_far_vel.length(), str(_far.is_ghost())]
					+ "инертная копия убрана=%s)" % str(cleaned))
			get_tree().quit(0 if ok else 1)
