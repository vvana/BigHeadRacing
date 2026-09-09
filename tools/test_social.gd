# Стенд СЕРВЕРА ДРУЗЕЙ (09.09): логика SocialServer без сети — стенд сам
# зовёт on_connect/handle и читает outbox. Проверяет: единые имена (занято
# чужим uid, своё — можно, смена имени освобождает старое), поиск, приглашение
# и принятие, сброс готовности при смене состава, запуск команды в пустое
# лобби по визиткам (go всем с одним портом и размером не меньше числа
# людей), подъём комнаты, когда пустого лобби нет, отмену готовности,
# выход (двое → команда распущена), обрыв связи, потолок 8 человек.
# Реестр имён на диск НЕ пишется (persist = false). Запуск:
# godot --headless --path . --script tools/test_social.gd
extends SceneTree

var _failed := 0
var _checks := 0


## Сервер с подменёнными визитками, временем и «подъёмом комнат».
class Fake:
	extends SocialServer
	var cards: Array = []
	var now := 1000.0
	var spawned := 0
	var can_spawn := true

	func _init() -> void:
		persist = false

	func _now() -> float:
		return now

	func _cards() -> Array:
		return cards

	func _spawn_room() -> bool:
		if not can_spawn:
			return false
		spawned += 1
		return true


func _ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		print("FAIL ", what)


## Сообщения адресату key из outbox (и вычёркивает их), по типу t ("" — все).
func _take(srv: Fake, key: int, t := "") -> Array:
	var out: Array = []
	var rest: Array = []
	for item: Array in srv.outbox:
		if int(item[0]) == key and (t == "" or str(item[1].get("t", "")) == t):
			out.append(item[1])
		else:
			rest.append(item)
	srv.outbox = rest
	return out


func _last(srv: Fake, key: int, t: String) -> Dictionary:
	var all := _take(srv, key, t)
	return all[-1] if not all.is_empty() else {}


func _init() -> void:
	_run()
	print("RESULT: %d/%d ok" % [_checks - _failed, _checks])
	print("SOCIAL TEST: %s" % ("PASS" if _failed == 0 else "FAIL"))
	quit(1 if _failed > 0 else 0)


