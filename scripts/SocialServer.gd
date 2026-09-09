class_name SocialServer
extends RefCounted
## Серверная половина «друзей» (09.09): единые имена, поиск, приглашения,
## команды до PARTY_MAX человек и запуск команды в один заезд. Живёт в
## процессе ВОРОТ (Social.gd поднимает её рядом с гонкой), но САМА сети не
## знает: транспорт зовёт on_connect/on_disconnect/handle и разгребает
## outbox — так всю логику гоняет стенд tools/test_social.gd без ENet.
##
## Сообщения — словари с полем "t" (см. Social.gd, там же клиентская
## сторона). Реестр имён — user://names.json: {имя_в_нижнем_регистре:
## {name, uid, ts}}. uid — случайная строка из профиля игрока
## (GameState.uid): по ней игрок узнаётся после переустановки имени,
## перезапуска игры и с другого компьютера с тем же профилем.
##
## Команда («party»): {id, leader, members: [uid…], ready: {uid: true},
## size: {uid: желаемый размер заезда}, launch: {since}}. Все члены нажали
## «ГОТОВ» — tick() ищет заезд с местом на всех (по визиткам Rooms) и
## шлёт каждому go{port,size,party,count}; Main на этом порту держит
## лобби, пока не съедутся все (Main._party_waiting). Выход любого члена
## сбрасывает готовность остальных; остался один — команда распущена.

const GS := preload("res://scripts/GameState.gd")
const NetScript := preload("res://scripts/Net.gd")

const NAMES_PATH := "user://names.json"
const PARTY_MAX := 8
const INVITE_TTL := 90.0       # секунд живёт приглашение без ответа
const LAUNCH_TIMEOUT := 45.0   # секунд ждём место для команды, потом отказ
const SEARCH_MAX := 12
const UID_MAX := 40

var names := {}          # имя в нижнем регистре → {name, uid, ts}
var sessions := {}       # ключ соединения → {uid, name, car, status, party}
var peer_of_uid := {}    # uid → ключ соединения (кто сейчас на связи)
var parties := {}        # id → команда (см. шапку)
var invites := {}        # uid приглашённого → {from: uid, party: id, ts}
var outbox: Array = []   # [[ключ, сообщение], …] — транспорт отправляет
var gate_port: int = NetScript.PORT   # порт ворот: базовый для комнат
var persist := true      # стенды выключают запись names.json
var _party_seq := 0
var _time_accum := 0.0


func _init() -> void:
	_load_names()


# ── переопределяемое стендами (время, визитки, комнаты, диск) ──

func _now() -> float:
	return Time.get_unix_time_from_system()


## Живые визитки заездов (Rooms): {port, players, joinable, free}.
func _cards() -> Array:
	return Rooms.cards()


## Поднять комнату под команду. true — процесс запущен (или уже
## поднимается), false — лимит комнат исчерпан.
func _spawn_room() -> bool:
	if Rooms.spawn_pending():
		return true
	var port := Rooms.free_port(gate_port)
	if port <= 0:
		return false
	Rooms.spawn(port)
	return true


