extends Node3D
## Автотест: МЕСТО В HUD И МЕСТО НА БАННЕРЕ ФИНИША — одно и то же число.
##
## До 26.08 они считались по-разному и расходились на глазах у игрока: HUD
## сравнивал накопленный путь всех машин, а баннер выдавал место по порядку
## пересечения финиша. Доехавшая машина останавливается, её путь замирает —
## и едущий сзади «обгонял» её в HUD, хотя первое место уже занято. Игрок
## присылал скриншот: в углу «МЕСТО 2/4», на баннере «ФИНИШ! МЕСТО 3 ИЗ 4».
##
## Стенд гоняет не всю четырёхкруговую гонку (это минуты), а саму арифметику
## мест: расставляет прогресс машин и порядок финиша руками и сверяет
## _place_of с тем, что видел бы игрок.

var _main: Node3D
var _frames := 0
var _ok := {}


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames < 10:
		return

	# 1. Никто не финишировал — место по накопленному пути, как и раньше.
	_set_progress([300.0, 500.0, 100.0, 400.0])
	_ok["без финишировавших: место по пути"] = _main._place_of(0) == 3 \
			and _main._place_of(1) == 1 and _main._place_of(2) == 4

	# 2. Машина 1 финишировала первой и ВСТАЛА (её путь больше не растёт),
	# машина 0 катится дальше и обходит её по метражу. Первое место уже
	# занято — машине 0 положено второе, а не первое.
	_main._finish_order = [1] as Array[int]
	_set_progress([600.0, 500.0, 100.0, 400.0])
	_ok["финишёр держит своё место"] = _main._place_of(1) == 1
	_ok["обогнавший по метражу — второй"] = _main._place_of(0) == 2

	# 3. Финишировали двое: места 1 и 2 заняты, остальные делят 3 и 4 по пути.
	_main._finish_order = [1, 3] as Array[int]
	_set_progress([600.0, 500.0, 100.0, 400.0])
	_ok["второй финишёр держит место 2"] = _main._place_of(3) == 2
	_ok["едущие делят места ниже"] = _main._place_of(0) == 3 \
			and _main._place_of(2) == 4

	# 4. Главное: своё место в HUD после финиша совпадает с баннером. Место
	# на баннере — это номер в порядке пересечения (_car_finished), место в
	# HUD — _place_of. Проверяем для каждого финишёра сразу.
	var same := true
	_main._finish_order = [2, 0, 3, 1] as Array[int]
	for place in _main._finish_order.size():
		var car: int = _main._finish_order[place]
		if _main._place_of(car) != place + 1:
			same = false
	_ok["HUD и баннер показывают одно место"] = same

	var all_ok := true
	for k: String in _ok:
		if not _ok[k]:
			all_ok = false
		print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
	print("PLACEFINISH TEST: %s" % ("PASS" if all_ok else "FAIL"))
	get_tree().quit(0 if all_ok else 1)


func _set_progress(vals: Array) -> void:
	for i in mini(vals.size(), _main._progress.size()):
		_main._progress[i] = vals[i]
