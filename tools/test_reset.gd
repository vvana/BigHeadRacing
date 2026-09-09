extends Node
## Одноразовый стенд полного цикла заезда по сети: клиент подключается,
## ЕДЕТ ГАЗ В ПОЛ все 4 круга, финиширует (баннер, конфетти, начисление
## опыта), сервер через POST_RACE_HOLD с перезапускает трассу и шлёт
## _rx_reset — с 09.09 (вечер) участник ОТСОЕДИНЯЕТСЯ и остаётся с
## таблицей мест до Enter (следующая гонка сама не начинается, все идут
## в гараж); перезагрузка сцены после заезда — теперь FAIL.
##
## Газ жмём НЕ для красоты: 26.08 клиент закрывался насмерть именно на этой
## перезагрузке, а прошлая версия стенда (стояла на месте и ждала
## FINISH_TIMEOUT) её переживала спокойно. Разница между стендом и живым
## игроком была ровно в том, что игрок ЕХАЛ: следы шин, дым, эффекты
## оружия, конфетти финиша — всё это к моменту reset висит в сцене.
##
## После reload_current_scene() эта нода пересоздаётся вместе со сценой:
## факт «мы перезапустились и снова получили слот» и есть критерий PASS
## (флаг переживает перезагрузку в GameState-автолоаде нельзя — не трогаем
## его; используем Net: после _rx_reset слот сброшен в −1 и выдан заново).
##
## Запуск (сервер должен работать):
##   godot --headless --path . res://tools/TestReset.tscn
## Ожидание долгое: ~3-6 минут (боты едут 4 круга + таймаут 40 с + 8 с).
##
## Адрес чужого сервера — аргументом после `--` (как в test_net.gd):
##   godot --headless --path . res://tools/TestReset.tscn -- 139.100.234.166
## И ВАЖНО: перезагрузка сцены — это освобождение всей графики заезда, а
## клиент 26.08 падал на ней НАСМЕРТЬ (окно закрывалось). Ловится это
## только с ЖИВЫМ рендером: запускать стенд БЕЗ `--headless`.

const DEADLINE := 420.0   # с запасом: круг ~727 м, боты ~17 м/с

static var _run := 0      # static переживает reload_current_scene
static var _t0 := 0.0
# Видели ли мы ИДУЩИЙ заезд до перезагрузки. Без этого стенд врал: сцену
# перезагружает и _rx_track («сервер выбрал другую трассу»), а он приходит
# сразу после подключения — стенд рапортовал PASS через 2 секунды, ни разу
# не доехав до финиша и не проверив то, ради чего написан.
static var _raced_run := 0

var _t := 0.0


func _ready() -> void:
	_run += 1
	if _run == 1:
		_t0 = Time.get_ticks_msec() / 1000.0
		var addr := "127.0.0.1"
		for a: String in OS.get_cmdline_user_args():
			if not a.begins_with("--"):
				addr = a
				break
		print("  [reset-test] первый запуск сцены, подключаемся к %s" % addr)
		# remember=false — не затирать игроку адрес VDS в user://net.cfg.
		Net.join_server(addr, Net.PORT, false)
	else:
		print("  [reset-test] сцена перезагружена (запуск %d, заезд был: %s)"
				% [_run, str(_raced_run > 0)])


func _physics_process(delta: float) -> void:
	_t += delta
	# Газ в пол через Input: своя машина клиент-авторитетна, её физику
	# целиком считает клиент (Main._client_tick шлёт состояние серверу).
	Input.action_press("accelerate")
	var main := get_parent() as Node3D
	if main != null and main._net_started:
		_raced_run = _run
	var total := Time.get_ticks_msec() / 1000.0 - _t0
	if total > DEADLINE:
		print("RESET TEST: FAIL (за %.0f с перезапуск так и не случился)" % DEADLINE)
		get_tree().quit(1)
		return
	# С 09.09 (вечер) УЧАСТНИК заезда по _rx_reset НЕ перезагружается, а
	# отсоединяется (Main._detach_after_race): следующая гонка сама не
	# начинается, итог остаётся на экране до Enter, дальше — гараж.
	# PASS: заезд шёл, пришёл reset, сцена та же (_run == 1), _detached,
	# сеть отключена, таблица мест видна, все машины заморожены.
	# Перезагрузка сцены после заезда теперь — FAIL (старое поведение).
	if _run >= 2 and _raced_run > 0 and _raced_run < _run:
		print("RESET TEST: FAIL (после заезда сцена перезагрузилась — участник "
				+ "должен остаться с таблицей и отсоединиться)")
		get_tree().quit(1)
		return
	if main != null and _raced_run == _run and main._detached:
		var frozen := true
		for c in main._cars:
			if not c.freeze or c.controls_enabled:
				frozen = false
		var ok: bool = Net.mode == Net.Mode.OFFLINE and main._finished \
				and main._finish_root != null and main._finish_root.visible \
				and frozen
		print("  [reset-test] reset получен на %.0f с: detached, сеть %s, финиш %s, "
				% [total, "OFFLINE" if Net.mode == Net.Mode.OFFLINE else "не отключена",
				str(main._finished)]
				+ "таблица %s, заморожены %s; моё время %s, лучший круг %s"
				% [str(main._finish_root.visible if main._finish_root else false),
				str(frozen), main.fmt_ms(main._finish_ms[main._my_index()]),
				main.fmt_ms(main._best_lap_ms[main._my_index()])])
		# Время своей гонки может быть и 0: стенд едет «газ в пол» без руля и
		# до финиша обычно не доезжает (заезд закрывает таймаут).
		print("RESET TEST: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
