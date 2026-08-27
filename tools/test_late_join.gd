extends Node
## Стенд «опоздавший к заезду». Проверяет правило, введённое 26.08: игрок,
## подключившийся к УЖЕ ИДУЩЕЙ гонке позже Main.JOIN_LATE_MAX, в неё больше
## не подсаживается, а ждёт в лобби следующей. Раньше он попадал в чужой
## заезд, доигрываемый вторую минуту, — «запустил игру заново, а началась не
## новая гонка, а продолжилась старая».
##
## Что должно быть видно через несколько секунд после подключения:
##   1) сервер выдал слот (соединение живое, игрока не выгнали);
##   2) клиент знает, что ждёт следующего заезда (_wait_next_race);
##   3) управление выключено — в чужую гонку он не едет;
##   4) лобби на экране (игрок видит, чего ждёт, а не пустую трассу).
##
## Запуск: сначала поднять сервер и НАЧАТЬ на нём заезд (годится соседний
## стенд TestReset — он подключается и едет), выждать больше JOIN_LATE_MAX,
## и только потом:
##   godot --headless --path . res://tools/TestLateJoin.tscn
## Адрес чужого сервера — аргументом после `--`, как в test_net.gd.
##
## ГРАБЛИ те же, что у TestNet: RPC адресуются по пути узла, поэтому корень
## сцены обязан зваться Main и нести Main.gd, а проверяльщик висит дочерним.

const DEADLINE := 20.0    # столько ждём слот и вердикт сервера

var _t := 0.0
var _main: Node3D
var _ok := {}


func _ready() -> void:
	Engine.max_fps = 120
	_main = get_parent() as Node3D
	var addr := "127.0.0.1"
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			addr = a
			break
	print("  сервер: %s:%d" % [addr, Net.PORT])
	# remember=false: не затирать игроку сохранённый адрес VDS.
	Net.join_server(addr, Net.PORT, false)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t > DEADLINE:
		_finish()
		return
	# Ждём вердикта сервера: слот выдан И пришла команда «жди следующего».
	if Net.my_slot >= 0 and _main._wait_next_race:
		_finish()


func _finish() -> void:
	_ok["слот выдан"] = Net.my_slot >= 0
	_ok["ждём следующего заезда"] = _main._wait_next_race
	_ok["в чужую гонку не едем"] = _main._car == null \
			or not _main._car.controls_enabled
	_ok["лобби на экране"] = _main._lobby != null and _main._lobby.visible
	var all_ok := true
	for k: String in _ok:
		if not _ok[k]:
			all_ok = false
		print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
	print("LATEJOIN TEST: %s" % ("PASS" if all_ok else "FAIL"))
	get_tree().quit(0 if all_ok else 1)
