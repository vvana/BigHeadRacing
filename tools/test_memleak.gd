extends Node3D
## Стенд поиска УТЕЧЕК ПАМЯТИ. Гоняет обычный офлайн-заезд и раз в 20 с
## снимает перепись: сколько всего объектов, узлов, СИРОТ (узлов вне
## дерева — их никто не освободит) и сколько узлов каждого класса висит
## в сцене. Растущий из замера в замер класс и есть утечка.
##
## Чтобы эффекты шли гуще, чем в обычной гонке, стенд каждые 0.5 с выдаёт
## всем машинам случайное оружие и жмёт «огонь»: мины, ракеты, масло,
## лазеры, взрывы, следы шин, искры — весь косметический слой работает.
##
## Запуск:
##   godot --headless --path . res://tools/TestMemLeak.tscn
## Дольше/короче — аргументом после `--` (секунды):
##   godot --headless --path . res://tools/TestMemLeak.tscn -- 300

var _main: Node3D
var _t := 0.0
var _next_sample := 0.0
var _next_fire := 2.0
var _duration := 200.0
var _samples: Array = []
var _out: FileAccess


## Пишем И в консоль, И в файл со сбросом буфера: stdout headless-Godot,
## уходя в файл, буферизуется блоками — при обрыве прогона не остаётся
## ничего. Отчёт нужен даже от недосчитанного прогона.
func _say(s: String) -> void:
	print(s)
	if _out != null:
		_out.store_line(s)
		_out.flush()


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.is_valid_float():
			_duration = maxf(20.0, a.to_float())
	_out = FileAccess.open("res://memleak_report.txt", FileAccess.WRITE)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	_say("=== СТЕНД УТЕЧЕК: %.0f с, замер каждые 20 с ===" % _duration)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= _next_fire:
		_next_fire = _t + 0.5
		_fire_everything()
	if _t >= _next_sample:
		_next_sample = _t + 20.0
		_sample()
	if _t >= _duration:
		_report()
		get_tree().quit(0)


## Всем машинам — случайное оружие и выстрел. Заодно каждые 4 с одну
## машину подрываем: взрыв, «призрак», респавн — самый богатый на эффекты
## путь.
func _fire_everything() -> void:
	var cars: Array = _main._cars
	for i in cars.size():
		var car: Car = cars[i]
		if not is_instance_valid(car) or not car.alive:
			continue
		car.weapon = randi() % Weapons.COUNT
		car.use_weapon()
	if int(_t) % 4 == 0 and cars.size() > 0:
		var victim: Car = cars[randi() % cars.size()]
		if is_instance_valid(victim) and victim.alive:
			victim.destroy()


## Перепись узлов сцены по классам (только те, кого больше одного —
## одиночки в отчёте лишь мешают).
func _census() -> Dictionary:
	var by_class := {}
	var stack: Array[Node] = [_main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var key := n.get_class()
		var scr: Script = n.get_script() as Script
		if scr != null:
			key = "%s(%s)" % [key, scr.resource_path.get_file()]
		by_class[key] = int(by_class.get(key, 0)) + 1
		for c in n.get_children():
			stack.append(c)
	return by_class


func _sample() -> void:
	var census := _census()
	_samples.append({"t": _t, "census": census})
	_say("[%3.0f c] память %.1f МБ | объектов %d | узлов %d | СИРОТ %d | ресурсов %d | в сцене %d"
			% [_t,
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			_count(census)])


func _count(census: Dictionary) -> int:
	var total := 0
	for k: String in census:
		total += int(census[k])
	return total


## Итог: какие классы выросли от ПЕРВОГО замера к последнему. Разовые
## всплески (эффект живёт 2 с) в замер попадают случайно, поэтому смотрим
## и на середину — устойчивый рост виден по всем трём точкам.
func _report() -> void:
	if _samples.size() < 2:
		_say("МАЛО ЗАМЕРОВ")
		return
	var first: Dictionary = _samples[0]["census"]
	var mid: Dictionary = _samples[_samples.size() / 2]["census"]
	var last: Dictionary = _samples[-1]["census"]
	_say("=== РОСТ ПО КЛАССАМ (первый замер -> середина -> последний) ===")
	var keys := {}
	for d: Dictionary in [first, mid, last]:
		for k: String in d:
			keys[k] = true
	var rows: Array = []
	for k: String in keys:
		var a := int(first.get(k, 0))
		var b := int(mid.get(k, 0))
		var c := int(last.get(k, 0))
		if c - a != 0:
			rows.append([c - a, k, a, b, c])
	rows.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	for r: Array in rows:
		_say("  %+5d  %-42s %d -> %d -> %d" % [r[0], r[1], r[2], r[3], r[4]])
	if rows.is_empty():
		_say("  роста нет")
	_say("СИРОТЫ (узлы вне дерева, их никто не освободит): %d"
			% Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	if _out != null:
		_out.close()
