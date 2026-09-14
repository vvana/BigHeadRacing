extends Node
## Стенд ДРУЗЕЙ ПО СЕТИ (09.09): настоящий ENet в одном процессе. Сервер
## друзей — автозагрузка Social в роли сервера (порт 29990), два «игрока» —
## сырые ENetConnection-клиенты этого стенда (JSON, как Social). Сценарий:
## оба здороваются, второй пробует занять имя первого (занято), берёт
## своё, первый ищет второго и приглашает, второй принимает, оба жмут
## «ГОТОВ» — сервер шлёт go в пустое лобби (визитка пишется стендом,
## Rooms.write_card на порт 39977), второй выходит — первому пустой
## ростер. Итог: «SOCIAL NET TEST: PASS|FAIL».
## Запуск: godot --headless --path . res://tools/TestSocialNet.tscn

const PORT := 29990
const CARD_PORT := 39977
const DEADLINE := 20.0

var _t := 0.0
var _card_t := 0.0
var _a: Dictionary
var _b: Dictionary
var _step := 0
var _fails := PackedStringArray()


func _ready() -> void:
	Engine.max_fps = 60
	if not Social.start_server(PORT):
		print("SOCIAL NET TEST: FAIL (порт %d занят)" % PORT)
		get_tree().quit(1)
		return
	Social.server.persist = false
	_a = _client("test_a_%d" % randi(), "СтендА")
	_b = _client("test_b_%d" % randi(), "СтендБ")


func _client(uid: String, name: String) -> Dictionary:
	var host := ENetConnection.new()
	host.create_host(1, 2)
	var peer := host.connect_to_host("127.0.0.1", PORT, 2)
	# last: последнее сообщение каждого типа; шаг сценария забирает его
	# _take, когда ДЕЙСТВИТЕЛЬНО переходит дальше (иначе ответ, пришедший
	# на кадр раньше соседнего, терялся бы).
	return {host = host, peer = peer, uid = uid, name = name, last = {},
			connected = false}


func _send(c: Dictionary, msg: Dictionary) -> void:
	(c.peer as ENetPacketPeer).send(0, JSON.stringify(msg).to_utf8_buffer(),
			ENetPacketPeer.FLAG_RELIABLE)


func _pump(c: Dictionary) -> void:
	for _i in 32:
		var ev: Array = (c.host as ENetConnection).service(0)
		if ev[0] == ENetConnection.EVENT_NONE:
			break
		if ev[0] == ENetConnection.EVENT_CONNECT:
			c.connected = true
			_send(c, {t = "hello", proto = Net.PROTOCOL, uid = c.uid, name = c.name, car = "vz01_red",
					status = "garage"})
		elif ev[0] == ENetConnection.EVENT_RECEIVE:
			var m: Variant = JSON.parse_string(
					(ev[1] as ENetPacketPeer).get_packet().get_string_from_utf8())
			if typeof(m) == TYPE_DICTIONARY:
				(c.last as Dictionary)[str(m.get("t", ""))] = m


func _peek(c: Dictionary, t: String) -> Dictionary:
	return (c.last as Dictionary).get(t, {})


func _take(c: Dictionary, t: String) -> Dictionary:
	var found: Dictionary = _peek(c, t)
	(c.last as Dictionary).erase(t)
	return found


func _fail(what: String) -> void:
	_fails.append(what)


func _physics_process(delta: float) -> void:
	_t += delta
	_pump(_a)
	_pump(_b)
	# Визитка «пустого лобби» — чтобы серверу было куда отправить команду.
	_card_t -= delta
	if _card_t <= 0.0:
		_card_t = 1.0
		Rooms.write_card(CARD_PORT, 0, true, 8)
	match _step:
		0:
			var wa := _peek(_a, "welcome")
			var wb := _peek(_b, "welcome")
			if not wa.is_empty() and not wb.is_empty():
				_take(_a, "welcome")
				_take(_b, "welcome")
				if not bool(wa.get("ok", false)) or not bool(wb.get("ok", false)):
					_fail("welcome: имена стендов должны быть свободны")
				_send(_b, {t = "claim", name = "стенда"})
				_step = 1
		1:
			var cr := _take(_b, "claim_result")
			if not cr.is_empty():
				if bool(cr.get("ok", true)) or str(cr.get("reason")) != "taken":
					_fail("claim чужого имени должен быть отказан")
				_send(_b, {t = "claim", name = "СтендБ2"})
				_step = 2
		2:
			var cr := _take(_b, "claim_result")
			if not cr.is_empty():
				if not bool(cr.get("ok", false)):
					_fail("claim своего нового имени должен пройти")
				_send(_a, {t = "search", q = "стендб"})
				_step = 3
		3:
			var sr := _take(_a, "search_result")
			if not sr.is_empty():
				var items: Array = sr.get("items", [])
				if items.size() != 1 or str(items[0].name) != "СтендБ2" \
						or not bool(items[0].online):
					_fail("поиск должен найти СтендБ2 онлайн: %s" % str(items))
				_send(_a, {t = "invite", name = "СтендБ2"})
				_step = 4
		4:
			var inv := _take(_b, "invite")
			if not inv.is_empty():
				if str(inv.get("from", "")) != "СтендА":
					_fail("приглашение должно быть от СтендА")
				_send(_b, {t = "accept"})
				_step = 5
		5:
			var pa := _peek(_a, "party")
			var pb := _peek(_b, "party")
			if (pa.get("members", []) as Array).size() == 2 \
					and (pb.get("members", []) as Array).size() == 2:
				_take(_a, "party")
				_take(_b, "party")
				_send(_a, {t = "ready", on = true, size = 4})
				_send(_b, {t = "ready", on = true, size = 4})
				_step = 6
		6:
			var ga := _peek(_a, "go")
			var gb := _peek(_b, "go")
			if not ga.is_empty() and not gb.is_empty():
				if int(ga.get("port", 0)) != CARD_PORT \
						or int(gb.get("port", 0)) != CARD_PORT:
					_fail("go должен вести на порт визитки %d: %s / %s"
							% [CARD_PORT, str(ga), str(gb)])
				if int(ga.get("count", 0)) != 2 or int(ga.get("size", 0)) != 4 \
						or str(ga.get("party", "")) == "":
					_fail("go: count 2, size 4, id команды")
				_take(_a, "party")
				# Выход одного — второму пустой ростер.
				_send(_b, {t = "leave"})
				_step = 7
		7:
			var pa := _peek(_a, "party")
			if not pa.is_empty() and (pa.get("members", []) as Array).is_empty():
				_step = 8
	if _step == 8 or _t > DEADLINE:
		var ok := _step == 8 and _fails.is_empty()
		if _step != 8:
			_fails.append("не дошли до конца сценария: шаг %d" % _step)
		for f in _fails:
			print("  FAIL: ", f)
		Rooms.remove_card(CARD_PORT)
		print("SOCIAL NET TEST: %s" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
