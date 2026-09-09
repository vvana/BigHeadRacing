extends Node
## Сетевой стенд: РОВНЫЙ СТАРТ (жалоба 09.09 «когда я стартую, я всегда
## стартую первым, другие отстают — все же сразу жмут на газ»).
## Подключается к запущенному серверу, ждёт GO, даёт газ и меряет, когда
## НА ЭКРАНЕ КЛИЕНТА тронулась своя машина и когда — каждая марионетка
## (бот стартует на сервере в момент GO). Разница и есть то, что видит
## игрок. Запуск (сервер фоном):
##   godot --headless --path . res://scenes/Main.tscn -- --server
##   godot --headless --path . res://tools/TestStartNet.tscn
## Порог: соперники обязаны тронуться не позже MAX_LAG с после своей.

const MOVE := 0.3            # м — «тронулась»
const MAX_LAG := 0.12        # с — допустимое отставание картинки соперника
const START_DEADLINE := 40.0
const MEASURE := 4.0

var _t := 0.0
var _main: Node3D
var _go_at := -1.0
var _start_pos := []
var _moved_at := []
var _ok := {}


func _ready() -> void:
	Engine.max_fps = 120
	_main = get_parent() as Node3D
	var addr := "127.0.0.1"
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			addr = a
			break
	Net.join_server(addr, Net.PORT, false)


func _physics_process(delta: float) -> void:
	_t += delta
	if Net.my_slot < 0:
		if _t > 10.0:
			_fail("сервер не выдал слот за 10 с (он запущен?)")
		return
	if _go_at < 0.0:
		if _main._car != null and _main._car.controls_enabled:
			_go_at = _t
			print("  GO на %.2f с, слот %d, буфер %.3f, упреждение %.3f"
					% [_t, Net.my_slot, Car.net_buf_delay, Car.net_view_lead])
			for c: Car in _main._cars:
				_start_pos.append(c.visual_origin())
				_moved_at.append(-1.0)
		elif _t > START_DEADLINE:
			_fail("заезд не начался за %.0f с" % START_DEADLINE)
		return
	Input.action_press("accelerate")
	for i in _main._cars.size():
		if _moved_at[i] < 0.0 and (_main._cars[i] as Car).visual_origin() \
				.distance_to(_start_pos[i]) > MOVE:
			_moved_at[i] = _t - _go_at
	if _t < _go_at + MEASURE:
		return
	var mine: float = _moved_at[Net.my_slot]
	_ok["своя машина тронулась"] = mine >= 0.0
	print("  своя тронулась через %.2f с после GO" % mine)
	var worst := 0.0
	for i in _main._cars.size():
		if i == Net.my_slot:
			continue
		var d: float = _moved_at[i]
		print("  слот %d тронулся через %.2f с (разница %+.2f)"
				% [i, d, d - mine] if d >= 0.0 else "  слот %d не тронулся" % i)
		_ok["слот %d тронулся" % i] = d >= 0.0
		if d >= 0.0:
			worst = maxf(worst, d - mine)
	print("  худшее отставание соперника: %.2f с (порог %.2f)" % [worst, MAX_LAG])
	_ok["соперники стартуют вместе со мной"] = worst <= MAX_LAG
	_report()


func _fail(reason: String) -> void:
	print("STARTNET TEST: FAIL (%s)" % reason)
	get_tree().quit(1)


func _report() -> void:
	var all_ok := true
	for k: String in _ok:
		if not _ok[k]:
			all_ok = false
		print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
	print("STARTNET TEST: %s" % ("PASS" if all_ok else "FAIL"))
	get_tree().quit(0 if all_ok else 1)
