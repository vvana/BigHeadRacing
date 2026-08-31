extends Node3D
## Автотест «догрузился после старта» (жалоба 31.08: «второй игрок
## несколько раз появлялся не у старта, а далеко впереди — я его даже не
## видел на своём экране»).
##
## НОВЫХ игроков начавшийся заезд с 31.08 не берёт вовсе — им поднимают
## свою комнату. Но остаётся один путь в идущую гонку: игрок БЫЛ в лобби,
## а догрузился позже старта (заезд ушёл без него по HELLO_GRACE), и его
## машину всё это время вёл бот. Раньше игроку отдавали ровно то место,
## где ехал бот (_rx_race_running), и он появлялся впереди всех. Теперь
## Main._seat_joiner_at_tail сажает его в хвост поля.
##
## Проверяем: машина уехавшего вперёд слота переезжает НАЗАД, за самую
## отставшую машину, и её прогресс (место в HUD, круги) пересчитан.
## И обратное правило: кто и так позади всех, с места не двигается —
## подсадка не должна отбирать у игрока то, что он честно проехал.

var _main: Node3D
var _frame := 0


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame != 20:
		return
	# Расставляем поле по трассе: слот 1 (подсевший) — далеко впереди.
	_place(0, 60.0)
	_place(1, 400.0)
	_place(2, 40.0)
	_place(3, 90.0)
	var ahead: float = _main._progress[1]
	_main._seat_joiner_at_tail(1)
	var joiner: Car = _main._cars[1]
	var tail: Car = _main._cars[2]
	var dist := joiner.global_position.distance_to(tail.global_position)
	var behind: bool = _main._progress[1] < _main._progress[2]
	var moved: float = ahead - _main._progress[1]
	# Второй случай: уже позади всех — не трогаем.
	_place(1, 10.0)
	var low: float = _main._progress[1]
	var pos_before: Vector3 = joiner.global_position
	_main._seat_joiner_at_tail(1)
	var kept: bool = is_equal_approx(low, _main._progress[1]) \
			and joiner.global_position.is_equal_approx(pos_before)

	var ok: bool = behind and dist < 15.0 and moved > 200.0 and kept
	print("JOIN TAIL TEST: %s (сдвинут назад на %.0f м, до хвоста %.1f м, "
			% ["PASS" if ok else "FAIL", moved, dist]
			+ "отставший не тронут=%s)" % str(kept))
	get_tree().quit(0 if ok else 1)


## Поставить машину i на отметку трассы off и привести к ней счётчики.
func _place(i: int, off: float) -> void:
	var car: Car = _main._cars[i]
	car.global_transform = _main._track.respawn_transform_at(off)
	car.linear_velocity = Vector3.ZERO
	car.reset_track_offset()
	_main._progress[i] = car.track_offset
	_main._last_offset[i] = car.track_offset