func _load_names() -> void:
	if not persist or not FileAccess.file_exists(NAMES_PATH):
		return
	var data: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(NAMES_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	for k in data:
		var v: Variant = data[k]
		if typeof(v) == TYPE_DICTIONARY and v.has("name") and v.has("uid"):
			names[str(k)] = {name = str(v.name), uid = str(v.uid),
					ts = float(v.get("ts", 0.0))}


func _save_names() -> void:
	if not persist:
		return
	var f := FileAccess.open(NAMES_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(names))


# ── транспорт → логика ──

func on_connect(key: int) -> void:
	sessions[key] = {uid = "", name = "", car = "", status = "garage",
			party = ""}


func on_disconnect(key: int) -> void:
	var s: Variant = sessions.get(key)
	if s == null:
		return
	sessions.erase(key)
	var uid: String = s.uid
	if uid != "" and peer_of_uid.has(uid) and int(peer_of_uid[uid]) == key:
		peer_of_uid.erase(uid)
		invites.erase(uid)
		_leave_party(uid)


func handle(key: int, msg: Dictionary) -> void:
	var s: Variant = sessions.get(key)
	if s == null:
		return
	match str(msg.get("t", "")):
		"hello":
			_hello(key, s, msg)
		"claim":
			_claim(key, s, str(msg.get("name", "")))
		"car":
			s.car = str(msg.get("car", "")).left(64)
			_broadcast_party(s.party)
		"status":
			s.status = "race" if str(msg.get("s", "")) == "race" else "garage"
			_broadcast_party(s.party)
		"search":
			_search(key, s, str(msg.get("q", "")))
		"invite":
			_invite(key, s, str(msg.get("name", "")))
		"accept":
			_accept(key, s)
		"decline":
			_decline(key, s)
		"ready":
			_ready(key, s, bool(msg.get("on", false)),
					int(msg.get("size", 0)))
		"leave":
			_leave_party(s.uid)
		"ping":
			pass


## Раз в секунду (транспорт зовёт из _process): срок приглашений и
## запуск готовых команд.
func tick(delta: float) -> void:
	_time_accum += delta
	if _time_accum < 1.0:
		return
	_time_accum = 0.0
	var now := _now()
	for uid: String in invites.keys():
		if now - float(invites[uid].ts) > INVITE_TTL:
			invites.erase(uid)
	for pid: String in parties.keys():
		var p: Dictionary = parties[pid]
		if not p.launch.is_empty():
			_try_launch(p)


# ── рукопожатие и имена ──

## Чистка uid: только буквы/цифры, не длиннее UID_MAX.
static func clean_uid(u: String) -> String:
	var out := ""
	for ch in u:
		if ch.is_valid_identifier() or ch.is_valid_int():
			out += ch
	return out.left(UID_MAX)


static func name_key(n: String) -> String:
	return GS.sanitize_name(n).to_lower()


## Кому принадлежит имя: "" — свободно, иначе uid владельца.
func owner_of(n: String) -> String:
	var rec: Variant = names.get(name_key(n))
	return str(rec.uid) if rec != null else ""


## Имя, зарегистрированное за uid ("" — нет).
func name_of(uid: String) -> String:
	for k in names:
		if str(names[k].uid) == uid:
			return str(names[k].name)
	return ""


func _hello(key: int, s: Dictionary, msg: Dictionary) -> void:
	var uid := clean_uid(str(msg.get("uid", "")))
	if uid == "":
		_send(key, {t = "error", text = "Профиль без идентификатора"})
		return
	# Тот же uid уже на связи (второй запуск игры, переподключение до
	# таймаута) — старая сессия теряет право голоса: её отключение больше
	# не выбьет игрока из команды.
	if peer_of_uid.has(uid):
		var old_key: int = int(peer_of_uid[uid])
		if old_key != key and sessions.has(old_key):
			sessions[old_key].uid = ""
			sessions[old_key].party = ""
	s.uid = uid
	peer_of_uid[uid] = key
	s.car = str(msg.get("car", "")).left(64)
	s.status = "race" if str(msg.get("status", "")) == "race" else "garage"
	var want := GS.sanitize_name(str(msg.get("name", "")))
	var ok := false
	var reason := ""
	if want == "":
		reason = "empty"
	else:
		var owner := owner_of(want)
		if owner == "" or owner == uid:
			_register(want, uid)
			ok = true
		else:
			reason = "taken"
	s.name = want if ok else ""
	# Команда по uid могла пережить обрыв? Нет: обрыв = выход (см.
	# on_disconnect). Но сессия могла быть подменена (второй запуск) —
	# членство переносим на новую.
	for pid: String in parties:
		if parties[pid].members.has(uid):
			s.party = pid
	_send(key, {t = "welcome", ok = ok, name = s.name, reason = reason})
	_broadcast_party(s.party)


## Записать имя за uid (старое имя этого uid освобождается).
func _register(n: String, uid: String) -> void:
	var k := name_key(n)
	for old in names.keys():
		if str(names[old].uid) == uid and old != k:
			names.erase(old)
	names[k] = {name = n, uid = uid, ts = _now()}
	_save_names()


func _claim(key: int, s: Dictionary, raw: String) -> void:
	var n := GS.sanitize_name(raw)
	if s.uid == "":
		_send(key, {t = "claim_result", ok = false, name = n,
				reason = "no_uid"})
		return
	if n == "":
		_send(key, {t = "claim_result", ok = false, name = n,
				reason = "empty"})
		return
	var owner := owner_of(n)
	if owner != "" and owner != s.uid:
		_send(key, {t = "claim_result", ok = false, name = n,
				reason = "taken"})
		return
	_register(n, s.uid)
	s.name = n
	_send(key, {t = "claim_result", ok = true, name = n, reason = ""})
	_broadcast_party(s.party)


# ── поиск ──

## Имена, содержащие q (без регистра), кроме своего; онлайн — первыми.
## Пустой q — все, кто сейчас на связи.
func _search(key: int, s: Dictionary, raw: String) -> void:
	var q := name_key(raw)
	var items: Array = []
	for k: String in names:
		if q != "" and not k.contains(q):
			continue
		var rec: Dictionary = names[k]
		var uid: String = rec.uid
		if uid == s.uid:
			continue
		var online := peer_of_uid.has(uid)
		if q == "" and not online:
			continue
		items.append({name = rec.name, online = online,
				party = _party_of(uid) != "",
				status = _status_of(uid)})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.online != b.online:
			return a.online
		return str(a.name).to_lower() < str(b.name).to_lower())
	if items.size() > SEARCH_MAX:
		items.resize(SEARCH_MAX)
	_send(key, {t = "search_result", q = raw, items = items})


