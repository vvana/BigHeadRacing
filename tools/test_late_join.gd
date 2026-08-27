extends Node
## Стенд «опоздавший к заезду». История правила:
## - 26.08: опоздавший позже Main.JOIN_LATE_MAX больше не подсаживался в
##   чужую гонку, а ждал в лобби следующей (_rx_lobby_wait_next);
## - 27.08 (Rooms.gd): ждать больше не надо — ворота перенаправляют его в
##   ПАРАЛЛЕЛЬНЫЙ заезд-комнату на соседнем порту (_rx_redirect). Прежнее
##   «жди следующего» осталось запасным путём на случай, когда комнаты
##   кончились (ROOMS_MAX) — здесь не проверяется: на дев-машине комната
##   поднимется всегда.
##
## Что должно быть видно через несколько секунд после подключения:
##   1) какой-то сервер выдал слот (игрока не выгнали);
##   2) это ДРУГОЙ заезд — порт не тот, в который мы стучались;
##   3) в чужую доигрываемую гонку нас не посадили и ждать её конца не
##      оставили (_wait_next_race не взведён).
##
## Запуск: сначала поднять сервер-ворота и НАЧАТЬ на нём заезд (годится
## соседний стенд TestRooms с ключом `--stay` — он подключается и сидит),
## выждать больше JOIN_LATE_MAX, и только потом:
##   godot --headless --path . res://tools/TestLateJoin.tscn
## Адрес чужого сервера — аргументом после `--`, как в test_net.gd.
##
## ГРАБЛИ те же, что у TestNet: RPC адресуются по пути узла, поэтому корень
## сцены обязан зваться Main и нести Main.gd, а проверяльщик висит дочерним.
## Перенаправление перезагружает сцену — этот узел переживает её вместе с
## ней, счётчик времени начинается заново (DEADLINE это учитывает).

const DEADLINE := 25.0    # ждём слот; запас на подъём комнаты (~2-4 с)

var _t := 0.0
var _main: Node3D
var _ok := {}


func _ready() -> void:
	Engine.max_fps = 120
	_main = get_parent() as Node3D
	# После перенаправления сцена перезагружена уже подключённой к комнате.
	if Net.is_online():
		return
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
	# Ждём, пока какой-нибудь заезд примет нас (слот в воротах нам не
	# положен — их гонка ушла дальше JOIN_LATE_MAX).
	if Net.my_slot >= 0:
		_finish()


func _finish() -> void:
	_ok["слот выдан"] = Net.my_slot >= 0
	_ok["нас перенаправили в другой заезд"] = Net.port != Net.PORT
	_ok["чужую гонку не ждём"] = not _main._wait_next_race
	var all_ok := true
	for k: String in _ok:
		if not _ok[k]:
			all_ok = false
		print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
	print("LATEJOIN TEST: %s" % ("PASS" if all_ok else "FAIL"))
	get_tree().quit(0 if all_ok else 1)
