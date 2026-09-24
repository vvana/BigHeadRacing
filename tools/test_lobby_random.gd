extends Node3D
## Лобби случайной длины (24.09): когда живых соперников нет, ожидание
## каждый раз разное, но заезд не начинается и боты не «подключаются», пока
## игрок не прогрелся (_rx_ready шлётся только после Main._prewarm_fx).
## Сервер настоящий (ENet без клиентов), вход игрока имитируется, как в
## TestBotTrickle. Проверяем:
##   1) _roll_lobby_wait даёт разброс во всём окне LOBBY_WAIT..LOBBY_WAIT_MAX
##      (веб — LOBBY_WAIT_WS..LOBBY_WAIT_WS_MAX);
##   2) игрок подключился и прислал hello, но не готов 6 с — старта нет,
##      ботов в лобби нет;
##   3) после готовности живого лобби не меньше READY_SHOW, план ботов
##      укладывается в оставшийся срок, все боты приходят ПО ОДНОМУ до
##      старта (на старте новых нет);
##   4) заезд начинается не позже LOBBY_WAIT(_WS)_MAX + показ ботов.
##
## Запуск: godot --headless --path . res://tools/TestLobbyRandom.tscn
##         (веб-ворота: то же с `-- --ws`)

const SIZE := 4
const NOT_READY_FOR := 6.0

var _main: Node3D
var _t := 0.0
var _slot := -1
var _ready_at := -1.0
var _wait_at_ready := 0.0
var _plan_max := 0.0
var _mask_before_start := 0
var _pass := 0
var _fail := 0


func _ok(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: ", what)


func _ready() -> void:
	Net.port = 29981
	GameState.race_size = SIZE
	Net.race_size = SIZE
	Net.start_server()
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t < 0.5:
		return
	if _slot < 0:
		_check_rolls()
		_slot = Net._free_slot()
		Net.slot_of_peer[801] = _slot
		Net.player_joined.emit(801, _slot)
		_main._hello_done[_slot] = true
		print("игрок вошёл в слот %d, ожидание %.1f с (%s)" % [_slot,
				_main._lobby_wait, "веб" if Net.uses_ws() else "UDP"])
		return
	if _ready_at < 0.0:
		if _main._net_started or _main._starting:
			_ok(false, "заезд начался до готовности игрока")
			_finish()
			return
		if _main._bot_mask != 0:
			_ok(false, "бот пришёл до готовности игрока")
			_finish()
			return
		if _t >= 0.5 + NOT_READY_FOR:
			_ok(true, "до готовности ни старта, ни ботов")
			_main._mark_ready(_slot)
			_ready_at = _t
			_wait_at_ready = _main._lobby_wait
			for s: int in _main._bot_plan:
				_plan_max = maxf(_plan_max, float(_main._bot_plan[s]))
			print("готов на %.1f с: осталось ждать %.1f с, план ботов %s"
					% [_t, _wait_at_ready, str(_main._bot_plan)])
			_ok(_wait_at_ready >= _main.READY_SHOW - 0.01,
					"после готовности лобби меньше READY_SHOW (%.1f)" % _wait_at_ready)
			_ok(_main._bot_plan.size() == SIZE - 1,
					"в плане %d ботов, ждали %d" % [_main._bot_plan.size(), SIZE - 1])
			_ok(_plan_max <= _wait_at_ready,
					"последний бот (%.1f) позже конца ожидания (%.1f)"
					% [_plan_max, _wait_at_ready])
		return
	if not _main._net_started and not _main._starting:
		_mask_before_start = _main._bot_mask
	if _main._net_started:
		var live := _t - _ready_at
		print("заезд начался через %.1f с после готовности" % live)
		_ok(_popcount(_mask_before_start) == SIZE - 1,
				"к старту по одному пришли %d ботов из %d"
				% [_popcount(_mask_before_start), SIZE - 1])
		_ok(live >= _main.READY_SHOW, "живого лобби %.1f с < READY_SHOW" % live)
		_finish()
		return
	var cap: float = (_main.LOBBY_WAIT_WS_MAX if Net.uses_ws()
			else _main.LOBBY_WAIT_MAX) + _main.BOTS_SHOW + 2.0
	if _t - _ready_at > cap:
		_ok(false, "заезд не начался за %.0f с после готовности" % cap)
		_finish()


func _check_rolls() -> void:
	var lo := 1e9
	var hi := -1e9
	for i in 300:
		var w: float = _main._roll_lobby_wait()
		lo = minf(lo, w)
		hi = maxf(hi, w)
	var a: float = _main.LOBBY_WAIT_WS if Net.uses_ws() else _main.LOBBY_WAIT
	var b: float = _main.LOBBY_WAIT_WS_MAX if Net.uses_ws() else _main.LOBBY_WAIT_MAX
	print("срок лобби: %.1f..%.1f с (окно %.0f..%.0f)" % [lo, hi, a, b])
	_ok(lo >= a and hi <= b, "срок вне окна")
	_ok(hi - lo > (b - a) * 0.8, "разброс срока мал (%.1f..%.1f)" % [lo, hi])


func _popcount(m: int) -> int:
	var n := 0
	while m != 0:
		n += m & 1
		m >>= 1
	return n


func _finish() -> void:
	print("LOBBY RANDOM TEST: %s (%d ok, %d fail)"
			% ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)