func _party_of(uid: String) -> String:
	for pid: String in parties:
		if parties[pid].members.has(uid):
			return pid
	return ""


## ВАЖНО: ключ соединения — любое целое, в том числе ОТРИЦАТЕЛЬНОЕ
## (транспорт даёт get_instance_id(), он переполняет int64) — «на связи»
## проверяется только через peer_of_uid.has(), никаких «k >= 0».
func _status_of(uid: String) -> String:
	var ms: Variant = _session_of(uid)
	return str(ms.status) if ms != null else "offline"


func _session_of(uid: String) -> Variant:
	if not peer_of_uid.has(uid):
		return null
	return sessions.get(int(peer_of_uid[uid]))


# ── приглашения и команда ──

func _invite(key: int, s: Dictionary, raw: String) -> void:
	if s.uid == "" or s.name == "":
		_send(key, {t = "error", text = "Сначала подтверди своё имя"})
		return
	var target := owner_of(raw)
	if target == "":
		_send(key, {t = "error", text = "Игрок «%s» не найден" % raw})
		return
	if target == s.uid:
		_send(key, {t = "error", text = "Себя приглашать не нужно"})
		return
	if not peer_of_uid.has(target):
		_send(key, {t = "error", text = "%s сейчас не в игре" % name_of(target)})
		return
	var tp := _party_of(target)
	if tp != "" and tp == s.party:
		_send(key, {t = "error", text = "%s уже в твоей команде" % name_of(target)})
		return
	if tp != "":
		_send(key, {t = "error", text = "%s уже в другой команде" % name_of(target)})
		return
	var p: Dictionary
	if s.party == "":
		p = _create_party(s.uid)
	else:
		p = parties[s.party]
	if p.members.size() >= PARTY_MAX:
		_send(key, {t = "error", text = "В команде уже %d человек" % PARTY_MAX})
		return
	invites[target] = {from = s.uid, party = p.id, ts = _now()}
	var tk: int = int(peer_of_uid[target])
	_send(tk, {t = "invite", from = s.name, party = p.id,
			count = p.members.size()})
	_send(key, {t = "notice", text = "Приглашение отправлено: %s" % name_of(target)})
	_broadcast_party(p.id)


