extends Node
## Сетевой слой (autoload Net). Модель — ВЫДЕЛЕННЫЙ СЕРВЕР: на VDS крутится
## headless-экземпляр игры, он считает всю гонку (2 слота игроков + боты) и
## рассылает состояние. Клиенты шлют только ввод. Никто из игроков не хостит,
## поэтому преимущества «нулевого пинга у хозяина» ни у кого нет.
##
## Запуск сервера:  godot --headless --path . res://scenes/Main.tscn -- --server
## Порт и адрес по умолчанию лежат в user://net.cfg (правится из игры).

enum Mode { OFFLINE, SERVER, CLIENT }

const PORT := 9977
## Версия сетевого протокола. ПОДНИМАТЬ при любом несовместимом изменении
## RPC (сигнатуры, формат снимка, каналы): сервер не пускает клиента с
## другой версией с внятным сообщением — иначе рассинхрон версий выглядит
## как загадочные «игра сломалась» (RPC молча отбрасываются). История:
## 1 — сервер считает всех, 2 — клиент-авторитетные машины игроков,
## 3 — проверка версии + канал состояния + прогресс позднего входа,
## 4 — пофинишный финиш (_rx_car_finished),
## 5 — лента событий оружия (_rx_weapon_event; новый @rpc-метод сдвигает
##     таблицу RPC-идентификаторов — старые клиенты несовместимы),
## 6 — 4 игрока + синхронный старт из лобби + перезапуск клиентов после
##     заезда (_rx_reset — новый @rpc-метод, сдвиг таблицы) + случайная
##     трасса заезда (_rx_track — тоже новый @rpc-метод; один бамп на обе
##     параллельные правки, как договаривались для 5).
## 7 — подсевший к идущему заезду встаёт НА МЕСТО своей машины, а не на
##     стартовую решётку (_rx_race_running получил аргумент), и лобби
##     показывает, какие слоты заняли боты (_rx_bots — новый @rpc-метод).
## 8 — опоздавший к идущему заезду (позже JOIN_LATE_MAX) в него больше НЕ
##     подсаживается, а ждёт в лобби следующего (_rx_lobby_wait_next —
##     новый @rpc-метод, сдвиг таблицы RPC-идентификаторов).
## 9 — метка тика автора в состояниях (11-е число в _rx_pstate и в снимке
##     _rx_state): по ней клиентские буферы строят ровную шкалу машин
##     живых игроков — без неё соперник-игрок дёргался даже на локалхосте.
## 10 — параллельные заезды-«комнаты» (Rooms.gd): игрок, которому нет места
##      (слоты заняты или опоздал к идущему заезду), перенаправляется в
##      свободный заезд на соседнем порту (_rx_redirect — новый @rpc-метод,
##      сдвиг таблицы RPC-идентификаторов).
## 11 — толчки игрок-игроку (_rx_shove — новый @rpc-метод, сдвиг таблицы):
##      таран машины живого игрока доставляется её владельцу через сервер
##      (машины клиент-авторитетны, и раньше игрока было «не сдвинуть»);
##      заодно лазер игрока отматывает цели на ~0.4 c (попадаешь в то, что
##      видел) и рисуется у стрелявшего мгновенно.
## 12 — заморозка ездит по сети: остаток дебафа стоит 4-м байтом на машину
##      в снимке (_rx_state) и 12-м числом в состоянии владельца
##      (_rx_pstate). Без этого «синим» соперник был только на своём
##      экране, и заразность заморозки в сетевой игре не работала вовсе.
const PROTOCOL := 12
const PLAYER_SLOTS := 4      # столько машин отдаётся живым игрокам
const CONFIG_PATH := "user://net.cfg"
const CONNECT_TIMEOUT := 5.0   # столько ждём ответа сервера, потом сдаёмся

## Сервер сообщает о слотах СВОИМИ сигналами, а не пробрасывает
## multiplayer.peer_disconnected: тот приходит и сюда, и в Main, а порядок
## обработчиков — по порядку подключения. Net подписывается первым и к
## моменту вызова Main уже СТИРАЕТ слот из slot_of_peer — Main не находил
## машину и оставлял её на замершем вводе ушедшего игрока (газ в пол
## навсегда). Теперь слот едет прямо в сигнале.
signal player_joined(id: int, slot: int)
signal player_left(id: int, slot: int)

signal joined()                   # клиент: соединение установлено
signal join_failed(reason: String)
signal left()                     # клиент: соединение потеряно

var mode := Mode.OFFLINE
# Адрес VDS по умолчанию. Игрок может вписать свой в поле на экране
# выбора машины — тогда он запомнится в user://net.cfg и перекроет это.
var host := "139.100.234.166"
var port := PORT
## «Домашний» порт игрока — ворота. join_server при перенаправлении в
## комнату (remember=false) его НЕ трогает: комната смертна, и если она не
## ответила, Main возвращает игрока именно сюда (_on_join_failed_in_race),
## а не бросает на тупиковом экране «Сервер не ответил».
var home_port := PORT
## Клиент: номер машины, которой я управляю (0..PLAYER_SLOTS-1). −1 пока не выдан.
var my_slot := -1
## Сервер: peer_id → слот (0..PLAYER_SLOTS-1). Слот без игрока ведёт бот.
var slot_of_peer := {}
## Сервер: пиры БЕЗ слота (все заняты). Их не отвергаем, как раньше, —
## Main перенаправит такого «гостя» в свободный заезд-комнату (Rooms.gd),
## а откажет только когда мест нет нигде.
var guests := {}
## Этот процесс — комната, поднятая воротами (`--room`): сам комнат не
## плодит и гасится, простояв пустым (см. Rooms.gd, Main._server_tick).
var is_room := false
## Клиент: сколько раз подряд нас перенаправляли между заездами
## (_rx_redirect). Защита от пинг-понга переполненных комнат; сбрасывается,
## когда сервер выдал слот (_rx_welcome) или игрок подключается сам.
var redirect_hops := 0


