extends Node3D
## Команда друзей СЪЕЗЖАЕТСЯ ЗАНОВО после того, как разбежалась из лобби,
## не стартовав (жалоба 14.09: «игрок с компа жмёт ГОТОВ, у меня выходит
## лобби, он в лобби не попадает, игрок с мобилы попадает»). По журналу VDS:
## та же команда p1_… заходила в лобби три раза за 65 с (два раза все
## вышли до старта), сервер помнил секунду её ПЕРВОГО прибытия с первого
## захода, на третьем PARTY_GRACE «давно вышел», и заезд уехал через
## LOBBY_WAIT без третьего — его унесло в отдельную комнату.
## Проверяем на серверной стороне (игроки имитируются, как в
## TestReadyStart — слот в Net.slot_of_peer + сигнал):
##   1) двое из трёх в лобби — старт ждёт команду (secs = −2);
##   2) оба ушли — сервер забыл команду (размер и отметку прибытия);
##   3) те же двое вернулись «через минуту» — отметка свежая, старт снова
##      ждёт третьего, а не уезжает по вышедшему сроку;
##   4) страховка на стороне hello: устаревшая отметка команды, никого из
##      которой нет в лобби, обновляется при первом же hello;
##   5) третий приехал — заезд начинается.
##
## Запуск: godot --headless --path . res://tools/TestPartyRegather.tscn

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
	Net.port = 29981
	Net.start_server()
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## «Подключить» члена команды в слот, как это сделали бы Net и hello.
func _join(peer: int, slot: int, pid: String, size: int) -> void:
	Net.slot_of_peer[peer] = slot
	Net.player_joined.emit(peer, slot)
	_main._note_party(slot, pid, size)
	_main._hello_done[slot] = true
	_main._ready_done[slot] = true


func _leave(peer: int, slot: int) -> void:
	Net.slot_of_peer.erase(peer)
	Net.player_left.emit(peer, slot)


func _physics_process(_d: float) -> void:
	_frame += 1
	match _phase:
		0:
			if _frame < 30:
				return
			_join(701, 0, "p1", 3)
			_join(702, 1, "p1", 3)
			_ok(_main._party_waiting(), "двое из трёх — команду ждём")
			_main._want_start = true
			_main._maybe_start()
			_ok(not _main._net_started and not _main._starting,
					"без третьего заезд не начался")
			_ok(_main._loading_told, "лобби сказало «ждём команду» (secs = −2)")
			_phase = 1
			_mark = _frame
		1:
			if _frame < _mark + 30:
				return
			# Как в жизни: первый заход был давно — отметка старше PARTY_GRACE.
			_main._party_first["p1"] = _now() - _main.PARTY_GRACE - 5.0
			_ok(not _main._party_waiting(),
					"со старой отметкой срок вышел (так и было на VDS)")
			_leave(701, 0)
			# Ушёл один — _on_peer_left зовёт _maybe_start, и со старой
			# отметкой заезд уезжает с ботами: ровно картина VDS 14.09.
			_ok(_main._starting, "со старой отметкой заезд уехал без команды")
			_leave(702, 1)
			_ok(not _main._party_size.has("p1") \
					and not _main._party_first.has("p1"),
					"все ушли — команда забыта")
			_ok(_main._lobby_wait < 0.0 and not _main._want_start,
					"лобби опустело — ожидание сброшено")
			_phase = 2
			_mark = _frame
		2:
			if _frame < _mark + 30:
				return
			# Та же команда вернулась третьим заходом.
			_join(703, 0, "p1", 3)
			_join(704, 1, "p1", 3)
			_ok(_now() - float(_main._party_first.get("p1", 0.0)) < 2.0,
					"отметка прибытия свежая")
			_ok(_main._party_waiting(), "вернувшуюся команду снова ждём")
			_main._want_start = true
			_main._maybe_start()
			_ok(not _main._net_started and not _main._starting,
					"третий ещё не приехал — заезд не уехал без него")
			# Страховка на стороне hello: устаревшая отметка команды, никого
			# из которой в лобби нет, обновляется первым же hello.
			_main._party_size["p9"] = 2
			_main._party_first["p9"] = _now() - _main.PARTY_GRACE - 5.0
			_main._note_party(3, "p9", 2)
			_ok(_now() - float(_main._party_first.get("p9", 0.0)) < 2.0,
					"hello обновил устаревшую отметку чужого сбора")
			_main._party_of_slot.erase(3)
			_main._party_size.erase("p9")
			_main._party_first.erase("p9")
			_phase = 3
			_mark = _frame
		3:
			# Три секунды: заезд начаться НЕ должен (грейс много больше).
			if _frame < _mark + 180:
				return
			_ok(not _main._net_started and not _main._starting,
					"за три секунды без третьего заезд не начался")
			_join(705, 2, "p1", 3)
			_ok(not _main._party_waiting(), "команда в сборе — ждать нечего")
			_main._maybe_start()
			_phase = 4
			_mark = _frame
		4:
			if not (_main._net_started or _main._starting):
				if _frame < _mark + 180:
					return
				_ok(false, "команда в сборе, а заезд так и не начался")
			else:
				_ok(true, "команда в сборе — заезд начался")
			print("RESULT: %d/%d ok" % [_pass, _pass + _fail])
			print("PARTY REGATHER TEST: %s" % ("PASS" if _fail == 0 else "FAIL"))
			get_tree().quit(0 if _fail == 0 else 1)
