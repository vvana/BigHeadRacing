extends Node
## Стенд «СТАРТ без сети» (09.09.2026, жалоба с телефона «без сети игра не
## начнётся»). Гараж всегда стучится на сервер и лишь потом сдаётся в
## оффлайн — проверяем, что заезд ВСЁ РАВНО начинается:
##   фаза A — адрес молчит (192.0.2.1, TEST-NET-1: пакеты уходят в никуда,
##            как в самолётном режиме), сдаться должен по таймауту;
##   фаза B — адрес невалидный (create_client падает сразу), join_failed
##            приходит СИНХРОННО внутри join_server, и _start_race зовёт
##            _start_offline второй раз — не ломается ли смена сцены;
##   фаза C — сети на устройстве нет вовсе (Net.debug_offline, как
##            самолётный режим): заезд обязан начаться БЕЗ ожидания.
## Стенд живёт в get_tree().root (не в текущей сцене), поэтому переживает
## change_scene_to_file гаража. Headless:
## godot --headless --path . res://tools/TestOfflineStart.tscn

const DEAD_ADDR := "192.0.2.1"      # TEST-NET-1: маршрута нет, ответа нет
const BAD_ADDR := "300.300.300.300" # невалидный: ENet не создаст клиента
const LIMIT := 25.0                 # столько ждём заезда в каждой фазе


class Watcher:
	extends Node

	const DEAD_ADDR := "192.0.2.1"
	const BAD_ADDR := "300.300.300.300"
	const LIMIT := 25.0

	var phase := 0
	var t := 0.0
	# Своё в user://net.cfg стенд ОБЯЗАН вернуть: join_server(remember=true)
	# пишет туда адрес, и после прогона игра стучалась бы в 300.300.300.300.
	var saved_host := ""
	var saved_port := 0
	var waiting := false
	var pressed_at := 0.0
	var fails := 0
	var report: Array[String] = []

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		saved_host = Net.host
		saved_port = Net.home_port
		_begin(0)

	func _begin(p: int) -> void:
		phase = p
		waiting = false
		t = 0.0
		var addr := BAD_ADDR if p == 1 else DEAD_ADDR
		Net.debug_offline = p == 2
		Net.leave()
		Net.host = addr
		Net.home_port = Net.PORT
		Net.port = Net.PORT
		print("[offline] фаза %d: адрес %s" % [p + 1, addr])
		get_tree().change_scene_to_file("res://scenes/CarSelect.tscn")

	func _check(name: String, ok: bool) -> void:
		print("[offline] %s: %s" % [name, "ok" if ok else "FAIL"])
		if not ok:
			fails += 1

	func _process(delta: float) -> void:
		t += delta
		var cur := get_tree().current_scene
		if cur == null:
			return
		if not waiting:
			# Гараж на экране — жмём «СТАРТ» (как палец по кнопке).
			if cur.get_script() == null \
					or not cur.has_method("_start_race"):
				return
			if t < 0.5:
				return
			GameState.player_name = "Стенд"
			Net.host = BAD_ADDR if phase == 1 else DEAD_ADDR
			Net.debug_offline = phase == 2
			# Уведомление «СЕТИ НЕТ» в гараже (просьба 10.09). Плашка живёт
			# ровно столько, сколько нет сети: в фазе 3 (debug_offline) она
			# обязана висеть, в фазах 1-2 — показывать состояние устройства.
			var note: Variant = cur.get("_offline_note")
			_check("фаза %d: плашка «СЕТИ НЕТ» построена" % [phase + 1],
					note != null)
			if note != null:
				_check("фаза %d: плашка видна = %s"
						% [phase + 1, "да" if phase == 2 else "нет"],
						(note as Control).visible == (not Net.device_online()))
			cur.call("_start_race")
			waiting = true
			pressed_at = t
			print("[offline] фаза %d: СТАРТ нажат" % [phase + 1])
			return
		# Ждём, пока гараж сдастся и покажет заезд.
		if cur.has_method("_start_race"):
			if t - pressed_at > LIMIT:
				_check("фаза %d: заезд начался" % [phase + 1], false)
				report.append("фаза %d: гараж завис на «ПОДКЛЮЧЕНИЕ…» (%.0f с)"
						% [phase + 1, t - pressed_at])
				_next()
			return
		# Сцена сменилась — это заезд?
		var cars: Variant = cur.get("_cars")
		if cars == null:
			return
		_check("фаза %d: заезд начался за %.1f с"
				% [phase + 1, t - pressed_at], true)
		_check("фаза %d: сеть выключена" % [phase + 1], not Net.is_client())
		_check("фаза %d: машины на трассе (%d)"
				% [phase + 1, (cars as Array).size()],
				(cars as Array).size() >= 4)
		# Имена соперников: без сети боты подписаны «Бот N», а не
		# человеческими никами (просьба 10.09). Ник маскирует бота только в
		# СЕТЕВОМ заезде, где он занимает слот живого игрока.
		var names: Variant = cur.get("_names")
		var bots_ok := names != null and (names as PackedStringArray).size() > 1
		if bots_ok:
			var arr: PackedStringArray = names
			_check("фаза %d: слот 0 — имя игрока (%s)" % [phase + 1, arr[0]],
					arr[0] == "Стенд")
			for i in range(1, arr.size()):
				if not arr[i].begins_with("Бот"):
					bots_ok = false
					print("[offline] слот %d подписан «%s»" % [i, arr[i]])
		_check("фаза %d: соперники подписаны «Бот N»" % [phase + 1], bots_ok)
		# Уведомление в заезде: «СЕТИ НЕТ» (фаза 3) или «НЕТ СВЯЗИ С
		# СЕРВЕРОМ» (фазы 1-2 — сеть есть, молчит именно сервер).
		var want := "СЕТИ НЕТ" if phase == 2 else "НЕТ СВЯЗИ С СЕРВЕРОМ"
		_check("фаза %d: анонс «%s»" % [phase + 1, want],
				_has_label(cur, want))
		_check("фаза %d: причина оффлайна списана" % [phase + 1],
				Net.offline_reason == "")
		if phase == 2:
			# Сети нет — ждать сервер нечего, заезд обязан начаться сразу.
			_check("фаза 3: без сети старт мгновенный (%.1f с)"
					% [t - pressed_at], t - pressed_at < 1.0)
		report.append("фаза %d: оффлайн-заезд за %.1f с"
				% [phase + 1, t - pressed_at])
		_next()

	## Есть ли в дереве сцены Label ровно с таким текстом (анонс строится
	## узлами на лету — текст ищем обходом, а не по пути).
	func _has_label(root: Node, txt: String) -> bool:
		var l := root as Label
		if l != null and l.text == txt:
			return true
		for ch in root.get_children():
			if _has_label(ch, txt):
				return true
		return false


	func _next() -> void:
		if phase < 2:
			_begin(phase + 1)
			return
		Net.debug_offline = false
		set_process(false)   # иначе кадр после quit ловит get_tree() == null
		Net.host = saved_host
		Net.home_port = saved_port
		Net.port = saved_port
		Net.save_config()
		print("[offline] адрес в net.cfg возвращён: %s:%d"
				% [saved_host, saved_port])
		for line: String in report:
			print("[offline] ", line)
		print("OFFLINESTART TEST: %s (ошибок %d)"
				% ["PASS" if fails == 0 else "FAIL", fails])
		get_tree().quit(0 if fails == 0 else 1)


func _ready() -> void:
	var w := Watcher.new()
	w.name = "OfflineWatcher"
	get_tree().root.call_deferred("add_child", w)
