extends Node3D
## Стенд НАКОПЛЕНИЯ между заездами. Клиент за вечер перезагружает сцену
## гонки десятки раз: после каждого заезда (_rx_reset), при смене трассы
## (_rx_track), при переезде в комнату (_rx_redirect). Если что-то
## переживает разбор сцены, за вечер это вырастет в гору.
##
## Цикл: собрать гонку из Main.tscn -> погонять CYCLE_SEC с эффектами ->
## освободить целиком -> замерить. Растущие от цикла к циклу числа и есть
## накопление. Освобождение через free() (не queue_free): нужен ТОЧНЫЙ
## замер сразу после разбора, а не «когда-нибудь в конце кадра».
##
## Запуск:
##   godot --headless --path . res://tools/TestMemCycle.tscn
## Число циклов — аргументом после `--`.

const CYCLE_SEC := 6.0

var _main: Node3D
var _t := 0.0
var _next_fire := 0.0
var _cycle := 0
var _cycles := 10
var _out: FileAccess


func _say(s: String) -> void:
	print(s)
	if _out != null:
		_out.store_line(s)
		_out.flush()


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.is_valid_int():
			_cycles = maxi(2, a.to_int())
	_out = FileAccess.open("res://memcycle_report.txt", FileAccess.WRITE)
	_say("=== СТЕНД НАКОПЛЕНИЯ: %d циклов по %.0f с ===" % [_cycles, CYCLE_SEC])
	_say("цикл | память МБ | объектов | узлов | СИРОТ | ресурсов")
	_start_cycle()


func _start_cycle() -> void:
	_cycle += 1
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	_t = 0.0
	_next_fire = 0.5


func _end_cycle() -> void:
	remove_child(_main)
	_main.free()
	_main = null
	_say("%4d | %9.1f | %8d | %5d | %5d | %8d" % [
			_cycle,
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)])
	if _cycle >= _cycles:
		_say("Если числа растут от цикла к циклу — разбор сцены что-то не отпускает.")
		if _out != null:
			_out.close()
		get_tree().quit(0)
		return
	_start_cycle()


func _physics_process(delta: float) -> void:
	if _main == null:
		return
	_t += delta
	if _t >= _next_fire:
		_next_fire = _t + 0.5
		var cars: Array = _main._cars
		for i in cars.size():
			var car: Car = cars[i]
			if not is_instance_valid(car) or not car.alive:
				continue
			car.weapon = randi() % Weapons.COUNT
			car.use_weapon()
	if _t >= CYCLE_SEC:
		_end_cycle()
