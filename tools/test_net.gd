extends Node
## Сквозной тест сетевой игры. Подключается к УЖЕ ЗАПУЩЕННОМУ серверу
## (`godot --headless --path . res://scenes/Main.tscn -- --server`) на
## 127.0.0.1, просит начать заезд, даёт газ и проверяет, что:
##   1) сервер выдал слот и ростер машин;
##   2) СВОЯ машина поехала (сервер принял наш ввод и вернул позицию);
##   3) марионетки (боты) тоже поехали — снимки состояния приходят;
##   4) над второй машиной игрока висит маркер (её должно быть видно);
##   5) заезд стартовал САМ, без второго игрока: сервер ждёт его
##      LOBBY_WAIT секунд и дальше едет с ботом в пустом слоте.
##
## ГРАБЛИ, из-за которых стенд устроен именно так: адресация RPC в Godot
## идёт ПО ПУТИ УЗЛА. На сервере гонка живёт в /root/Main, значит и у
## клиента она обязана быть /root/Main — поэтому корень этой сцены зовётся
## Main и несёт тот же Main.gd, а проверяльщик висит ДОЧЕРНИМ узлом.
## Дочерний _ready вызывается раньше родительского — там и подключаемся,
## чтобы Main._ready увидел уже выставленный режим клиента.
##
## Запуск (сервер должен работать в фоне):
##   godot --headless --path . res://tools/TestNet.tscn

const RUN_TIME := 16.0
const MOVE_MIN := 15.0     # сколько метров должна проехать машина

var _t := 0.0
var _main: Node3D
var _start_pos := []
var _asked_start := false
var _ok := {}


func _ready() -> void:
	_main = get_parent() as Node3D
	Net.join_server("127.0.0.1", Net.PORT)


func _physics_process(delta: float) -> void:
	_t += delta
	if Net.my_slot < 0:
		if _t > 8.0:
			_fail("сервер не выдал слот за 8 с (он запущен?)")
		return
	if _start_pos.is_empty():
		_ok["слот выдан"] = true
		_ok["ростер получен"] = _main._roster.size() == _main._cars.size()
		for c: Car in _main._cars:
			_start_pos.append(c.global_position)
	# Стартовать НЕ просим: проверяем как раз то, что сервер сам подождёт
	# второго игрока LOBBY_WAIT секунд и начнёт с ботом.
	if not _asked_start and _main._car != null and _main._car.controls_enabled:
		_asked_start = true
		_ok["старт без второго игрока"] = _t < 12.0
		print("  заезд начался на %.1f с" % _t)
	# Газ в пол: своя машина считается локально, но ввод уходит и серверу,
	# и вернуться позиция должна ИМЕННО от него.
	if _main._car != null and _main._car.controls_enabled:
		_main._rx_input.rpc_id(1, 1.0, 0.0, false)
	if _t < RUN_TIME:
		return

	var me: Car = _main._cars[Net.my_slot]
	var moved_me := me.global_position.distance_to(_start_pos[Net.my_slot])
	var moved_bot := 0.0
	for i in _main._cars.size():
		if i == Net.my_slot:
			continue
		moved_bot = maxf(moved_bot,
				_main._cars[i].global_position.distance_to(_start_pos[i]))
	_ok["своя машина поехала"] = moved_me > MOVE_MIN
	_ok["снимки ботов идут"] = moved_bot > MOVE_MIN
	_ok["маркер у второго игрока"] = _main._rival_marker != null
	_ok["своя машина не марионетка"] = me.net_role == Car.NetRole.OWNED
	print("  проехали: своя %.1f м, лучший из остальных %.1f м"
			% [moved_me, moved_bot])
	_report()


func _fail(reason: String) -> void:
	print("NET TEST: FAIL (%s)" % reason)
	get_tree().quit(1)


func _report() -> void:
	var all_ok := true
	for k: String in _ok:
		if not _ok[k]:
			all_ok = false
		print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
	print("NET TEST: %s" % ("PASS" if all_ok else "FAIL"))
	get_tree().quit(0 if all_ok else 1)
