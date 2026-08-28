class_name Rooms
## Реестр параллельных заездов — «комнат». Задача: сервер должен держать
## столько заездов, сколько пришло игроков, а не одну гонку на всех
## (раньше пятый игрок получал отказ, а опоздавший ждал конца чужой гонки).
##
## Устройство: главный сервер (порт из Net) — «ворота» и одновременно
## первый заезд. Когда игроку в нём нет места, ворота находят по реестру
## свободную комнату или поднимают новую — ТОТ ЖЕ процесс игры с ключами
## `--server --room --port=N` на соседнем порту — и шлют клиенту
## _rx_redirect(порт). Комнаты сами никого не поднимают (никаких цепочек
## процессов) и гасятся, простояв пустыми (Main._server_tick).
##
## Реестр — файлы-«визитки» user://rooms/<порт>.json:
##   {port, players, joinable, ts}
## Каждый сервер (ворота и комнаты) раз в секунду пишет свою. Все процессы
## одного пользователя видят один user:// (на VDS — HOME=/home/bighead).
## Файловый обмен выбран нарочно: не нужен второй транспорт, падение
## любого процесса переживается — устаревшая визитка (ts старше STALE)
## просто игнорируется и прибирается.

const DIR := "user://rooms"
## Сколько комнат СВЕРХ ворот можно поднять. VDS: 1 CPU / 960 МБ, каждый
## процесс ~113 МБ и ~22% ядра — больше трёх соседних заездов это железо
## не потянет (итого 4 одновременные гонки = 16 игроков). Порты комнат:
## порт ворот +1 … +ROOMS_MAX — на VDS файрвол пуст (policy ACCEPT), но
## при переезде их надо открыть (см. server/README.md).
const ROOMS_MAX := 3
const STALE := 5.0        # визитка старше — процесс считается мёртвым
## Поднятая комната пишет первую визитку через 1-3 с (загрузка сцены).
## До этой отметки её порт занят «авансом» — иначе каждый повторный hello
## ждущего гостя поднимал бы ещё один процесс на том же порту.
const SPAWN_GRACE := 15.0

## Порт → unix-секунда запуска процесса комнаты (только в памяти ворот).
static var _spawn_time := {}
## Порт → pid поднятого процесса. Нужен для уборки «зомби»: на Linux
## завершившийся ребёнок висит defunct, пока родитель его не подождёт
## (пойман на VDS 27.08: комната погасла по таймеру, а в ps остался
## `[godot] <defunct>`). OS.is_process_running внутри делает
## waitpid(WNOHANG) — он и хоронит покойника.
static var _spawn_pid := {}


## Похоронить завершившиеся процессы комнат. Ворота зовут раз в секунду
## (Main._server_tick, вместе с визиткой).
static func reap_children() -> void:
	for p: int in _spawn_pid.keys():
		if not OS.is_process_running(int(_spawn_pid[p])):
			_spawn_pid.erase(p)


static func _now() -> float:
	return Time.get_unix_time_from_system()


## Своя визитка: сколько игроков и есть ли место новому (Main._joinable_here).
static func write_card(port: int, players: int, joinable: bool) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open("%s/%d.json" % [DIR, port], FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		port = port, players = players, joinable = joinable, ts = _now(),
	}))


## Комната гасится штатно — прибирает визитку, порт сразу свободен.
static func remove_card(port: int) -> void:
	DirAccess.remove_absolute("%s/%d.json" % [DIR, port])


## Живые визитки (устаревшие молча прибираются — их процесс умер).
static func cards() -> Array:
	var out: Array = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for f: String in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var data: Variant = JSON.parse_string(
				FileAccess.get_file_as_string(DIR + "/" + f))
		if typeof(data) != TYPE_DICTIONARY \
				or not data.has_all(["port", "players", "joinable", "ts"]):
			continue
		if _now() - float(data.ts) > STALE:
			dir.remove(f)
			continue
		out.append(data)
	return out


## Куда перенаправить игрока: заезд с местом, НЕ этот процесс. Из равных
## берём самый людный — игроков собираем вместе, а не размазываем по
## полупустым комнатам. −1 — мест нет нигде.
static func find_joinable(own_port: int) -> int:
	var best := -1
	var best_players := -1
	for c: Dictionary in cards():
		if int(c.port) == own_port or not bool(c.joinable):
			continue
		if int(c.players) > best_players:
			best_players = int(c.players)
			best = int(c.port)
	return best


## Свободный порт под новую комнату: без живой визитки и не занятый
## авансом только что поднятым процессом. −1 — лимит ROOMS_MAX исчерпан.
static func free_port(base: int) -> int:
	var busy := {}
	for c: Dictionary in cards():
		busy[int(c.port)] = true
	for i in range(1, ROOMS_MAX + 1):
		var p := base + i
		if busy.has(p):
			continue
		if _now() - float(_spawn_time.get(p, -1e12)) < SPAWN_GRACE:
			continue
		return p
	return -1


## Комната уже поднимается (процесс запущен, визитки ещё нет)? Тогда новых
## не плодим — hello гостя повторяется раз в секунду и дождётся визитки.
static func spawn_pending() -> bool:
	var busy := {}
	for c: Dictionary in cards():
		busy[int(c.port)] = true
	for p: int in _spawn_time:
		if not busy.has(p) and _now() - float(_spawn_time[p]) < SPAWN_GRACE:
			return true
	return false


## Поднять процесс-комнату. Дев-машина и VDS запускают игру из проекта —
## нужен --path; экспортированный exe находит свой pck сам.
static func spawn(port: int) -> void:
	_spawn_time[port] = _now()
	var args := PackedStringArray(["--headless"])
	if not OS.has_feature("standalone"):
		args.append_array(PackedStringArray(
				["--path", ProjectSettings.globalize_path("res://")]))
	args.append("res://scenes/Main.tscn")
	args.append_array(PackedStringArray(
			["--", "--server", "--room", "--port=%d" % port]))
	var pid := OS.create_process(OS.get_executable_path(), args)
	_spawn_pid[port] = pid
	print("[rooms] поднимаем комнату на порту %d (pid %d)" % [port, pid])
