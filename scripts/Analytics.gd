extends Node
## МЕТРИКИ (10.09) — автозагрузка Analytics. Собирает обезличенные события
## игры (запуск, заезд, матч, реклама, покупка, уровень, команда) и отдаёт
## их СЕРВЕРУ ДРУЗЕЙ по уже работающему соединению Social (UDP 9990,
## сообщение {t = "metric", e, d}). Сервер пишет их строками в
## user://metrics/<дата>.jsonl, а веб-панель на VDS читает эти файлы
## (server/metrics/README.md).
##
## Почему через Social, а не своим HTTP: соединение уже есть, переживает
## смену сцен, не требует ни TLS, ни открытого TCP-порта, ни разрешения
## «cleartext» на Android. Почему с ОЧЕРЕДЬЮ: игрок часто играет без связи
## (оффлайн-заезд, телефон в метро) — события ждут в user://metrics_queue.json
## и уезжают при следующем выходе на связь, поэтому оффлайновые заезды в
## статистике не теряются.
##
## Что НЕ собираем: ничего, чего сервер и так не знает (имя и uid у него
## есть из реестра имён), никаких адресов, текстов и содержимого профиля
## сверх агрегатов ниже.

const QUEUE_PATH := "user://metrics_queue.json"
const QUEUE_MAX := 150          # событий в очереди (старые вытесняются)
const SEND_PER_TICK := 8        # сколько отправляем за один кадр-флаш
const FLUSH_EVERY := 2.0        # секунд между попытками флаша

var enabled := true
var _queue: Array = []
var _t := 0.0
var _session_sent := false


func _ready() -> void:
	# В web-сборке (Яндекс Игры) метрики собирает сама платформа, а UDP там
	# нет вовсе — Social не работает, очередь росла бы впустую.
	if OS.has_feature("web"):
		enabled = false
		set_process(false)
		return
	# Выделенный сервер (ворота и комнаты) метрик не шлёт: у него нет
	# игрока, а Social в роли сервера никуда не отправляет — очередь просто
	# росла бы на диске (поймано на VDS 10.09, файл metrics_queue.json).
	# Стенды и тесты — тоже: иначе в аналитике будут сотни их «заездов».
	if Net.wants_server() or GameState.is_test_profile():
		enabled = false
		set_process(false)
		return
	_load_queue()
	Social.connected_changed.connect(_on_social)
	# Сигналы профиля: покупки, уровни, реклама (GameState про Analytics не
	# знает — так стенды-скрипты без автозагрузок продолжают компилироваться).
	GameState.purchased.connect(_on_purchased)
	GameState.level_up.connect(_on_level_up)
	GameState.ad_rewarded.connect(_on_ad)
	session()


func _process(delta: float) -> void:
	if not enabled or _queue.is_empty():
		return
	_t += delta
	if _t < FLUSH_EVERY:
		return
	_t = 0.0
	_flush()


# ── события ──

## Запуск игры: платформа, версия, «толщина» профиля. Одно на запуск.
func session() -> void:
	if _session_sent:
		return
	_session_sent = true
	var st: Dictionary = GameState.stats
	push_event("session", {
		platform = _platform(),
		version = str(ProjectSettings.get_setting("application/config/version",
				"")),
		protocol = Net.PROTOCOL,
		level = GameState.level_info().x,
		xp = GameState.xp,
		money = GameState.money,
		cars = GameState.owned_cars.size() + GameState.FREE_CARS.size(),
		races = int(st.get("races", 0)) if not st.is_empty() else 0,
		rating = GameState.rating(),
		mode = GameState.game_mode,
		locale = OS.get_locale_language(),
	})


## Финиш заезда (Main._show_finish). weapons — сколько раз игрок применил
## каждый вид оружия за заезд (ключ — номер вида Weapons.*).
func race(place: int, size: int, humans: int, online: bool, base: String,
		kills: int, deaths: int, track: String, ms: int,
		weapons: Dictionary, party: bool) -> void:
	push_event("race", {
		place = place, size = size, humans = humans, online = online,
		car = base, kills = kills, deaths = deaths, track = track,
		ms = ms, weapons = weapons, party = party,
		rating = GameState.rating(), level = GameState.level_info().x,
	})


## Итог футбольного матча (Soccer._finish_match).
func soccer(result: int, goals: int, mine: int, theirs: int, ms: int) -> void:
	push_event("soccer", {result = result, goals = goals, score_me = mine,
			score_them = theirs, ms = ms,
			level = GameState.level_info().x})


## Заезд командой друзей поехал (CarSelect._on_party_go).
func party_race(count: int, size: int) -> void:
	push_event("party", {count = count, size = size})


## Досмотренный ролик: coins — что начислено (0 — первый ролик пары).
func _on_ad(coins: int) -> void:
	push_event("ad", {coins = coins, pair = coins > 0,
			level = GameState.level_info().x})


## Покупка: kind — "car" / "item" / "weapon" / "pack".
func _on_purchased(kind: String, key: String, price: int) -> void:
	push_event("buy", {kind = kind, key = key, price = price,
			money_after = GameState.money, level = GameState.level_info().x})


func _on_level_up(level: int) -> void:
	push_event("level", {level = level, xp = GameState.xp,
			money = GameState.money})


func _on_social(on: bool) -> void:
	if on:
		_flush()


# ── очередь ──

## Положить событие в очередь (и сразу попробовать отправить). d — только
## числа, строки и флаги; словари внутри допустимы (оружие).
func push_event(e: String, d: Dictionary) -> void:
	if not enabled:
		return
	_queue.append({e = e, d = d, ts = int(Time.get_unix_time_from_system())})
	if _queue.size() > QUEUE_MAX:
		_queue = _queue.slice(_queue.size() - QUEUE_MAX)
	_save_queue()
	_flush()


## Отправить первые SEND_PER_TICK событий. Не на связи — ничего (ждут).
## Отправленное вычёркиваем сразу: повтор хуже потери — в аналитике
## двойные заезды не отличить от настоящих.
func _flush() -> void:
	if not enabled or _queue.is_empty() or not Social.connected:
		return
	var sent := 0
	while sent < SEND_PER_TICK and not _queue.is_empty():
		var ev: Dictionary = _queue[0]
		Social.send_metric(str(ev.e), ev.d as Dictionary, int(ev.ts))
		_queue.remove_at(0)
		sent += 1
	if sent > 0:
		_save_queue()


func _load_queue() -> void:
	if not FileAccess.file_exists(QUEUE_PATH):
		return
	var data: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(QUEUE_PATH))
	if data is Array:
		for it in data:
			if it is Dictionary and (it as Dictionary).has("e"):
				_queue.append({e = str(it.e), d = it.get("d", {}),
						ts = int(it.get("ts", 0))})
		if _queue.size() > QUEUE_MAX:
			_queue = _queue.slice(_queue.size() - QUEUE_MAX)


func _save_queue() -> void:
	if _queue.is_empty():
		if FileAccess.file_exists(QUEUE_PATH):
			DirAccess.remove_absolute(
					ProjectSettings.globalize_path(QUEUE_PATH))
		return
	var f := FileAccess.open(QUEUE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_queue))


func _platform() -> String:
	if OS.has_feature("android"):
		return "android"
	if OS.has_feature("ios"):
		return "ios"
	if OS.has_feature("web"):
		return "web"
	if OS.has_feature("linux"):
		return "linux"
	if OS.has_feature("macos"):
		return "macos"
	return "windows"
