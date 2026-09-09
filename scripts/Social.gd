extends Node
## «Друзья» (autoload Social, 09.09): поиск игроков по имени, приглашения
## в команду, общий заезд для команды, единые имена. Это ОТДЕЛЬНОЕ от
## гонки соединение — низкоуровневый ENetConnection на порту SOCIAL_PORT
## ворот (Net.PORT + 13): игрок сидит в гараже, где никакого /root/Main нет,
## а RPC высокого уровня адресуются по пути узла. Соединение живёт в
## автозагрузке и переживает смену сцен: в гараже и в заезде игрок остаётся
## «на связи» для друзей.
##
## Сервер (ворота, `--server` без `--room`) держит SocialServer — всю
## логику (имена, команды) и умеет гоняться стендом без сети. Здесь только
## транспорт: пакет = JSON-словарь с полем "t".
##
## Клиент → сервер: hello{uid,name,car,status}, claim{name}, car{car},
## status{s}, search{q}, invite{name}, accept, decline, ready{on,size},
## leave. Сервер → клиент: welcome{ok,name,reason}, claim_result{ok,name,
## reason}, search_result{q,items}, invite{from,party,count},
## party{id,members,me,launching}, go{port,size,party,count},
## notice{text}, error{text}.

const SOCIAL_PORT := 9990
const CHANNELS := 2
const RETRY := 8.0            # клиент: секунд между попытками подключения
const MAX_EVENTS := 64        # событий ENet за кадр

signal connected_changed(on: bool)
signal welcome(ok: bool, reason: String)
signal name_result(ok: bool, name: String, reason: String)
signal search_result(items: Array)
signal friends_result(items: Array)   # статусы списка друзей (lookup)
signal invite_received(from: String, count: int)
signal party_changed()
signal go(port: int, size: int, party_id: String, count: int)
signal notice(text: String)

var server: SocialServer = null   # ворота: логика
var _host: ENetConnection = null
var _peer: ENetPacketPeer = null  # клиент: связь с сервером
var _peers := {}                  # сервер: ключ → ENetPacketPeer
var _is_server := false

# ── клиент ──
var connected := false
var name_ok := false              # сервер подтвердил наше имя
var name_reason := ""             # "taken" — занято другим, "empty" — нет
var party := {}                   # последний ростер {id, members, me, launching}
var pending_invite := {}          # {from, party, count} — ждёт ответа
var status := "garage"
var _want := false                # хотим быть на связи
var _retry := 0.0
var _addr := ""
var _port := SOCIAL_PORT


func _ready() -> void:
	# В web-сборке UDP нет — друзей там нет вовсе.
	if OS.has_feature("web"):
		set_process(false)
		return
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--social-port="):
			_port = maxi(1, int(a.trim_prefix("--social-port=")))
	if Net.wants_server() and not Net.is_room:
		start_server(_port)


# ── сервер ──

func start_server(port: int) -> bool:
	_host = ENetConnection.new()
	var err := _host.create_host_bound("*", port, 64, CHANNELS)
	if err != OK:
		push_error("[social] не удалось открыть UDP-порт %d: %s"
				% [port, error_string(err)])
		_host = null
		return false
	_is_server = true
	server = SocialServer.new()
	server.gate_port = Net.port
	print("[social] сервер друзей слушает UDP-порт %d, имён в реестре: %d"
			% [port, server.names.size()])
	return true


func stop_server() -> void:
	if _host != null and _is_server:
		_host.destroy()
	_host = null
	_is_server = false
	server = null
	_peers.clear()


# ── клиент ──

## Выйти на связь с сервером друзей (гараж зовёт при входе). Адрес — тот
## же, что у гонки (Net.host), порт — SOCIAL_PORT; стенды передают свой.
func go_online(addr := "", port := 0) -> void:
	if _is_server or OS.has_feature("web"):
		return
	_addr = addr if addr != "" else Net.host.strip_edges()
	_port = port if port > 0 else _port
	_want = true
	if _host == null and _addr != "":
		_connect_now()


func go_offline() -> void:
	_want = false
	_drop("")


func _connect_now() -> void:
	_retry = RETRY
	_host = ENetConnection.new()
	if _host.create_host(1, CHANNELS) != OK:
		_host = null
		return
	_peer = _host.connect_to_host(_addr, _port, CHANNELS)
	if _peer == null:
		_host.destroy()
		_host = null


func _drop(_why: String) -> void:
	if _host != null and not _is_server:
		if _peer != null:
			_peer.peer_disconnect_now()
		_host.destroy()
	_host = null
	_peer = null
	if connected:
		connected = false
		name_ok = false
		party = {}
		pending_invite = {}
		connected_changed.emit(false)
		party_changed.emit()


func _hello() -> void:
	send({t = "hello", uid = GameState.uid, name = GameState.player_name,
			car = GameState.selected_car_id, status = status})


func send(msg: Dictionary) -> void:
	if _peer == null or not connected:
		return
	_peer.send(0, JSON.stringify(msg).to_utf8_buffer(),
			ENetPacketPeer.FLAG_RELIABLE)


func claim_name(n: String) -> void:
	send({t = "claim", name = n})


func search(q: String) -> void:
	send({t = "search", q = q})


func invite(n: String) -> void:
	# Кого звал — в список друзей (профиль): в следующий раз пригласить
	# можно одной кнопкой, без поиска.
	GameState.remember_friend(n)
	send({t = "invite", name = n})


## Статусы друзей из профиля (в сети / в заезде / в команде) — ответ
## придёт сигналом friends_result в том же виде, что поиск.
func lookup(names: Array) -> void:
	if names.is_empty():
		friends_result.emit([])
		return
	send({t = "lookup", names = names})


