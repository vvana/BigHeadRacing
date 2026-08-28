extends Node3D
## Автотест «пустого заезда» (VDS 27.08, 13:52:30: «старт заезда,
## игроков: 0»). Последний игрок уходит В ОКНЕ показа ботов (BOTS_SHOW,
## 2.2 с): хвост await в _start_with_bots раньше проверял только «не зашёл
## ли новый» (_start_gen) — и стартовал заезд, в котором нет ни одного
## человека. Зашедший через полминуты игрок считался «опоздавшим» к этой
## ничьей гонке и высылался в комнату вместо своей новой.
## Сервер здесь настоящий (ENet без клиентов), а вход/выход игрока
## имитируется так, как их выдал бы Net: слот в slot_of_peer + сигнал.

var _main: Node3D
var _frame := 0
var _bots_seen_at := -1
var _left_at := -1


func _ready() -> void:
	# Не 9977: рядом может крутиться настоящий локальный сервер.
	Net.port = 29977
	Net.start_server()
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 30:
		print("игрок вошёл")
		Net.slot_of_peer[777] = 0
		Net.player_joined.emit(777, 0)
		_main._hello_done[0] = true   # hello «пришёл» — загрузку не ждём
		return
	# Ждём начала показа ботов (лобби истекло, _start_with_bots взвёл флаг).
	if _bots_seen_at < 0:
		if _main._starting:
			_bots_seen_at = _frame
			print("боты показаны (кадр %d)" % _frame)
		elif _frame > 60 * 20:
			print("EMPTYSTART TEST: FAIL — показ ботов так и не начался")
			get_tree().quit(1)
		return
	# Через полсекунды после начала показа игрок уходит — окно ещё открыто.
	if _left_at < 0:
		if _frame == _bots_seen_at + 30:
			print("игрок ушёл в окне показа ботов")
			Net.slot_of_peer.clear()
			Net.player_left.emit(777, 0)
			_left_at = _frame
		return
	# BOTS_SHOW давно позади: заезд НЕ должен был начаться.
	if _frame == _left_at + 240:
		var ok: bool = not _main._net_started
		print("EMPTYSTART TEST: %s" % ("PASS" if ok
				else "FAIL — заезд стартовал без игроков"))
		get_tree().quit(0 if ok else 1)