func _create_party(leader: String) -> Dictionary:
	_party_seq += 1
	var pid := "p%d_%d" % [_party_seq, int(_now()) % 100000]
	var p := {id = pid, leader = leader, members = [leader], ready = {},
			size = {}, launch = {}}
	parties[pid] = p
	var s: Variant = _session_of(leader)
	if s != null:
		s.party = pid
	return p


func _accept(key: int, s: Dictionary) -> void:
	var inv: Variant = invites.get(s.uid)
	if inv == null:
		_send(key, {t = "error", text = "Приглашение уже недействительно"})
		return
	invites.erase(s.uid)
	var p: Variant = parties.get(str(inv.party))
	if p == null:
		_send(key, {t = "error", text = "Команда уже распалась"})
		_send(key, {t = "party", id = "", members = []})
		return
	if p.members.size() >= PARTY_MAX:
		_send(key, {t = "error", text = "В команде уже нет места"})
		return
	if s.party != "" and s.party != p.id:
		_leave_party(s.uid)
	if not p.members.has(s.uid):
		p.members.append(s.uid)
	s.party = p.id
	# Состав изменился — готовность всех сбрасывается: заезд запускается
	# только когда «ГОТОВ» нажал каждый из нынешнего состава.
	_reset_ready(p)
	_notify_party(p.id, "%s в команде" % s.name)
	_broadcast_party(p.id)


func _decline(key: int, s: Dictionary) -> void:
	var inv: Variant = invites.get(s.uid)
	if inv == null:
		return
	invites.erase(s.uid)
	if peer_of_uid.has(str(inv.from)):
		_send(int(peer_of_uid[str(inv.from)]),
				{t = "notice", text = "%s отклонил приглашение" % s.name})
	_send(key, {t = "notice", text = "Приглашение отклонено"})


func _ready(key: int, s: Dictionary, on: bool, size: int) -> void:
	var p: Variant = parties.get(s.party)
	if p == null:
		_send(key, {t = "party", id = "", members = []})
		return
	if on:
		p.ready[s.uid] = true
		if size > 0:
			p.size[s.uid] = size
	else:
		p.ready.erase(s.uid)
		# Передумал — запуск, если шёл, отменяется.
		p.launch = {}
	_broadcast_party(p.id)
	_check_launch(p)


## Все на месте и все готовы — ищем заезд (tick → _try_launch).
func _check_launch(p: Dictionary) -> void:
	if p.members.size() < 2:
		return
	for uid: String in p.members:
		if not p.ready.has(uid) or not peer_of_uid.has(uid):
			return
	if p.launch.is_empty():
		p.launch = {since = _now()}
		_notify_party(p.id, "Все готовы — ищем заезд…")
		_try_launch(p)


## Размер заезда для команды: желание лидера (или самого крупного из
## пожеланий), но не меньше числа людей и в рамках 4..8.
func launch_size(p: Dictionary) -> int:
	var want: int = int(p.size.get(p.leader, 0))
	if want <= 0:
		for uid: String in p.members:
			want = maxi(want, int(p.size.get(uid, 0)))
	return clampi(maxi(want, p.members.size()), GS.RACE_SIZE_MIN,
			GS.RACE_SIZE_MAX)