func accept_invite() -> void:
	if pending_invite.has("from"):
		GameState.remember_friend(str(pending_invite.from))
	pending_invite = {}
	send({t = "accept"})


func decline_invite() -> void:
	pending_invite = {}
	send({t = "decline"})


func set_ready(on: bool) -> void:
	send({t = "ready", on = on, size = GameState.race_size})


func leave_party() -> void:
	send({t = "leave"})


## Машина сменилась в гараже — команде видно, на чём поедешь.
func report_car(id: String) -> void:
	send({t = "car", car = id})


## Где мы: "garage" или "race" (друзьям в поиске и в ростере).
func report_status(s: String) -> void:
	status = s
	send({t = "status", s = s})


func in_party() -> bool:
	return not party.is_empty() and str(party.get("id", "")) != "" \
			and (party.get("members", []) as Array).size() >= 2


func members() -> Array:
	return party.get("members", []) as Array if not party.is_empty() else []


## Имена ТОВАРИЩЕЙ по команде (без своего) — по ним заезд подсвечивает
## машины друзей (имена единые, потому совпадение имени = тот человек).
func mates() -> PackedStringArray:
	var out := PackedStringArray()
	var me := str(party.get("me", ""))
	for m: Dictionary in members():
		if str(m.get("uid", "")) != me and str(m.get("name", "")) != "":
			out.append(str(m.name))
	return out


func is_mate(pname: String) -> bool:
	return pname != "" and mates().has(pname)


func my_ready() -> bool:
	var me := str(party.get("me", ""))
	for m: Dictionary in members():
		if str(m.get("uid", "")) == me:
			return bool(m.get("ready", false))
	return false


func all_ready() -> bool:
	var ms := members()
	if ms.size() < 2:
		return false
	for m: Dictionary in ms:
		if not bool(m.get("ready", false)):
			return false
	return true


# ── цикл ──

func _process(delta: float) -> void:
	if _host == null:
		if _want and not _is_server:
			_retry -= delta
			if _retry <= 0.0 and _addr != "":
				_connect_now()
		return
	for _i in MAX_EVENTS:
		var ev: Array = _host.service(0)
		var kind: int = ev[0]
		if kind == ENetConnection.EVENT_NONE:
			break
		if kind == ENetConnection.EVENT_ERROR:
			if not _is_server:
				_drop("ошибка")
			break
		var peer: ENetPacketPeer = ev[1]
		if _is_server:
			_server_event(kind, peer)
		else:
			_client_event(kind, peer)
		if _host == null:
			break
	if _is_server and server != null:
		server.tick(delta)
		_flush()


func _server_event(kind: int, peer: ENetPacketPeer) -> void:
	var key := peer.get_instance_id()
	match kind:
		ENetConnection.EVENT_CONNECT:
			_peers[key] = peer
			server.on_connect(key)
		ENetConnection.EVENT_DISCONNECT:
			server.on_disconnect(key)
			_peers.erase(key)
		ENetConnection.EVENT_RECEIVE:
			var msg: Variant = JSON.parse_string(
					peer.get_packet().get_string_from_utf8())
			if typeof(msg) == TYPE_DICTIONARY:
				server.handle(key, msg)


func _flush() -> void:
	if server.outbox.is_empty():
		return
	for item: Array in server.outbox:
		var p: ENetPacketPeer = _peers.get(int(item[0]))
		if p != null and p.get_state() == ENetPacketPeer.STATE_CONNECTED:
			p.send(0, JSON.stringify(item[1]).to_utf8_buffer(),
					ENetPacketPeer.FLAG_RELIABLE)
	server.outbox.clear()


func _client_event(kind: int, peer: ENetPacketPeer) -> void:
	match kind:
		ENetConnection.EVENT_CONNECT:
			_peer = peer
			connected = true
			connected_changed.emit(true)
			_hello()
		ENetConnection.EVENT_DISCONNECT:
			_drop("сервер закрыл соединение")
			_retry = RETRY
		ENetConnection.EVENT_RECEIVE:
			var msg: Variant = JSON.parse_string(
					peer.get_packet().get_string_from_utf8())
			if typeof(msg) == TYPE_DICTIONARY:
				_on_message(msg)


func _on_message(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"welcome":
			name_ok = bool(msg.get("ok", false))
			name_reason = str(msg.get("reason", ""))
			welcome.emit(name_ok, name_reason)
		"claim_result":
			var ok := bool(msg.get("ok", false))
			if ok:
				name_ok = true
				name_reason = ""
			name_result.emit(ok, str(msg.get("name", "")),
					str(msg.get("reason", "")))
		"search_result":
			search_result.emit(msg.get("items", []) as Array)
		"lookup_result":
			friends_result.emit(msg.get("items", []) as Array)
		"invite":
			pending_invite = {from = str(msg.get("from", "")),
					party = str(msg.get("party", "")),
					count = int(msg.get("count", 1))}
			invite_received.emit(pending_invite.from, pending_invite.count)
		"party":
			party = msg
			# Все, с кем оказался в одной команде, — друзья на будущее.
			var me := str(party.get("me", ""))
			for m: Dictionary in members():
				if str(m.get("uid", "")) != me:
					GameState.remember_friend(str(m.get("name", "")))
			party_changed.emit()
		"go":
			go.emit(int(msg.get("port", 0)), int(msg.get("size", 4)),
					str(msg.get("party", "")), int(msg.get("count", 1)))
		"notice", "error":
			notice.emit(str(msg.get("text", "")))
