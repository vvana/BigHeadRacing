extends Node3D
## Автотест «боты подключаются по одному» (07.09). Сервер настоящий (ENet
## без клиентов), вход игроков имитируется, как их выдал бы Net: слот из
## Net._free_slot() + запись в slot_of_peer + сигнал player_joined.
## Проверяем:
##   1) после входа первого игрока боты занимают слоты НЕ разом: биты
##      _bot_mask загораются в разные моменты, между ними >= BOT_GAP;
##   2) второй игрок, зашедший, когда часть слотов уже за ботами, получает
##      слот БЕЗ бота (никто из «подключившихся» не пропадает);
##   3) третий игрок, когда свободных нет, получает слот бота, и бот
##      уступает (бит гаснет);
##   4) заезд стартует с тремя людьми и одним ботом, _lobby_players() == 4.
##
## Запуск: godot --headless --path . res://tools/TestBotTrickle.tscn

const SIZE := 4

var _main: Node3D
var _frame := 0
var _seen_mask := 0
var _arrivals: Array[int] = []      # кадры, когда загорались новые биты
var _b_joined := false
var _c_joined := false
var _c_slot := -1
var _fails: Array[String] = []


func _ready() -> void:
	Net.port = 29978
	GameState.race_size = SIZE
	Net.race_size = SIZE
	Net.start_server()
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _join(id: int) -> int:
	var slot: int = Net._free_slot()
	Net.slot_of_peer[id] = slot
	Net.player_joined.emit(id, slot)
	_main._hello_done[slot] = true
	_main._ready_done[slot] = true
	return slot


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 30:
		var s := _join(701)
		print("игрок A вошёл в слот %d" % s)
		return
	if _frame < 30:
		return
	var mask: int = _main._bot_mask
	if mask & ~_seen_mask:
		_arrivals.append(_frame)
		print("бот занял слот (маска %d, кадр %d, игроков в лобби %d)"
				% [mask, _frame, _main._lobby_players()])
	_seen_mask |= mask
	var bots := _popcount(mask)
	# Два бота на местах — заходит B: ему положен слот без бота.
	if not _b_joined and bots >= 2 and not _main._net_started:
		_b_joined = true
		var free_slot: int = Net._free_slot()
		var expect_free := (mask & (1 << free_slot)) == 0
		var s := _join(702)
		print("игрок B вошёл в слот %d (бот там %s)"
				% [s, "БЫЛ" if not expect_free else "не сидел"])
		if not expect_free:
			_fails.append("B получил слот бота при свободном слоте")
		if _main._bot_mask != mask:
			_fails.append("вход B погасил бота (маска %d → %d)"
					% [mask, _main._bot_mask])
		return
	# Все оставшиеся слоты за ботами — заходит C: получает слот бота,
	# бот уступает.
	if _b_joined and not _c_joined and not _main._net_started \
			and _popcount(mask) + Net.slot_of_peer.size() >= SIZE:
		_c_joined = true
		_c_slot = _join(703)
		print("игрок C вошёл в слот %d (маска была %d, стала %d)"
				% [_c_slot, mask, _main._bot_mask])
		if (mask & (1 << _c_slot)) == 0:
			_fails.append("C получил слот %d, где бота не было" % _c_slot)
		if _main._bot_mask & (1 << _c_slot):
			_fails.append("бот не уступил слот C")
		return
	if _main._net_started:
		_report()
	elif _frame > 60 * 30:
		_fails.append("заезд не начался за 30 с")
		_report()


func _popcount(m: int) -> int:
	var n := 0
	while m != 0:
		n += m & 1
		m >>= 1
	return n


func _report() -> void:
	if _arrivals.size() < 2:
		_fails.append("боты пришли разом (моментов прихода %d)" % _arrivals.size())
	for i in range(1, _arrivals.size()):
		var gap := _arrivals[i] - _arrivals[i - 1]
		if gap < int(_main.BOT_GAP * 60.0 * 0.9):
			_fails.append("боты %d и %d пришли слишком близко (%d кадров)"
					% [i - 1, i, gap])
	if not _c_joined:
		_fails.append("C так и не зашёл")
	if _main._race_humans != 3:
		_fails.append("на старте людей %d, ждали 3" % _main._race_humans)
	if _main._lobby_players() != SIZE:
		_fails.append("игроков в лобби %d, ждали %d"
				% [_main._lobby_players(), SIZE])
	if _popcount(_main._bot_mask) != 1:
		_fails.append("ботов на старте %d, ждали 1" % _popcount(_main._bot_mask))
	var ok := _fails.is_empty()
	print("BOTTRICKLE TEST: %s%s" % ["PASS" if ok else "FAIL",
			"" if ok else " — " + "; ".join(_fails)])
	get_tree().quit(0 if ok else 1)
