extends Node
## ЗАМЕР входа в сетевой заезд и рывков первого круга НА НАСТОЛЬНОЙ СБОРКЕ
## (21.09.2026): «до/после» прогрева шейдеров, черновика трассы и плашки
## загрузки (GameState.warm_gfx, ключ --no-warm выключает). Запуск С ОКНОМ:
##   сервер:  godot --headless --path . res://scenes/Main.tscn -- --server --track=sand
##   замер:   godot --path . res://tools/MeasureNetStart.tscn -- [--no-warm]
## Перед прогоном стереть .godot/shader_cache — иначе меряется уже тёплый кэш.
## Стенд живёт в root (переживает смену сцен), жмёт «СТАРТ» в гараже, свою
## машину ведёт ИИ (Car.debug_autodrive) и 45 с после «GO!» пишет времена кадров.
## Итог — строка «MEASURE: …». Адрес в user://net.cfg возвращает на место.

const RACE_SECONDS := 45.0

class Watcher:
	extends Node

	var saved_host := ""
	var saved_port := 0
	var t := 0.0
	var last_usec := 0
	var click_ms := 0
	var main_ms := 0
	var go_ms := 0
	var load_max := 0.0          # самый длинный кадр от клика до готовности, мс
	var load_stall := 0.0        # сумма кадров > 100 мс за то же время
	var race: PackedFloat32Array = []
	var done := false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		saved_host = Net.host
		saved_port = Net.home_port
		Car.debug_autodrive = true
		GameState.player_name = "Замер"   # до гаража: иначе окно имени закроет СТАРТ
		Net.leave()
		Net.host = "127.0.0.1"
		Net.home_port = Net.PORT
		Net.port = Net.PORT
		get_tree().change_scene_to_file("res://scenes/CarSelect.tscn")

	func _process(delta: float) -> void:
		var now := Time.get_ticks_usec()
		var ms := (now - last_usec) / 1000.0 if last_usec > 0 else 0.0
		last_usec = now
		t += delta
		var cur := get_tree().current_scene
		if cur == null or done:
			return
		if click_ms == 0:
			if not cur.has_method("_start_race") or t < 1.5:
				return
			GameState.player_name = "Замер"
			Net.host = "127.0.0.1"
			click_ms = Time.get_ticks_msec()
			cur.call("_start_race")
			return
		if not ("_cars" in cur):
			load_max = maxf(load_max, ms)
			if ms > 100.0:
				load_stall += ms
			return
		if main_ms == 0:
			main_ms = Time.get_ticks_msec()
		if go_ms == 0:
			load_max = maxf(load_max, ms)
			if ms > 100.0:
				load_stall += ms
			var cars: Array = cur.get("_cars")
			var my: int = clampi(Net.my_slot, 0, maxi(cars.size() - 1, 0))
			if cur.get("_net_started") and not cars.is_empty() \
					and (cars[my] as Car).controls_enabled:
				go_ms = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - click_ms > 90000:
				_finish(cur, "заезд не начался за 90 с")
			return
		race.append(ms)
		if Time.get_ticks_msec() - go_ms >= int(RACE_SECONDS * 1000.0):
			_finish(cur, "")

	func _finish(cur: Node, problem: String) -> void:
		done = true
		var over25 := 0
		var over40 := 0
		var over80 := 0
		var worst := 0.0
		var total := 0.0
		for ms in race:
			total += ms
			worst = maxf(worst, ms)
			if ms > 25.0:
				over25 += 1
			if ms > 40.0:
				over40 += 1
			if ms > 80.0:
				over80 += 1
		var ready_ms: int = int(cur.get("ready_at_ms")) if "ready_at_ms" in cur else 0
		print("MEASURE: режим=%s%s | СТАРТ→сцена заезда %d мс, СТАРТ→готовность %d мс, СТАРТ→GO %d мс | загрузка: худший кадр %d мс, стояли %d мс | заезд %d с: кадров %d (%.0f к/с), >25 мс %d, >40 мс %d, >80 мс %d, худший %d мс"
				% ["ПРОГРЕВ" if GameState.warm_gfx() else "без прогрева",
				(" | ПРОБЛЕМА: " + problem) if problem != "" else "",
				main_ms - click_ms, ready_ms - click_ms, go_ms - click_ms,
				int(load_max), int(load_stall), int(RACE_SECONDS), race.size(),
				race.size() / maxf(total / 1000.0, 0.001),
				over25, over40, over80, int(worst)])
		Net.leave()
		Net.host = saved_host
		Net.home_port = saved_port
		Net.save_config()
		get_tree().quit()


func _ready() -> void:
	var w := Watcher.new()
	w.name = "MeasureWatcher"
	get_tree().root.add_child.call_deferred(w)
