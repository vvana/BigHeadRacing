extends Node3D
## Отсчёт не начинается, пока МИР НЕ НА ЭКРАНЕ У ВСЕХ (жалоба 11.09:
## «запускали вчетвером — трое стояли на трассе, один ещё был в лобби,
## а игра уже началась»). Раньше слот переставал держать старт по одному
## hello, а он уходит из только что ПОСТРОЕННОЙ сцены: до первой картинки
## на телефоне проходят секунды, да и сцена могла отправиться на
## перестройку под присланный вид трассы. Теперь клиент подтверждает
## готовность вторым сообщением (_rx_ready → _ready_done).
## Проверяем на серверной стороне (игроки имитируются, как в
## TestEmptyStart — слот в Net.slot_of_peer + сигнал):
##   1) двое в лобби, hello от обоих, готовность только от одного —
##      заезд НЕ начинается и лобби сообщает «ждём загрузку» (secs = −1);
##   2) пришла готовность второго — заезд начинается;
##   3) молчуна всё-таки отпускает грейс (_all_loaded по HELLO_GRACE) —
##      иначе один зависший клиент держал бы остальных вечно.
##
## Запуск: godot --headless --path . res://tools/TestReadyStart.tscn

var _main: Node3D
var _frame := 0
var _pass := 0
var _fail := 0
var _phase := 0
var _mark := 0


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: ", what)


func _ready() -> void:
	# Не 9977: рядом может крутиться настоящий локальный сервер.
	Net.port = 29979
	Net.start_server()
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


## «Подключить» игрока в слот, как это сделал бы Net.
func _join(peer: int, slot: int) -> void:
	Net.slot_of_peer[peer] = slot
	Net.player_joined.emit(peer, slot)


func _physics_process(_d: float) -> void:
	_frame += 1
	match _phase:
		0:
			if _frame < 30:
				return
			_join(701, 0)
			_join(702, 1)
			# hello от обоих: сцены построены.
			_main._hello_done[0] = true
			_main._hello_done[1] = true
			# Готовность — только от первого.
			_main._ready_done[0] = true
			# Старт запрошен (в жизни это делает таймер лобби).
			_main._want_start = true
			_main._maybe_start()
			_ok(not _main._all_loaded(),
					"один без подтверждения — «загрузились все» ложно")
			_phase = 1
			_mark = _frame
		1:
			# Три секунды: заезд начаться НЕ должен (грейс много больше).
			if _frame < _mark + 180:
				return
			_ok(not _main._net_started and not _main._starting,
					"без готовности второго заезд не начался")
			_ok(_main._loading_told,
					"лобби сказало, что ждёт загрузку (secs = −1)")
			# Подтверждение второго — и заезд идёт.
			_main._mark_ready(1)
			_ok(_main._all_loaded(), "после подтверждения загрузились все")
			_phase = 2
			_mark = _frame
		2:
			if not (_main._net_started or _main._starting):
				if _frame < _mark + 180:
					return
				_ok(false, "после подтверждения заезд так и не начался")
			else:
				_ok(true, "после подтверждения заезд начался")
			# Третья проверка — на чистой сцене: молчуна отпускает грейс.
			_phase = 3
			_mark = _frame
		3:
			if _frame < _mark + 5:
				return
			_main._net_started = false
			_main._starting = false
			_main._hello_done = {0: true, 1: true}
			_main._ready_done = {0: true}
			# Подключились давно — грейс вышел.
			var long_ago: float = Time.get_ticks_msec() / 1000.0 \
					- 60.0
			_main._join_time = {0: long_ago, 1: long_ago}
			_ok(_main._all_loaded(),
					"молчуна отпускает грейс: старт не держится вечно")
			print("RESULT: %d/%d ok" % [_pass, _pass + _fail])
			print("READY START TEST: %s" % ("PASS" if _fail == 0 else "FAIL"))
			get_tree().quit(0 if _fail == 0 else 1)
