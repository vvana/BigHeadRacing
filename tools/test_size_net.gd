extends Node
## Сетевая половина выбора числа участников (31.08): ПЕРВЫЙ игрок пустого
## лобби задаёт размер заезда. Клиент хочет 6 машин (GameState.race_size),
## подключается к свежему локальному серверу (тот построен под 4) и ждёт:
##   1) сервер принял желание и перестроился — слот выдан, а сцена
##      КЛИЕНТА построена на 6 машин (сервер продиктовал размер в
##      _rx_track, наша сцена совпала с ним без перестройки: желание
##      выставлено в Net.race_size ещё до подключения — как это делает
##      кнопка «ПО СЕТИ»);
##   2) стрелок соперников — 5 (по одной на каждый чужой слот);
##   3) счётчики мест и слотов — той же длины.
##
## ГРАБЛИ те же, что у TestNet: корень сцены обязан зваться Main и нести
## Main.gd (RPC адресуются по пути узла), проверяльщик — дочерний узел.
## Сервер должен быть СВЕЖИМ (размер 4 по умолчанию): прогон друг за
## другом без перезапуска сервера оставит ему размер 6 — это не ошибка,
## первый игрок нового лобби переопределит его снова.
##
## Запуск (сервер поднять отдельно):
##   godot --headless --path . res://scenes/Main.tscn -- --server
##   godot --headless --path . res://tools/TestSizeNet.tscn

const WANT := 6
const DEADLINE := 30.0

var _t := 0.0
var _main: Node3D


func _ready() -> void:
	Engine.max_fps = 120
	_main = get_parent() as Node3D
	# После перестройки сцены (сервер продиктовал размер/трассу) мы уже
	# подключены — второй раз не идём.
	if Net.is_online():
		return
	GameState.race_size = WANT
	Net.race_size = WANT   # то же делает кнопка «ПО СЕТИ» (_join_pressed)
	var addr := "127.0.0.1"
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			addr = a
			break
	print("  сервер: %s:%d, хотим машин: %d" % [addr, Net.PORT, WANT])
	Net.join_server(addr, Net.PORT, false)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t > DEADLINE:
		_finish()
		return
	if Net.my_slot >= 0 and _t > 6.0:
		_finish()


func _finish() -> void:
	var n: int = _main._cars.size()
	var slot_ok := Net.my_slot >= 0
	var size_ok := n == WANT and Net.race_size == WANT
	var markers_ok: bool = _main._rival_markers.size() == WANT - 1
	var counters_ok: bool = _main._slot_taken.size() == n \
			and _main._net_place.size() == n
	var ok := slot_ok and size_ok and markers_ok and counters_ok
	print("SIZE NET TEST: %s (слот=%d, машин %d из %d, стрелок %d, "
			% ["PASS" if ok else "FAIL", Net.my_slot, n, WANT,
			_main._rival_markers.size()]
			+ "счётчики=%s)" % str(counters_ok))
	get_tree().quit(0 if ok else 1)