func _run() -> void:
	var srv := Fake.new()
	# --- Имена.
	srv.on_connect(1)
	srv.handle(1, {t = "hello", uid = "aaa1", name = "Андрей", car = "vz01_red"})
	var w := _last(srv, 1, "welcome")
	_ok(bool(w.get("ok", false)), "первый hello: имя свободно — принято")
	_ok(srv.owner_of("андрей") == "aaa1", "реестр без регистра: владелец aaa1")
	srv.on_connect(2)
	srv.handle(2, {t = "hello", uid = "bbb2", name = "андрей", car = "vz02_blue"})
	w = _last(srv, 2, "welcome")
	_ok(not bool(w.get("ok", true)) and str(w.get("reason")) == "taken",
			"чужой hello с тем же именем (другой регистр) — занято")
	srv.handle(2, {t = "claim", name = "Андрей "})
	var cr := _last(srv, 2, "claim_result")
	_ok(not bool(cr.get("ok", true)) and str(cr.get("reason")) == "taken",
			"claim занятого имени — отказ")
	srv.handle(2, {t = "claim", name = "Жека_777"})
	cr = _last(srv, 2, "claim_result")
	_ok(bool(cr.get("ok", false)) and srv.sessions[2].name == "Жека_777",
			"claim свободного — принято")
	srv.handle(2, {t = "claim", name = "Женёк"})
	_take(srv, 2)
	_ok(srv.owner_of("Жека_777") == "" and srv.owner_of("Женёк") == "bbb2",
			"смена имени освобождает старое")
	srv.handle(1, {t = "claim", name = "АНДРЕЙ"})
	cr = _last(srv, 1, "claim_result")
	_ok(bool(cr.get("ok", false)), "своё имя в другом регистре — можно")
	_ok(srv.name_of("aaa1") == "АНДРЕЙ", "имя обновилось в реестре")
	# Тот же uid с другого соединения — старое теряет голос.
	srv.on_connect(3)
	srv.handle(3, {t = "hello", uid = "aaa1", name = "АНДРЕЙ"})
	w = _last(srv, 3, "welcome")
	_ok(bool(w.get("ok", false)) and int(srv.peer_of_uid["aaa1"]) == 3,
			"второе подключение того же uid — имя своё, сессия новая")
	srv.on_disconnect(1)
	_ok(srv.peer_of_uid.has("aaa1"), "обрыв старой сессии не снимает uid")

	# --- Поиск.
	srv.on_connect(4)
	srv.handle(4, {t = "hello", uid = "ccc3", name = "Настя", status = "race"})
	_take(srv, 4)
	srv.handle(3, {t = "search", q = "ж"})
	var sr := _last(srv, 3, "search_result")
	var items: Array = sr.get("items", [])
	_ok(items.size() == 1 and str(items[0].name) == "Женёк"
			and bool(items[0].online), "поиск по подстроке: Женёк онлайн")
	srv.handle(3, {t = "search", q = ""})
	sr = _last(srv, 3, "search_result")
	items = sr.get("items", [])
	var names_found := PackedStringArray()
	for it: Dictionary in items:
		names_found.append(str(it.name))
	_ok(items.size() == 2 and names_found.has("Женёк") and names_found.has("Настя")
			and not names_found.has("АНДРЕЙ"), "пустой поиск: все онлайн, кроме себя")
	var nastya_status := ""
	for it: Dictionary in items:
		if str(it.name) == "Настя":
			nastya_status = str(it.status)
	_ok(nastya_status == "race", "статус «в заезде» в поиске")
	srv.on_disconnect(4)
	srv.handle(3, {t = "search", q = "наст"})
	sr = _last(srv, 3, "search_result")
	items = sr.get("items", [])
	_ok(items.size() == 1 and not bool(items[0].online),
			"ушедший игрок в поиске — не в сети")

	# --- Список друзей (lookup, 09.09 вечер): статусы по именам.
	srv.handle(3, {t = "lookup", names = ["Женёк", "настя", "Никто", "АНДРЕЙ"]})
	var lr := _last(srv, 3, "lookup_result")
	items = lr.get("items", [])
	_ok(items.size() == 4, "lookup: по записи на каждое имя (%d)" % items.size())
	_ok(items.size() == 4 and str(items[0].name) == "Женёк" and bool(items[0].online)
			and str(items[0].status) == "garage", "lookup: Женёк в сети, в гараже")
	_ok(items.size() == 4 and str(items[1].name) == "Настя" and not bool(items[1].online),
			"lookup: имя без регистра, Настя не в сети")
	_ok(items.size() == 4 and str(items[2].name) == "Никто" and not bool(items[2].online)
			and str(items[2].status) == "offline", "lookup: незнакомое имя — не в сети")
	_ok(items.size() == 4 and not bool(items[3].online),
			"lookup: своё имя — как не в сети (не приглашаем сами себя)")
	srv.handle(3, {t = "lookup", names = "мусор"})
	lr = _last(srv, 3, "lookup_result")
	_ok((lr.get("items", []) as Array).is_empty(), "lookup: не список — пустой ответ")

	# --- Приглашение и команда.
	srv.handle(3, {t = "invite", name = "никто"})
	_ok(not _take(srv, 3, "error").is_empty(), "приглашение несуществующего — ошибка")
	srv.handle(3, {t = "invite", name = "настя"})
	_ok(not _take(srv, 3, "error").is_empty(), "приглашение не в сети — ошибка")
	srv.handle(3, {t = "invite", name = "женёк"})
	var inv := _last(srv, 2, "invite")
	_ok(str(inv.get("from", "")) == "АНДРЕЙ", "Женёк получил приглашение от АНДРЕЙ")
	_ok(srv.parties.size() == 1 and srv.sessions[3].party != "",
			"у приглашающего появилась команда")
	srv.on_connect(5)
	srv.handle(5, {t = "hello", uid = "ddd4", name = "Макс", car = "ac1"})
	_take(srv, 5)
	srv.handle(5, {t = "accept"})
	_ok(not _take(srv, 5, "error").is_empty(), "accept без приглашения — ошибка")
	srv.handle(2, {t = "accept"})
	var p2 := _last(srv, 2, "party")
	var p3 := _last(srv, 3, "party")
	_ok((p2.get("members", []) as Array).size() == 2
			and (p3.get("members", []) as Array).size() == 2,
			"после принятия ростер из двоих у обоих")
	_ok(str(p2.get("me")) == "bbb2" and str(p3.get("me")) == "aaa1",
			"каждому — своя пометка me")
	var leader := ""
	for m: Dictionary in p2.members:
		if bool(m.leader):
			leader = str(m.name)
	_ok(leader == "АНДРЕЙ", "лидер — приглашавший")
	# Машина в ростере и её смена.
	srv.handle(2, {t = "car", car = "ac3-red"})
	p3 = _last(srv, 3, "party")
	var car_of_zhenek := ""
	for m: Dictionary in p3.members:
		if str(m.name) == "Женёк":
			car_of_zhenek = str(m.car)
	_ok(car_of_zhenek == "ac3-red", "смена машины видна товарищу")

	# --- Готовность и запуск.
	srv.handle(3, {t = "ready", on = true, size = 6})
	p2 = _last(srv, 2, "party")
	_ok(not srv.parties.values()[0].launch.size() > 0, "один готов — запуска нет")
	srv.cards = [{port = 9977, players = 1, joinable = true, free = 7},
			{port = 9978, players = 0, joinable = true, free = 8}]
	srv.handle(2, {t = "ready", on = true, size = 4})
	var go2 := _last(srv, 2, "go")
	var go3 := _last(srv, 3, "go")
	_ok(int(go2.get("port", 0)) == 9978 and int(go3.get("port", 0)) == 9978,
			"оба готовы — go обоим в ПУСТОЕ лобби 9978")
	_ok(int(go2.get("size", 0)) == 6 and int(go2.get("count", 0)) == 2
			and str(go2.get("party", "")) == srv.parties.keys()[0],
			"размер заезда — желание лидера (6), нас двое, id команды")
	p2 = _last(srv, 2, "party")
	var any_ready := false
	for m: Dictionary in p2.members:
		any_ready = any_ready or bool(m.ready)
	_ok(not any_ready and srv.parties.size() == 1,
			"после go готовность сброшена, команда осталась")
	# Пустого лобби нет — комната поднимается, go после появления визитки.
	srv.cards = [{port = 9977, players = 1, joinable = true, free = 7}]
	srv.handle(3, {t = "ready", on = true, size = 4})
	srv.handle(2, {t = "ready", on = true, size = 4})
	_ok(srv.spawned == 1 and _take(srv, 2, "go").is_empty(),
			"нет пустого лобби — поднимаем комнату, go пока нет")
	srv.now += 1.5
	srv.tick(1.0)
	_ok(_take(srv, 2, "go").is_empty(), "комната ещё не поднялась — ждём")
	srv.cards.append({port = 9979, players = 0, joinable = true, free = 8})
	srv.now += 1.0
	srv.tick(1.0)
	go2 = _last(srv, 2, "go")
	_ok(int(go2.get("port", 0)) == 9979, "визитка комнаты появилась — go в неё")
	# Комнат больше нет — самое людное лобби с местом.
	srv.can_spawn = false
	srv.cards = [{port = 9977, players = 1, joinable = true, free = 3},
			{port = 9978, players = 3, joinable = true, free = 5},
			{port = 9979, players = 5, joinable = true, free = 1}]
	srv.handle(3, {t = "ready", on = true})
	srv.handle(2, {t = "ready", on = true})
	go2 = _last(srv, 2, "go")
	_ok(int(go2.get("port", 0)) == 9978, "без комнат — самое людное лобби с местом (9978)")
	_ok(int(go2.get("size", 0)) == 4, "размер: нас двое, минимум 4")
	_take(srv, 3, "go")   # у 3-го тот же go — снимаем, чтобы не спутать ниже
	# Мест нет нигде — ждём и сдаёмся по таймауту.
	srv.cards = [{port = 9977, players = 7, joinable = true, free = 1}]
	srv.handle(3, {t = "ready", on = true})
	srv.handle(2, {t = "ready", on = true})
	_ok(_take(srv, 2, "go").is_empty(), "мест нет — go нет")
	srv.now += SocialServer.LAUNCH_TIMEOUT + 2.0
	srv.tick(1.0)
	_take(srv, 2, "notice")
	p2 = _last(srv, 2, "party")
	any_ready = false
	for m: Dictionary in p2.members:
		any_ready = any_ready or bool(m.ready)
	_ok(not any_ready, "таймаут поиска места — готовность сброшена")
	# Отмена готовности отменяет запуск.
	srv.cards = []
	srv.handle(3, {t = "ready", on = true})
	srv.handle(2, {t = "ready", on = true})
	_ok(not srv.parties.values()[0].launch.is_empty(), "оба готовы — ищем заезд")
	srv.handle(2, {t = "ready", on = false})
	_ok(srv.parties.values()[0].launch.is_empty(), "снял готовность — поиск отменён")
	srv.cards = [{port = 9978, players = 0, joinable = true, free = 8}]
	srv.now += 2.0
	srv.tick(1.0)
	_ok(_take(srv, 3, "go").is_empty(), "после отмены go не приходит")

	# --- Третий в команде, сброс готовности при смене состава, потолок.
	srv.handle(3, {t = "ready", on = true})
	srv.handle(3, {t = "invite", name = "макс"})
	srv.handle(5, {t = "accept"})
	p3 = _last(srv, 3, "party")
	any_ready = false
	for m: Dictionary in p3.members:
		any_ready = any_ready or bool(m.ready)
	_ok((p3.get("members", []) as Array).size() == 3 and not any_ready,
			"третий принят — трое, готовность сброшена")
	srv.handle(2, {t = "invite", name = "макс"})
	_ok(not _take(srv, 2, "error").is_empty(), "приглашение своего же — ошибка")
	var keys := [10, 11, 12, 13, 14, 15]
	for i in keys.size():
		srv.on_connect(keys[i])
		srv.handle(keys[i], {t = "hello", uid = "u%d" % i, name = "Игрок%d" % i})
		_take(srv, keys[i])
		srv.handle(3, {t = "invite", name = "Игрок%d" % i})
		var inv_i := _last(srv, keys[i], "invite")
		if i < 5:
			_ok(not inv_i.is_empty(), "приглашение %d-му ушло" % (i + 4))
			srv.handle(keys[i], {t = "accept"})
		else:
			_ok(inv_i.is_empty() and not _take(srv, 3, "error").is_empty(),
					"девятого не пригласить — потолок 8")
	_ok(srv.parties.values()[0].members.size() == 8, "в команде 8")
	# Все восемь готовы — размер заезда 8, go всем.
	srv.cards = [{port = 9978, players = 0, joinable = true, free = 8}]
	for k in [3, 2, 5, 10, 11, 12, 13, 14]:
		srv.handle(k, {t = "ready", on = true, size = 4})
	var got := 0
	for k in [3, 2, 5, 10, 11, 12, 13, 14]:
		var g := _last(srv, k, "go")
		if int(g.get("port", 0)) == 9978 and int(g.get("size", 0)) == 8 \
				and int(g.get("count", 0)) == 8:
			got += 1
	_ok(got == 8, "восьмером: go всем, размер 8")
	# Лобби, куда не влезть всем, не годится.
	srv.cards = [{port = 9978, players = 0, joinable = true, free = 6}]
	for k in [3, 2, 5, 10, 11, 12, 13, 14]:
		srv.handle(k, {t = "ready", on = true})
	_ok(_take(srv, 3, "go").is_empty(), "лобби с 6 местами восьмерым не годится")

	# --- Выход: лидер ушёл — лидер сменился; остались двое → один → распад.
	srv.handle(3, {t = "leave"})
	p2 = _last(srv, 2, "party")
	_ok((p2.get("members", []) as Array).size() == 7 and str(srv.sessions[3].party) == "",
			"лидер вышел — в команде 7, у него команды нет")
	var new_leader := ""
	for m: Dictionary in p2.members:
		if bool(m.leader):
			new_leader = str(m.name)
	_ok(new_leader == "Женёк", "лидерство перешло следующему")
	var left3 := _last(srv, 3, "party")
	_ok(left3.has("members") and (left3.members as Array).is_empty(),
			"ушедшему — пустой ростер")
	for k in [5, 10, 11, 12, 13]:
		srv.handle(k, {t = "leave"})
	_take(srv, 2)
	_ok(srv.parties.values()[0].members.size() == 2, "остались двое")
	srv.on_disconnect(14)
	var p2_after := _last(srv, 2, "party")
	_ok(srv.parties.is_empty() and (p2_after.get("members", []) as Array).is_empty()
			and str(srv.sessions[2].party) == "",
			"обрыв предпоследнего — команда распущена, оставшийся один")
	_ok(not _take(srv, 2, "notice").is_empty(), "оставшемуся сказано, что команда распущена")

	# --- Отклонение приглашения.
	srv.handle(2, {t = "invite", name = "АНДРЕЙ"})
	_take(srv, 3, "invite")
	srv.handle(3, {t = "decline"})
	_ok(not _take(srv, 2, "notice").is_empty(), "приглашавший узнал об отказе")
	srv.handle(3, {t = "accept"})
	_ok(not _take(srv, 3, "error").is_empty(), "после отказа принять нельзя")
	# Просроченное приглашение.
	srv.handle(2, {t = "invite", name = "АНДРЕЙ"})
	_take(srv, 3, "invite")
	srv.now += SocialServer.INVITE_TTL + 5.0
	srv.tick(1.0)
	srv.handle(3, {t = "accept"})
	_ok(not _take(srv, 3, "error").is_empty(), "просроченное приглашение не принять")
	# Без подтверждённого имени приглашать нельзя.
	srv.on_connect(20)
	srv.handle(20, {t = "hello", uid = "zzz", name = ""})
	w = _last(srv, 20, "welcome")
	_ok(not bool(w.get("ok", true)) and str(w.get("reason")) == "empty",
			"hello без имени — reason empty")
	srv.handle(20, {t = "invite", name = "АНДРЕЙ"})
	_ok(not _take(srv, 20, "error").is_empty(), "без имени приглашать нельзя")
	_ok(SocialServer.clean_uid("ab-12 c!") == "ab12c", "clean_uid чистит мусор")