## Куда сажать команду. Лучше всего ПУСТОЕ лобби (никто не стартует у
## нас под носом и размер заезда возьмут наш); нет пустого — поднимаем
## комнату; не можем — самое людное лобби, где хватит мест; ничего —
## ждём до LAUNCH_TIMEOUT и сдаёмся.
func _try_launch(p: Dictionary) -> void:
	var need: int = p.members.size()
	var empty := -1
	var best := -1
	var best_players := -1
	for c: Dictionary in _cards():
		if not bool(c.get("joinable", false)):
			continue
		var free := int(c.get("free", 0))
		if free < need:
			continue
		var players := int(c.get("players", 0))
		if players == 0:
			if empty < 0 or int(c.port) < empty:
				empty = int(c.port)
		elif players > best_players:
			best_players = players
			best = int(c.port)
	var target := empty
	if target < 0:
		if _spawn_room():
			_notify_party(p.id, "Поднимаем заезд для команды…")
			if _now() - float(p.launch.since) <= LAUNCH_TIMEOUT:
				return
		target = best
	if target < 0:
		if _now() - float(p.launch.since) > LAUNCH_TIMEOUT:
			p.launch = {}
			_reset_ready(p)
			_notify_party(p.id, "Все заезды заняты — попробуйте через минуту")
			_broadcast_party(p.id)
		return
	var size := launch_size(p)
	for uid: String in p.members:
		if peer_of_uid.has(uid):
			_send(int(peer_of_uid[uid]), {t = "go", port = target, size = size,
					party = p.id, count = need})
	print("[social] команда %s (%d чел.) отправлена в заезд на порту %d"
			% [p.id, need, target])
	p.launch = {}
	# После заезда команда остаётся, но «ГОТОВ» жмут заново.
	_reset_ready(p)
	_broadcast_party(p.id)


func _reset_ready(p: Dictionary) -> void:
	p.ready.clear()
	p.launch = {}


## Выход из команды: сам, по обрыву или потому что распалась.
func _leave_party(uid: String) -> void:
	var pid := _party_of(uid)
	var s: Variant = _session_of(uid)
	if s != null:
		s.party = ""
	if pid == "":
		if s != null:
			_send(int(peer_of_uid[uid]), {t = "party", id = "", members = []})
		return
	var p: Dictionary = parties[pid]
	p.members.erase(uid)
	p.ready.erase(uid)
	p.size.erase(uid)
	p.launch = {}
	if s != null:
		_send(int(peer_of_uid[uid]), {t = "party", id = "", members = []})
	var who := name_of(uid)
	if p.members.size() < 2:
		# Остался один — команды больше нет, он снова играет сам.
		for m: String in p.members:
			var ms: Variant = _session_of(m)
			if ms != null:
				ms.party = ""
				var mk: int = int(peer_of_uid[m])
				_send(mk, {t = "party", id = "", members = []})
				_send(mk, {t = "notice",
						text = "%s вышел — команда распущена" % who})
		parties.erase(pid)
		return
	if p.leader == uid:
		p.leader = p.members[0]
	_reset_ready(p)
	_notify_party(pid, "%s вышел из команды" % who)
	_broadcast_party(pid)


func _notify_party(pid: String, text: String) -> void:
	var p: Variant = parties.get(pid)
	if p == null:
		return
	for uid: String in p.members:
		if peer_of_uid.has(uid):
			_send(int(peer_of_uid[uid]), {t = "notice", text = text})


## Ростер команды — всем её членам. Каждому — с пометкой, он ли это.
func _broadcast_party(pid: String) -> void:
	var p: Variant = parties.get(pid)
	if p == null:
		return
	var members: Array = []
	for uid: String in p.members:
		var ms: Variant = _session_of(uid)
		members.append({
			uid = uid,
			name = name_of(uid),
			car = str(ms.car) if ms != null else "",
			ready = p.ready.has(uid),
			leader = uid == p.leader,
			online = ms != null,
			status = str(ms.status) if ms != null else "offline",
		})
	for uid: String in p.members:
		if peer_of_uid.has(uid):
			_send(int(peer_of_uid[uid]), {t = "party", id = pid, members = members,
					me = uid, launching = not p.launch.is_empty()})


func _send(key: int, msg: Dictionary) -> void:
	outbox.append([key, msg])