func _ready() -> void:
	_load_config()
	# Ключи процесса-комнаты (после `--`): порт командной строки сильнее
	# порта из user://net.cfg.
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = maxi(1, int(a.trim_prefix("--port=")))
		elif a == "--room":
			is_room = true
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


func is_server() -> bool:
	return mode == Mode.SERVER


func is_client() -> bool:
	return mode == Mode.CLIENT


func is_online() -> bool:
	return mode != Mode.OFFLINE


## Ждал ли этот процесс роль сервера (ключ `-- --server` в командной строке).
static func wants_server() -> bool:
	return OS.get_cmdline_user_args().has("--server")


func start_server() -> bool:
	var peer := ENetMultiplayerPeer.new()
	# Слотов PLAYER_SLOTS, но пускаем заметно больше: пир сверх слотов —
	# «гость», его перенаправят в свободный заезд-комнату (Rooms.gd), и
	# запас нужен, чтобы волна гостей не упёрлась в отказ самого ENet.
	# Каналов 8: поток состояния идёт по каналу 1, отдельно от reliable-
	# событий (см. Main._rx_state) — каналы надо выделить явно, иначе
	# отправка с transfer_channel > 0 молча не уйдёт.
	var err := peer.create_server(port, PLAYER_SLOTS + 8, 8)
	if err != OK:
		push_error("Не удалось поднять сервер на порту %d: %s" % [port, error_string(err)])
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.SERVER
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("[net] сервер слушает UDP-порт %d, слотов игроков: %d"
			% [port, PLAYER_SLOTS])
	return true


## remember=false — для тестовых стендов: они бьют в 127.0.0.1, и запись
## этого адреса в user://net.cfg затирала игроку адрес VDS — после
## прогона тестов игра «переставала подключаться» («сервер не ответил»),
## хотя сервер был жив. Пойманы на живом пользователе 24.08.
func join_server(address: String, p: int, remember := true) -> bool:
	host = address
	port = p
	if remember:
		# Подключение по воле игрока (кнопка «ПО СЕТИ») — счёт прыжков
		# перенаправлений начинается заново, а выбранный порт становится
		# «домом». При самом перенаправлении remember=false: порт комнаты
		# в net.cfg не пишем, дом и счёт не трогаем.
		redirect_hops = 0
		home_port = p
		save_config()
	var peer := ENetMultiplayerPeer.new()
	# Каналов столько же, сколько у сервера (ENet берёт минимум из двух).
	var err := peer.create_client(address, p, 8)
	if err != OK:
		join_failed.emit("Не удалось начать подключение: %s" % error_string(err))
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	return true


## Полный сброс в одиночный режим — при выходе из сетевой гонки в меню.
func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	mode = Mode.OFFLINE
	my_slot = -1
	slot_of_peer.clear()
	guests.clear()


## Свободный слот игрока, либо −1 если все заняты.
func _free_slot() -> int:
	var taken := {}
	for s: int in slot_of_peer.values():
		taken[s] = true
	for i in PLAYER_SLOTS:
		if not taken.has(i):
			return i
	return -1


func _on_peer_connected(id: int) -> void:
	var slot := _free_slot()
	if slot < 0:
		# Мест нет — но соединение НЕ рвём: это гость, Main._rx_hello
		# перенаправит его в свободный заезд-комнату (Rooms.gd), и лишь
		# когда мест нет нигде — откажет по-человечески.
		guests[id] = true
		print("[net] пир %d без слота — гость, ждёт перенаправления" % id)
		return
	slot_of_peer[id] = slot
	print("[net] пир %d занял слот %d (игроков: %d)"
			% [id, slot, slot_of_peer.size()])
	player_joined.emit(id, slot)


func _on_peer_disconnected(id: int) -> void:
	if guests.erase(id):
		return
	if slot_of_peer.has(id):
		var slot: int = slot_of_peer[id]
		print("[net] пир %d ушёл, слот %d освобождён" % [id, slot])
		slot_of_peer.erase(id)
		player_left.emit(id, slot)


func _on_connected() -> void:
	joined.emit()


func _on_connect_failed() -> void:
	mode = Mode.OFFLINE
	multiplayer.multiplayer_peer = null
	join_failed.emit("Сервер не ответил")


func _on_server_gone() -> void:
	mode = Mode.OFFLINE
	multiplayer.multiplayer_peer = null
	my_slot = -1
	left.emit()


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	host = cfg.get_value("net", "host", host)
	port = cfg.get_value("net", "port", port)
	# Амнистия отравленного cfg. До 28.08 поле адреса в гараже показывало
	# ТЕКУЩИЙ порт: после перенаправления (_rx_redirect) там оказывался порт
	# КОМНАТЫ, игрок жал «ПО СЕТИ» — и порт комнаты сохранялся как
	# постоянный. Комнаты смертны, и такой игрок вечно видел «Сервер не
	# ответил за 5 с» (поймано у живого игрока: в cfg остался 9978). Порт из
	# диапазона комнат мог попасть в cfg только этой ошибкой — комнаты
	# никогда не были «домом»; возвращаем ворота.
	if port > PORT and port <= PORT + Rooms.ROOMS_MAX:
		port = PORT
	home_port = port


func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("net", "host", host)
	cfg.set_value("net", "port", port)
	cfg.save(CONFIG_PATH)
