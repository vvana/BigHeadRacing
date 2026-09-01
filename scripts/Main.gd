extends Node3D
## Гонка в духе Rock'n'Roll Racing: трасса, игрок + 3 ИИ-соперника,
## отсчёт 3-2-1-GO, 4 круга, позиции, «резинка» ИИ, HUD (скорость, круг,
## позиция, HP, боезапас), финиш. Всё собирается из кода.

const LAPS := 4
# Машин в заезде — ВЫБИРАЕМОЕ число (гараж, 4..8). Оффлайн это игрок +
# (N−1) ботов (GameState.race_size); по сети размер текущего заезда диктует
# сервер (Net.race_size), и КАЖДЫЙ слот — для живого игрока: пустой до
# подключения ведёт бот.
func _car_count() -> int:
	return Net.race_size if Net.is_online() else GameState.race_size
# Снимков состояния в секунду — с частотой физики. На машину уходит 43 байта,
# на четыре — меньше 200, то есть ~10 КБ/с на клиента: для двух игроков это
# ничто. А ровность движения от частоты зависит прямо: замер «насколько
# пройденный за кадр путь сходится с присланной скоростью» (tools/test_net.gd)
# даёт 5.0% при 30 снимках в секунду и 1.2% при 60 (эталон одиночной игры —
# 0.3%). Игрок жаловался как раз на дёрганое движение, так что берём 60.
const SNAP_HZ := 60.0
# Сколько ждать ОСТАЛЬНЫХ живых игроков после подключения первого.
# Не дождались — едем по старинке, пустые слоты берут боты.
# 27.08 по просьбе пользователя укорочено 20 -> 5 с. Былую проблему «у
# второго игра грузится дольше и первый уезжает с ботами» это не вернёт:
# старт всё равно ждёт hello от КАЖДОГО подключённого (_maybe_start), а
# подключение продлевает ожидание до JOIN_GRACE.
const LOBBY_WAIT := 5.0
# Сколько ждать ещё, когда в лобби заходит очередной игрок (см.
# _on_peer_joined): ожидание продлевается до этой отметки, если оставалось
# меньше, — чтобы зашедшие вразнобой всё равно стартовали вместе.
# Урезано вместе с LOBBY_WAIT (8 -> 5): продление длиннее самого ожидания
# выглядело бы как «зашёл второй — ждать стало ДОЛЬШЕ».
const JOIN_GRACE := 5.0
# Сколько лобби показывает «слоты заняли боты», прежде чем начать отсчёт.
# Без паузы игрок не успевает увидеть, с кем едет: отсчёт прячет лобби.
const BOTS_SHOW := 2.2
# НАЧАВШИЙСЯ ЗАЕЗД НОВЫХ НЕ БЕРЁТ (31.08). Раньше первые 25 секунд можно
# было «подсесть», забрав машину у бота, — и подсевший появлялся там, куда
# бот успел уехать, то есть далеко впереди уже играющих. Теперь опоздавшему
# поднимают ОТДЕЛЬНЫЙ заезд-комнату (Rooms.gd, см. _route_elsewhere): своё
# лобби, свой отсчёт, своя гонка с первого метра.
# На сколько метров позади самой отставшей машины сажаем того, кто был в
# лобби, но догрузился уже после старта (см. _seat_joiner_at_tail): его
# машину до этого вёл бот, и её место ему не отдаём.
const JOIN_TAIL_GAP := 8.0
# Полотно переменной ширины, поэтому порог вылета считается в точке машины:
# полуширина здесь + 0.5 м (машина у самой стены отстоит от оси почти ровно
# на полуширину, дальше — уже за ограждением).
const OFFTRACK_MARGIN := 0.5
const OFFTRACK_WAIT_PLAYER := 2.0
const OFFTRACK_WAIT_AI := 1.0
# Переворот: «верх» кузова завалился больше чем на ~70° от вертикали.
const FLIP_DOT := 0.35
const FLIP_WAIT := 1.5
# Застревание: почти не движется, хотя гонка идёт.
const STALL_SPEED := 1.2
const STALL_WAIT := 5.0

var _car: Car                       # машина игрока (= _cars[0])
var _cars: Array[Car] = []
var _track: TrackBuilder
var _track_kind := TrackBuilder.KIND_GRASS  # вид трассы этого заезда
var _progress: Array[float] = []    # накопленный путь вдоль оси, м
var _last_offset: Array[float] = []
# Клетка стартовой решётки каждой машины: welcome возвращает на неё свою
# машину (пока ждали слот, её могла увезти марионетка со старым снимком).
var _grid_xf: Array[Transform3D] = []
var _laps_done: Array[int] = []
var _offtrack_time: Array[float] = []
var _flip_time: Array[float] = []
var _stall_time: Array[float] = []
var _finished := false              # заезд окончен ЦЕЛИКОМ (все или таймаут)
var _my_finished := false           # моя машина пересекла финиш (баннер показан)
var _finish_order: Array[int] = []  # индексы машин в порядке пересечения финиша
var _first_finish_time := -1.0      # когда финишировал первый (для таймаута)
# Доезжать дают всем, но не вечно: спустя столько секунд после первого
# финишёра заезд закрывается принудительно (места — по текущему прогрессу).
const FINISH_TIMEOUT := 40.0

var _player_marker: Node3D          # стрелка-указатель над своей машиной
var _rival_markers := {}            # слот → стрелка живого соперника
var _marker_time := 0.0

var _net_started := false           # сервер: гонка идёт (иначе лобби)
# Комната-процесс (Net.is_room), простоявшая пустой без гонки столько
# секунд, гасится и освобождает память VDS — ворота поднимут новую при
# нужде (см. Rooms.gd).
const ROOM_IDLE_EXIT := 120.0
var _card_accum := 0.0              # сервер: до следующей визитки Rooms
var _room_idle := 0.0               # комната: сколько секунд стоит пустой
# Сервер: слоты, чей игрок подключился к УЖЕ ИДУЩЕМУ заезду слишком поздно
# и ждёт следующего. Их машины остаются за ботами, состояние от этих
# клиентов сервер не принимает (см. _rx_pstate) — иначе машина в гонке
# скакала бы между ботом и стоящим на решётке новичком.
var _late_slots := {}
var _snap_accum := 0.0              # накопитель до следующего снимка
var _net_lost := false              # клиент: связь пропала, уходим в гараж
var _kicked := false                # клиент: сервер отказал (версии и т.п.)
var _going_home := false            # клиент: комната молчит, едем к воротам
# Толчки игрок-игроку (протокол 11): на клиенте — время последнего доклада
# по жертве, на сервере — по паре (агрессор*100+жертва). Оба — антидребезг.
var _shove_sent := {}
# Разбор ПРИРОДЫ дыр в потоке снимков (см. _rx_state): метка часов сервера
# и номер нашего кадра на прошлом приходе.
var _srv_stamp_prev := -1.0
var _gap_frames_prev := 0
# Замер потерь по меткам (включают стенды): длина пропажи -> сколько раз.
# Клиент: места, присланные сервером (протокол 13). 0 — ещё не приходило.
var _net_place: Array[int] = []   # размер задаёт _spawn_cars
var _loss_probe := false
var _loss_prev := -1.0
var _loss_hist := {}
var _loss_total := 0
var _loss_got := 0


## Отчёт замера потерь: сколько снимков пропало и КАКИМИ СЕРИЯМИ. Серии по
## 1-3 лечатся избыточностью (прошлые состояния в том же пакете), длинные —
## только буфером.
func net_loss_report() -> String:
	if _loss_got <= 0:
		return "нет данных"
	var keys := _loss_hist.keys()
	keys.sort()
	var parts := PackedStringArray()
	for k: int in keys:
		parts.append("%d:%d" % [k, _loss_hist[k]])
	return "дошло %d, пропало %d (%.1f%%); серии пропаж %s" % [
			_loss_got, _loss_total,
			100.0 * float(_loss_total) / float(_loss_got + _loss_total),
			" ".join(parts)]
# Когда мы сами нарисовали свой лазер, не дожидаясь сервера (см.
# _client_tick): эхо _rx_weapon_fx об этом же выстреле рисовать не надо.
var _laser_predicted := -10.0
var _last_state_time := 0.0         # клиент: когда пришёл последний снимок
# Диагностика потока снимков (см. _rx_state и tools/test_net.gd): сколько
# снимков пришло, сумма и максимум интервалов между ними. Три сложения на
# снимок — по ним видно, ровно ли сервер шлёт, а это первое, что надо знать
# при жалобе «соперники едут дёргано».
var _state_seen := 0
var _state_gap_sum := 0.0
var _state_gap_max := 0.0
var _state_gaps_big := 0        # сколько дыр потока длиннее 100 мс
var _wd_last := 0                   # вачдог фризов: мс прошлого кадра физики
# Вачдог-«между чем»: имя и мс последней пройденной точки кадра. Если между
# двумя точками прошло >250 мс — печатаем, между какими: это делит фриз на
# «внутри физики» / «между физикой и рендером» / «в рендере+ОС».
var _wd_pt_name := ""
var _wd_pt_time := 0


func _wd_mark(pt: String) -> void:
	var now := Time.get_ticks_msec()
	if _wd_pt_time > 0 and now - _wd_pt_time > 250:
		print("[freeze-где] %s -> %s: %d мс" % [_wd_pt_name, pt, now - _wd_pt_time])
	_wd_pt_name = pt
	_wd_pt_time = now
var _lobby_wait := -1.0             # сервер: остаток ожидания, <0 — не идёт
# Сервер: синхронный старт. Гонку нельзя начинать, пока у подключённого
# игрока ещё грузится сцена (первый вход — компиляция шейдеров): он
# пропустил бы отсчёт и въехал в уже идущий заезд. «Загрузился» = прислал
# hello (клиент шлёт его из готовой сцены Main). _want_start — старт уже
# запрошен (Пробел или таймаут лобби), ждём только загрузки всех.
var _hello_done := {}               # слот → true: клиент прислал hello
var _join_time := {}                # слот → секунда подключения (для грейса)
var _want_start := false
# Сервер: старт решён, но лобби ещё показывает ботов, занявших пустые
# слоты (_start_with_bots). Гонка ещё не идёт — второй раз стартовать нельзя.
var _starting := false
# Номер попытки старта: если во время показа ботов подключился живой игрок,
# попытка отменяется (номер меняется), и заезд снова ждёт людей.
var _start_gen := 0
var _loading_told := false          # статус «ждём загрузки» уже разослан
# Подключился, но hello так и не пришёл (старый клиент, зависшая загрузка) —
# спустя столько секунд перестаём ждать такого и стартуем без него.
const HELLO_GRACE := 25.0
var _roster := PackedStringArray()  # id моделей машин по слотам
# Имена по слотам: живые игроки — как представились в hello, боты — ники
# из PlayerNames (бот не должен отличаться от игрока — просьба 01.09).
# Сервер рассылает при каждом изменении (_rx_names), как ростер.
var _names := PackedStringArray()
var _lobby: Lobby                   # полноэкранное лобби на клиенте
# Клиент: какие слоты заняты живыми игроками (для экрана лобби).
# Размер задаёт _spawn_cars — слотов столько, сколько машин в заезде.
var _slot_taken: Array[bool] = []
# Клиент: битовая маска слотов, которые перед стартом забрали боты (сервер
# шлёт её в _rx_bots) — лобби показывает их машины вместо «ждём игрока…».
var _bot_mask := 0
# Клиент: сцена доживает последний кадр перед перестройкой (_rx_track с
# чужой трассой/размером, _rx_reset). Смена сцены случается в конце кадра,
# а RPC, приехавшие с нею в одном пакете, исполняются ещё В СТАРОЙ сцене:
# welcome записывал Net.my_slot в умирающую сцену, новая видела «слот уже
# есть», не представлялась заново (_say_hello выходит сразу) и оставалась
# без своей машины и стрелок. Гонка ЖИВАЯ: успел пакет в тот же кадр —
# зависли, пришёл кадром позже — RPC не нашёл узла и всё сходилось.
var _rebuilding := false
# Клиент: пришёл к УЖЕ ИДУЩЕМУ заезду и ждёт в лобби следующего. Запасной
# путь на случай, когда своей комнаты поднять не вышло (ROOMS_MAX):
# управление выключено, машину в его слоте ведёт бот сервера; дождётся
# _rx_reset — перезагрузится в новую гонку.
var _wait_next_race := false
var _feed_box: VBoxContainer        # лента «кто кого чем» (события оружия)
var _feed_pending: Array[Array] = []  # события, ждущие места в ленте

var _speed_label: Label
var _lap_label: Label
var _pos_label: Label
var _weapon_icon: TextureRect   # значок оружия (пустой слот — гекс EMPTY)
var _weapon_name: Label
var _slot_empty_tex: Texture2D  # гекс пустого слота (нарезан из референса)
var _last_weapon := -2          # чтобы не перезагружать иконку каждый кадр
var _warn_panel: Control
var _warn_label: Label
var _minimap: Minimap           # мини-карта в правом верхнем углу
var _count_label: Label         # отсчёт 3-2-1-GO
var _finish_root: Control       # баннер финиша
var _finish_label: Label
var _finish_xp_label: Label     # строка «+N ОПЫТА · УРОВЕНЬ K» на баннере
var _my_kills := 0              # мои уничтоженные соперники (опыт за заезд)
var _ui_font: FontFile          # Russo One — индустриальный, с кириллицей

# ---- Всплывающие анонсы (Announcer) и события, которые их порождают ----
var _announcer: Announcer
# Летальное оружие (жертву уничтожает с одного попадания) — только такие
# попадания считаются «убийствами» для серий и первой крови.
const LETHAL_KINDS := [Weapons.ROCKET, Weapons.LASER, Weapons.AIRSTRIKE,
		Weapons.MINE]
const KILL_STREAK_WINDOW := 1.2   # окно серии, с (лазер бьёт всех за кадр)
var _kill_streak := {}            # атакующий -> {count, time}
var _first_blood_done := false
var _last_lap_told := false
var _race_time := 0.0             # сколько моя машина уже гоняется (после GO)
var _lead_shown := false          # подтверждённое «я лидер» для анонсов
var _lead_flip_time := 0.0        # дебаунс смены лидерства


func _ready() -> void:
	# Выделенный сервер: тот же Main, но без камеры, HUD и своей машины.
	# Запуск: godot --headless --path . res://scenes/Main.tscn -- --server
	if Net.wants_server() and not Net.is_online():
		if not Net.start_server():
			get_tree().quit(1)
			return
	_track_kind = _pick_track_kind()
	_setup_environment()

	_track = TrackBuilder.new()
	_track.kind = _track_kind
	_track.name = "Track"
	add_child(_track)

	_spawn_cars()
	_spawn_weapon_boxes()

	if not Net.is_server():
		var cam := IsoCamera.new()
		cam.name = "IsoCamera"
		cam.target = _car
		add_child(cam)
		cam.make_current()
		_setup_hud()

	if Net.is_server():
		Net.player_joined.connect(_on_peer_joined)
		Net.player_left.connect(_on_peer_left)
		print("[net] трасса готова, ждём игроков%s" % _mem_note())
		# Сцена могла быть перезагружена после прошлого заезда — тогда
		# игроки УЖЕ подключены, и peer_connected по ним больше не придёт.
		# Возвращаем их машины на присланный ввод руками.
		for pid: int in Net.slot_of_peer.keys():
			_on_peer_joined(pid, Net.slot_of_peer[pid])
	elif Net.is_client():
		print("[net] сцена гонки готова%s" % _mem_note())
		# Клиент ничего не начинает сам: представляемся серверу и ждём
		# от него слот, ростер машин и команду отсчёта. Если рукопожатие
		# ещё не закончилось (сцену могли открыть сразу), ждём сигнала —
		# RPC, отправленный до соединения, просто пропадёт.
		Net.left.connect(_on_net_lost)
		# После перенаправления в комнату (_rx_redirect) сцена грузится, пока
		# соединение ещё устанавливается, — обрыв на этом этапе (комната
		# умерла) должен показать причину, а не молча висеть в лобби.
		Net.join_failed.connect(_on_join_failed_in_race, CONNECT_ONE_SHOT)
		if _lobby:
			_lobby.show_screen()
		var peer := multiplayer.multiplayer_peer
		if peer != null and peer.get_connection_status() 				== MultiplayerPeer.CONNECTION_CONNECTED:
			_say_hello()
		else:
			Net.joined.connect(_say_hello, CONNECT_ONE_SHOT)
			# Соединение ещё устанавливается (мы после _rx_redirect). ENet
			# может молчать дольше, чем игрок готов ждать, — свой таймаут,
			# как в CarSelect: не ответили — судьбу решит
			# _on_join_failed_in_race (вернёт домой к воротам).
			_watch_join_timeout()
	else:
		_countdown()


## Стартовая решётка: 2 колонны. Оффлайн — игрок впереди слева и 3 бота.
## По сети — 4 машины, и все 4 слота держатся за живыми игроками. Пустой
## слот до подключения ведёт бот (net_role LOCAL), при подключении сервер
## переключает машину на присланное состояние — так гонка идёт с любым
## числом игроков от одного до размера заезда (4..8, выбор в гараже).
func _spawn_cars() -> void:
	var st := _track.start_transform()
	var dir := -st.basis.z
	var right := st.basis.x
	var count := _car_count()
	var ids := _pick_car_ids(count)

	for i in count:
		var is_p := i == 0 and not Net.is_online()
		var car := Car.new()
		car.is_player = is_p
		car.name = "Car%d" % i
		car.track = _track
		car.race = self
		# На старте у каждого одно случайное оружие; дальше — боксы.
		car.weapon = Weapons.random_weapon()
		if not is_p:
			# Лёгкий разброс характеристик, чтобы ИИ не ехали строем.
			car.max_speed += randf_range(-1.2, 1.2)
			car.engine_power += randf_range(-8.0, 8.0)
			# Боты слабее игрока: «класс» режет темп на 6-14% (жалоба
			# «противники едут очень хорошо» — игра должна быть попроще).
			car.ai_skill = randf_range(0.86, 0.94)

		var row := i / 2
		var col := i % 2
		var pos: Vector3 = st.origin - dir * (2.0 + row * 5.0) 				+ right * (2.2 if col == 1 else -2.2)
		car.transform = Transform3D(st.basis, pos)
		add_child(car)
		_set_car_model(car, ids[i])

		_cars.append(car)
		_grid_xf.append(car.transform)
		_progress.append(0.0)
		_laps_done.append(0)
		_offtrack_time.append(0.0)
		_flip_time.append(0.0)
		_stall_time.append(0.0)
		_last_offset.append(0.0)
		_slot_taken.append(false)
		_net_place.append(0)

	_roster = ids
	# Имена. Клиент ждёт их с сервера (_rx_names) — до тех пор пустые;
	# сервер и оффлайн раздают ботам ники сразу (имена живых игроков сервер
	# перепишет из hello). Оффлайн нулевой слот — сам игрок.
	_names.resize(_cars.size())
	if not Net.is_client():
		var nicks := PlayerNames.pick(_cars.size())
		for i in _cars.size():
			_names[i] = nicks[i]
		if not Net.is_online():
			_names[0] = GameState.display_name()
	_car = _cars[0]
	if Net.is_client():
		# Пока сервер не выдал слот, СВОЕЙ машины нет — все марионетки.
		for c in _cars:
			c.net_make_puppet()
	elif not Net.is_server():
		_attach_marker(0)

	var length := _track._curve.get_baked_length()
	for i in _cars.size():
		_cars[i].reset_track_offset()
		var off := _cars[i].track_offset
		_last_offset[i] = off
		# Стартовый прогресс = фактическая отметка относительно ЛИНИИ
		# (решётка стоит до линии, off у конца круга → прогресс < 0).
		# Если у всех начинать с нуля, задний ряд получает фору ~5-7 м
		# и позиция в HUD врёт, когда соперник борется рядом.
		_progress[i] = off - length if off > length * 0.5 else off


## Заменить визуальную модель машины (при получении ростера с сервера
## модель может смениться — каждый игрок выбирает свою).
func _set_car_model(car: Car, id: String) -> void:
	# Выделенному серверу модели НЕ НУЖНЫ: он ничего не рисует. Мало того,
	# они вредны — headless-рендер на каждый меш сыпет «Parameter m is null»,
	# и journald, поймав тысячи строк за секунду, включает rate limit и
	# выбрасывает ВСЁ, включая наши [net]-сообщения. Плюс ~100 МБ памяти на
	# однопроцессорной VDS. Физика от моделей не зависит: форма корпуса
	# строится в Car._build_collision.
	if Net.is_server():
		return
	var old := car.get_node_or_null("CarModel")
	if old:
		car.remove_child(old)
		old.queue_free()
	var model := CarModelLibrary.build(id)
	if model:
		model.name = "CarModel"
		car.add_child(model)
		car.collect_wheels(model)
		# Фары (ночной город) строятся в Car._ready, когда модели ещё нет, —
		# на нос конкретной машины их сажаем здесь.
		car.fit_headlights(model)
	else:
		_build_placeholder_visual(car)


## Стрелка-указатель над машиной: своя — зелёная, соперник — оранжевая.
## По сети стрелки у ВСЕХ соперников, включая ботов: бот не должен
## отличаться от живого игрока (просьба 01.09).
func _attach_marker(index: int, rival := false) -> void:
	if index < 0 or index >= _cars.size():
		return
	var marker := _build_player_marker(
			Color(1.0, 0.55, 0.1) if rival else Color(0.15, 0.95, 0.25))
	_cars[index].add_child(marker)
	# Стрелка top_level, то есть за машиной сама не едет — её ставит _process.
	# Но первый кадр он ещё не отработал, и стрелка мигнула бы в начале
	# координат: ставим её на место сразу.
	marker.global_position = _cars[index].global_position + Vector3.UP * 2.4
	_cars[index].has_marker = true
	if rival:
		_rival_markers[index] = marker
	else:
		_player_marker = marker


## Боксы с оружием: ПО ОДНОМУ на отметку. Бокс не исчезает, каждый
## проехавший забирает свой случайный бонус (см. WeaponBox). Стоят НЕ по
## центру полотна: смещение к бортам, стороны чередуются — за бонусом
## нужно целиться. Смещения детерминированные (без randf): расстановка
## не сдвигает поток случайных чисел, регрессионные стенды стабильны.
func _spawn_weapon_boxes() -> void:
	var curve: Curve3D = _track._curve
	var length := curve.get_baked_length()
	var marks: Array[float] = [0.06, 0.17, 0.28, 0.38, 0.48,
			0.58, 0.70, 0.81, 0.92]
	for i in marks.size():
		var off := length * marks[i]
		var max_lat: float = maxf(0.0, _track.half_width_at_offset(off) - 1.6)
		var lateral := (1.0 if i % 2 == 0 else -1.0) \
				* minf(2.4 if i % 3 == 0 else 3.6, max_lat)
		var box := WeaponBox.new()
		add_child(box)
		box.global_position = curve.sample_baked(off) \
				+ _track.right_at_offset(off) * lateral + Vector3.UP * 0.85


## Лидер гонки (по прогрессу) — цель авиаудара.
func leader_car() -> Car:
	var best := 0
	for i in range(1, _cars.size()):
		if _progress[i] > _progress[best]:
			best = i
	return _cars[best]


## Накопленный путь машины вдоль оси трассы, м (магнит сравнивает по нему,
## кто впереди по гонке).
func progress_of(car: Car) -> float:
	var i := _cars.find(car)
	return _progress[i] if i >= 0 else 0.0


## Оружие из бокса с поправкой на положение в гонке: идущему ПОСЛЕДНИМ
## вдвое реже выпадают мина и масло (ставить их сзади некому), а сильно
## отставшему от лидера чаще выпадает ускорение (см. Weapons.random_weapon).
func pickup_weapon_for(car: Car) -> int:
	var i := _cars.find(car)
	if i < 0:
		return Weapons.random_weapon()
	var lead := _progress[0]
	for j in _cars.size():
		lead = maxf(lead, _progress[j])
	return Weapons.random_weapon(
			_place_of(i) == _cars.size(), lead - _progress[i])


## Модели для всех машин заезда. Оффлайн: нулевая — выбранная игроком,
## остальные — случайные другие. По сети сервер раздаёт всем одинаковый
## ростер (клиенты присылают свой выбор в _rx_hello), иначе игроки видели
## бы у соперника не ту машину, что он выбрал.
func _pick_car_ids(count: int) -> PackedStringArray:
	var pool := CarModelLibrary.CAR_IDS.duplicate()
	pool.shuffle()
	var res := PackedStringArray()
	if not Net.is_online():
		res.append(GameState.selected_car_id)
	for id: String in pool:
		if res.size() >= count:
			break
		if not res.has(id):
			res.append(id)
	while res.size() < count:
		res.append(pool[res.size() % pool.size()])
	return res


## Отсчёт. Оффлайн — сразу при загрузке. На сервере тот же код гоняет
## таймеры и РАССЫЛАЕТ цифры клиентам (своего HUD у него нет). Клиент
## отсчёт сам не запускает: он показывает то, что пришло в _rx_count.
func _countdown() -> void:
	# Кадр на раскладку HUD: pivot отсчёта берётся из размера full-rect.
	await get_tree().process_frame
	if not is_inside_tree():
		return
	if _count_label:
		_count_label.visible = true
	for txt in ["3", "2", "1"]:
		_pop_count(txt, UiKit.YELLOW)
		if Net.is_server():
			_rx_count.rpc(txt)
		await get_tree().create_timer(0.8).timeout
		if not is_inside_tree():
			return
	_pop_count("GO!", UiKit.TEAL)
	if Net.is_server():
		_rx_count.rpc("GO!")
	for c in _cars:
		c.controls_enabled = true
	await get_tree().create_timer(0.7).timeout
	if is_inside_tree() and _count_label:
		_count_label.visible = false


## Цифра отсчёта «выпрыгивает»: масштаб 1.6 → 1.0 с пружинкой.
func _pop_count(txt: String, color: Color) -> void:
	if _count_label == null:
		return   # на сервере HUD не собирается
	_count_label.text = txt
	_count_label.add_theme_color_override("font_color", color)
	_count_label.pivot_offset = _count_label.size * 0.5
	_count_label.scale = Vector2(1.6, 1.6)
	var tw := _count_label.create_tween()
	tw.tween_property(_count_label, "scale", Vector2.ONE, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Прогресс, круги, рефилл боезапаса, «резинка» ИИ.
func _physics_process(_delta: float) -> void:
	# Вачдог замирания главного потока: пауза между кадрами физики дольше
	# 250 мс — это уже видимый фриз у ВСЕХ (на сервере встаёт поток снимков
	# всем клиентам разом). Печатаем всегда — событие редкое, а жалобу
	# «все дёргаются одновременно» без этой строки не отладить.
	_wd_mark("физика")
	var wd_now := Time.get_ticks_msec()
	if _wd_last > 0 and wd_now - _wd_last > 250:
		print("[freeze] кадр физики встал на %d мс (%s, t=%.1f c, гонка=%s)"
				% [wd_now - _wd_last,
				"сервер" if Net.is_server() else "клиент",
				wd_now / 1000.0, str(_net_started)])
	_wd_last = wd_now
	if _cars.is_empty():
		return
	var curve: Curve3D = _track._curve
	var length := curve.get_baked_length()

	for i in _cars.size():
		# Отметка НЕПРЕРЫВНАЯ (см. Car.sync_track_offset): глобальный поиск
		# ближайшей точки перепрыгивал на соседний виток кольца, стоило
		# машине уехать за ограждение, и прогресс прибавлял сотни метров —
		# круги, места и «резинка» ИИ сходили с ума.
		_cars[i].sync_track_offset()
		var off := _cars[i].track_offset
		var d := off - _last_offset[i]
		if d > length * 0.5:
			d -= length
		elif d < -length * 0.5:
			d += length
		_progress[i] += d
		_last_offset[i] = off

		var lap := int(floorf(_progress[i] / length))
		if lap > _laps_done[i]:
			_laps_done[i] = lap
			# Финиш ПОФИНИШНЫЙ: доехавшая машина останавливается и
			# получает место по порядку пересечения, остальные ДОЕЗЖАЮТ
			# (раньше первый финишёр обрывал заезд всем — «3 и 4 не
			# доехали»). Решает не клиент, а сервер/оффлайн — иначе у
			# двоих игроков места раздались бы по-разному.
			if lap >= LAPS and not Net.is_client() \
					and not _cars[i].race_over:
				_car_finished(i)

	# Таймаут доезда: не ждать вечно застрявшего/уничтоженного.
	if not Net.is_client() and _first_finish_time >= 0.0 and not _finished \
			and Time.get_ticks_msec() / 1000.0 - _first_finish_time \
			> FINISH_TIMEOUT:
		_finish_race()

	# «Резинка»: отстающий ИИ едет бодрее, убежавший — спокойнее.
	# ОФФЛАЙН темп меряется от ИГРОКА (машина 0): убежавший вперёд бот
	# сбрасывает (кламп снизу 0.8 — его можно догнать), отставший слегка
	# поджимает (сверху 1.15 — от него можно уехать). По сети машина 0 —
	# просто один из слотов, там мерим от лидера. Поверх резинки — ai_skill:
	# постоянная «слабина» бота (боты не должны ехать идеально).
	if not Net.is_client():
		var ref := _progress[0]
		if Net.is_online():
			for i in _cars.size():
				ref = maxf(ref, _progress[i])
		for i in _cars.size():
			if _cars[i].net_role == Car.NetRole.LOCAL and not _cars[i].is_player:
				_cars[i].ai_rubber = _cars[i].ai_skill * clampf(
						1.0 + (ref - _progress[i]) / 120.0, 0.8, 1.15)

	if Net.is_server():
		_server_tick(_delta)
	elif Net.is_client():
		_client_tick(_delta)
	_wd_mark("физика-конец")


## Стрелка-указатель (конус остриём вниз) над машиной.
## Материал unshaded + emission — видна при любом освещении.
func _build_player_marker(color: Color) -> Node3D:
	var marker := MeshInstance3D.new()
	marker.name = "PlayerMarker"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.34
	cone.bottom_radius = 0.0   # остриё вниз — указывает на машину
	cone.height = 0.6
	marker.mesh = cone
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color * 0.85
	marker.material_override = mat
	# Стрелка ставится по ВИДИМОМУ положению машины (см. _process), а не
	# висит на теле: тело шагает 60 Гц, и на плавном рендере машина уползала
	# бы из-под собственной стрелки. Отсюда top_level.
	marker.top_level = true
	marker.position = Vector3(0, 2.4, 0)
	return marker


func _process(delta: float) -> void:
	_wd_mark("рендер")
	# Лёгкое покачивание по высоте (без вращения — оно отвлекало). Стрелки
	# top_level, поэтому ставим их сами — по ВИДИМОМУ положению машины
	# (Car.visual_origin), чтобы стрелка не отставала от машины на кадр.
	_marker_time += delta
	var bob := 2.4 + 0.12 * sin(_marker_time * 3.0)
	if _player_marker and _car != null:
		_player_marker.global_position = _car.visual_origin() + Vector3.UP * bob
	for slot: int in _rival_markers:
		if slot < _cars.size():
			var m: Node3D = _rival_markers[slot]
			m.global_position = _cars[slot].visual_origin() + Vector3.UP * bob
	if _car and _speed_label:
		_speed_label.text = str(int(_car.speed_kmh()))
		if _car.weapon != _last_weapon:
			_last_weapon = _car.weapon
			if _car.weapon >= 0:
				_weapon_icon.texture = Weapons.icon(_car.weapon)
				_weapon_name.text = Weapons.display_name(_car.weapon)
			else:
				_weapon_icon.texture = _slot_empty_tex
				_weapon_name.text = "возьми бокс"
		_lap_label.text = "КРУГ %d/%d" % [
				clampi(_laps_done[_my_index()] + 1, 1, LAPS), LAPS]
		_pos_label.text = "МЕСТО %d/%d" % [_player_place(), _cars.size()]
		_tick_announcements(delta)
		_pump_feed()

	if Net.is_server():
		# У сервера нет ни ввода, ни HUD — только автовозврат машин.
		_check_recovery(delta)
		return

	# Ввод опрашиваем напрямую (как езду в Car), а не через события —
	# надёжнее: событие может не дойти до _unhandled_input.
	if Input.is_action_just_pressed("ui_cancel"):
		Net.leave()
		get_tree().change_scene_to_file("res://scenes/CarSelect.tscn")
		return
	if (_finished or _my_finished) and Input.is_action_just_pressed("ui_accept"):
		Net.leave()
		get_tree().change_scene_to_file("res://scenes/CarSelect.tscn")
		return
	if Net.is_client():
		# Watchdog снимков: соединение может числиться живым, а сервер
		# завис или канал умер — сам ENet заметит только через десятки
		# секунд, всё это время машины стояли бы статуями без объяснений.
		if _net_started and not _finished and not _net_lost and not _kicked \
				and Net.my_slot >= 0 and _last_state_time > 0.0 \
				and Time.get_ticks_msec() / 1000.0 - _last_state_time > 5.0:
			_on_net_lost()
		# В лобби пробел просит сервер начать, не дожидаясь второго игрока.
		if _lobby != null and _lobby.visible and not _net_lost \
				and not _kicked and Input.is_action_just_pressed("ui_accept"):
			_rx_start_request.rpc_id(1)
		# Своя машина клиент-авторитетна — и возврат на трассу (R и
		# автовозврат) для неё делаем мы, сервер её не двигает. Ждущему
		# следующего заезда возвращать нечего: он стоит на решётке за
		# экраном лобби, и автовозврат только дёргал бы машину по застреванию.
		if _car != null and _car.net_role == Car.NetRole.OWNED \
				and not _wait_next_race:
			if Input.is_action_just_pressed("respawn"):
				_respawn_car(_my_index())
			_check_recovery(delta)
		return
	if Input.is_action_just_pressed("respawn"):
		_respawn_car(0)
	_check_recovery(delta)


## Индекс МОЕЙ машины: оффлайн это всегда 0, по сети — выданный слот.
func _my_index() -> int:
	return Net.my_slot if Net.is_client() and Net.my_slot >= 0 else 0


## Место машины в гонке. Уже ФИНИШИРОВАВШИЕ держат свои места навсегда —
## по порядку пересечения линии, ровно как их раздаёт _car_finished. Без
## этого HUD и баннер финиша расходились: доехавшая машина останавливается,
## её прогресс замирает, едущий сзади обходит её ПО ПРОГРЕССУ, и HUD
## показывал «МЕСТО 2», когда первое место уже было занято, — а потом
## баннер выдавал честное «МЕСТО 3 ИЗ 4». Ровно на это игрок и жаловался.
func _place_of(idx: int) -> int:
	# КЛИЕНТ берёт место у сервера (протокол 13). Свой счёт по прогрессу он
	# вести не может честно: своя машина у него «сейчас», чужие — с
	# отставанием буфера, и в плотной борьбе оба игрока видели себя первыми.
	if Net.is_client() and idx >= 0 and idx < _net_place.size() \
			and _net_place[idx] > 0:
		return _net_place[idx]
	var done := _finish_order.find(idx)
	if done >= 0:
		return done + 1
	# Ещё едет: все финишировавшие впереди по определению, среди остальных
	# сравниваем накопленный путь.
	var place := _finish_order.size() + 1
	for j in _cars.size():
		if j == idx or _finish_order.has(j):
			continue
		if _progress[j] > _progress[idx]:
			place += 1
	return place


func _player_place() -> int:
	return _place_of(_my_index())


## Машина i пересекла финиш (сервер или оффлайн): останавливается, место
## фиксируется по порядку пересечения. Остальные продолжают доезжать.
func _car_finished(i: int) -> void:
	var car := _cars[i]
	car.race_over = true
	car.controls_enabled = false
	_finish_order.append(i)
	if _first_finish_time < 0.0:
		_first_finish_time = Time.get_ticks_msec() / 1000.0
	var place := _finish_order.size()
	if Net.is_server():
		_rx_car_finished.rpc(i, place)
	elif i == 0:
		_show_finish(place)
	# Все доехали — заезд окончен целиком.
	if _finish_order.size() >= _cars.size():
		_finish_race()


## Баннер «ФИНИШ! Место N». Место зафиксировано в момент пересечения —
## кто доехал позже, на него уже не влияет. Здесь же начисляется опыт:
## один раз (guard _my_finished), у себя — оффлайн и на клиенте
## (выделенный сервер HUD не строит и сюда не попадает).
func _show_finish(place: int) -> void:
	if _my_finished:
		return
	_my_finished = true
	if _count_label:
		_count_label.visible = false
	var gained: int = GameState.place_xp(place) + _my_kills * GameState.KILL_XP
	var before: Vector3i = GameState.level_info()
	GameState.add_xp(gained)
	var info: Vector3i = GameState.level_info()
	_finish_label.text = "ФИНИШ!  МЕСТО %d ИЗ %d" % [place, _cars.size()]
	if _finish_xp_label:
		_finish_xp_label.text = "+%d ОПЫТА   ·   УРОВЕНЬ %d  (%d / %d)" \
				% [gained, info.x, info.y, info.z]
	if info.x > before.x and _announcer:
		_announcer.big("НОВЫЙ УРОВЕНЬ %d!" % info.x, "", "teal")
	_finish_root.visible = true
	# Праздничный залп конфетти над машиной игрока (победителю — двойной).
	var me := _my_index()
	if me >= 0 and me < _cars.size():
		var car := _cars[me]
		FxKit.confetti_burst(self, car.global_position + Vector3.UP * 1.2)
		if place == 1:
			FxKit.confetti_burst(self,
					car.global_position + Vector3.UP * 2.5, 120)


## Полное окончание заезда: все доехали или вышел FINISH_TIMEOUT.
func _finish_race() -> void:
	if _finished:
		return
	_finished = true
	# Управление снято у всех, недоехавшие плавно тормозят
	# (см. ветку race_over в Car._physics_process).
	for c in _cars:
		c.controls_enabled = false
		c.race_over = true
	if Net.is_server():
		_rx_finish.rpc()
		_reset_server_after_race()
		return
	# Сам не доехал, а заезд кончился (таймаут) — место по прогрессу.
	if not _my_finished:
		_show_finish(_player_place())


## Возврат i-й машины на ось трассы (+6 м вперёд), скорость в ноль.
func _respawn_car(i: int) -> void:
	var _wd0 := Time.get_ticks_msec()
	var car := _cars[i]
	# От СВОЕЙ отметки (ведётся по непрерывности), а не от ближайшей точки
	# оси: улетевшая за ограждение машина бывает ближе к чужому витку
	# кольца, и тогда возврат «на трассу» выбрасывал её через пол-трассы
	# вперёд — на это и жаловались.
	car.global_transform = _track.respawn_transform_at(car.track_offset)
	car.reset_track_offset()
	_last_offset[i] = car.track_offset
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_speed_memory()
	_offtrack_time[i] = 0.0
	_flip_time[i] = 0.0
	_stall_time[i] = 0.0
	if _warn_panel and i == _my_index():
		_warn_panel.visible = false
	print("[respawn] машина %d, заняло %d мс (t=%.1f)"
			% [i, Time.get_ticks_msec() - _wd0,
			Time.get_ticks_msec() / 1000.0])


## Автовозврат на трассу по трём причинам: вылет за ограждение, переворот
## на крышу, длительное застревание. Игроку показываем, что происходит.
func _check_recovery(delta: float) -> void:
	for i in _cars.size():
		var car := _cars[i]
		# По сети машину живого игрока возвращает ЕЁ клиент (она у него
		# клиент-авторитетна): сервер марионетку не двигает, а клиент
		# правит только свою.
		if car.net_role == Car.NetRole.PUPPET \
				or (Net.is_client() and i != _my_index()):
			continue
		# Страховка от «улетел в никуда»: дикий импульс (или NaN в
		# трансформе) уносит машину, камера уезжает следом — «трасса
		# пропала». Возвращаем сразу, без таймера. NaN сперва обнуляем:
		# respawn_transform от нечисловой позиции сам бы вернул NaN.
		if not car.global_position.is_finite():
			car.global_position = Vector3.ZERO
			_respawn_car(i)
			continue
		if car.global_position.length() > 600.0:
			_respawn_car(i)
			continue
		if not car.alive:
			_offtrack_time[i] = 0.0
			_flip_time[i] = 0.0
			_stall_time[i] = 0.0
			continue

		var reason := ""
		var left := 0.0

		# И расстояние, и полуширина — от СВОЕЙ отметки (ведётся по
		# непрерывности): у машины, уехавшей далеко от полотна, ближайшей
		# точкой оси бывает чужой виток кольца — вылет тогда не замечался
		# вовсе, а замеченный лечился респавном на другом конце трассы.
		car.sync_track_offset()
		var dist := _track.distance_from_axis_at(
				car.global_position, car.track_offset)
		# ПРОВАЛ ПОД ПОЛОТНО: машина в границах дороги, но ЗАМЕТНО ниже её
		# уровня — жёсткий удар (переворот, депенетрация) продавил тонкий
		# тримеш, и машина ездила под асфальтом. Ни одна старая проверка
		# этого не ловила: вылет меряет расстояние В ПЛАНЕ (под дорогой
		# оно ~0), переворот и застревание под дорогой не обязательны.
		# Возвращаем сразу: под полотном легальной езды не бывает.
		var road_y := _track._curve.sample_baked(car.track_offset).y
		if dist < _track.half_width_at_offset(car.track_offset) \
				and car.global_position.y < road_y - 1.0:
			_respawn_car(i)
			continue
		# Запас — у трассы: классика 0.5 м (за ним ограждение), песчаная
		# 12 м (съезд на песок легален, возвращаем только уехавших в дюны).
		if dist > _track.half_width_at_offset(car.track_offset) \
				+ _track.offtrack_margin:
			_offtrack_time[i] += delta
			var wait := OFFTRACK_WAIT_PLAYER if i == _my_index() \
					else OFFTRACK_WAIT_AI
			reason = "Вне трассы!"
			left = wait - _offtrack_time[i]
			if _offtrack_time[i] >= wait:
				_respawn_car(i)
				continue
		else:
			# Затухание вместо сброса: машина, дребезжащая у самой границы
			# (кадр внутри порога — кадр снаружи), при жёстком сбросе никогда
			# не набирала таймер и каталась за ограждением бесконечно.
			_offtrack_time[i] = maxf(0.0, _offtrack_time[i] - delta * 2.0)

		# Переворот считаем, только когда машина уже легла на землю:
		# в полёте её может кувыркать, это не повод для возврата.
		if car.global_transform.basis.y.dot(Vector3.UP) < FLIP_DOT \
				and car.is_near_ground() \
				and absf(car.linear_velocity.y) < 2.5:
			_flip_time[i] += delta
			if reason == "":
				reason = "Перевернулся!"
				left = FLIP_WAIT - _flip_time[i]
			if _flip_time[i] >= FLIP_WAIT:
				_respawn_car(i)
				continue
		else:
			_flip_time[i] = 0.0

		# Застревание: гонка идёт, а машина почти стоит.
		# (До отсчёта «GO!» все стоят на решётке — это не застревание.)
		if car.controls_enabled and car.linear_velocity.length() < STALL_SPEED:
			_stall_time[i] += delta
			if reason == "":
				reason = "Застрял!"
				left = STALL_WAIT - _stall_time[i]
			if _stall_time[i] >= STALL_WAIT:
				_respawn_car(i)
				continue
		else:
			_stall_time[i] = 0.0

		# Плашку показываем только у СВОЕЙ машины; у сервера HUD нет вовсе.
		if _warn_panel and i == _my_index():
			if reason == "":
				_warn_panel.visible = false
			else:
				_warn_label.text = "%s Возврат через %d…" \
						% [reason, maxi(1, ceili(left))]
				_warn_panel.visible = true


## Вид трассы этого заезда. Оффлайн выбирает гараж (случайно, см.
## CarSelect._start_race); тесты, грузящие Main напрямую, ничего не
## выбирают и получают классику — регрессия детерминирована. По сети вид
## диктует СЕРВЕР: выбирает случайно на каждый заезд (сцена перезапускается
## между заездами) и шлёт клиентам _rx_track; ключ `--track=<вид>` в
## командной строке фиксирует выбор (нужно сетевым стендам — TestNet
## перезагрузку сцены не переживёт).
func _pick_track_kind() -> String:
	if Net.is_client():
		if TrackBuilder.KINDS.has(GameState.track_kind):
			return GameState.track_kind
		return TrackBuilder.KIND_GRASS
	if Net.is_server():
		for a: String in OS.get_cmdline_user_args():
			if a.begins_with("--track="):
				var forced := a.trim_prefix("--track=")
				if TrackBuilder.KINDS.has(forced):
					return forced
		return TrackBuilder.pick_random_kind()
	if TrackBuilder.KINDS.has(GameState.track_kind):
		return GameState.track_kind
	return TrackBuilder.KIND_GRASS


func _setup_environment() -> void:
	if Net.is_server():
		return   # см. _set_car_model: сервер без косметики
	# Ночной город (неон) — своё окружение: луна вместо солнца, тёмное
	# небо с городским заревом у горизонта и glow, от которого светятся
	# все эмиссивные материалы (трубки на стенах, окна зданий, вывески).
	# Космос — звёздная панорама вместо градиентного неба, тот же glow.
	var neon := _track_kind == TrackBuilder.KIND_NEON
	var space := _track_kind == TrackBuilder.KIND_SPACE
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	if neon:
		sun.light_energy = 0.25
		sun.light_color = Color(0.65, 0.75, 1.0)   # холодный лунный свет
	elif space:
		sun.light_energy = 0.4
		sun.light_color = Color(0.8, 0.85, 1.0)    # жёсткий свет далёкой звезды
	else:
		sun.light_energy = 1.2
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	if space:
		# Космос: панорама звёздного неба, печётся кодом (см. _space_sky).
		sky.sky_material = _space_sky()
	else:
		# Голубое градиентное небо (мультяшный день — под стать декору
		# трассы); ночью — чёрный верх и багровое зарево у горизонта.
		var sky_mat := ProceduralSkyMaterial.new()
		if neon:
			sky_mat.sky_top_color = Color(0.01, 0.02, 0.06)
			sky_mat.sky_horizon_color = Color(0.17, 0.07, 0.22)
			sky_mat.ground_horizon_color = Color(0.17, 0.07, 0.22)
			sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.04)
		else:
			sky_mat.sky_top_color = Color(0.3, 0.55, 0.87)
			sky_mat.sky_horizon_color = Color(0.74, 0.85, 0.95)
			sky_mat.ground_horizon_color = Color(0.74, 0.85, 0.95)
			# Низ скайбокса — в тон земли: трава или песок пустыни.
			sky_mat.ground_bottom_color = Color(0.52, 0.44, 0.28) \
					if _track_kind == TrackBuilder.KIND_SAND \
					else Color(0.28, 0.4, 0.24)
		sky_mat.sun_angle_max = 15.0
		sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	if neon or space:
		# Приподнятый ambient: темнота читается, но машины не тонут в
		# черноте (аркада важнее реализма). Glow зажигает всё эмиссивное:
		# трубки на стенах, вывески, планеты, звёзды.
		e.ambient_light_color = Color(0.38, 0.42, 0.62) if neon \
				else Color(0.42, 0.44, 0.6)
		e.ambient_light_energy = 0.55
		e.glow_enabled = true
		e.glow_intensity = 0.7
		e.glow_bloom = 0.05
		e.glow_hdr_threshold = 1.0
	else:
		e.ambient_light_color = Color(0.65, 0.67, 0.72)
		e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)


## Звёздная панорама космической трассы: тёмный сине-фиолетовый градиент,
## полоса «млечного пути» по диагонали, туманности и ~900 звёзд. Печётся
## один раз при старте заезда, зерно фиксировано.
func _space_sky() -> PanoramaSkyMaterial:
	const W := 1024
	const H := 512
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260901
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	for py in H:
		# Вертикальный градиент: у зенита чернее, к «низу» чуть синее.
		var t := float(py) / H
		var base := Color(0.008 + 0.02 * t, 0.008 + 0.02 * t, 0.03 + 0.05 * t)
		for px in W:
			img.set_pixel(px, py, base)
	# Млечный путь: широкая полоса звёздной пыли волной через всю панораму.
	for px in W:
		var mid := H * 0.5 + sin(float(px) / W * TAU + 1.3) * H * 0.14
		var half_w := H * 0.09
		for py in range(maxi(0, int(mid - half_w)), mini(H, int(mid + half_w))):
			var k := 1.0 - absf(py - mid) / half_w
			k = k * k * 0.10
			var c := img.get_pixel(px, py)
			img.set_pixel(px, py,
					Color(c.r + k * 0.9, c.g + k * 0.85, c.b + k))
	# Туманности: несколько мягких цветных пятен.
	for _n in 6:
		var cx := rng.randf_range(0, W)
		var cy := rng.randf_range(H * 0.2, H * 0.8)
		var r := rng.randf_range(30.0, 70.0)
		var tint := Color(0.12, 0.04, 0.18) if rng.randf() < 0.5 \
				else Color(0.04, 0.09, 0.18)
		for py in range(maxi(0, int(cy - r)), mini(H, int(cy + r))):
			for px in range(int(cx - r), int(cx + r)):
				var d := Vector2(px - cx, py - cy).length() / r
				if d >= 1.0:
					continue
				var k := (1.0 - d) * (1.0 - d)
				var wrapped := posmod(px, W)
				var c := img.get_pixel(wrapped, py)
				img.set_pixel(wrapped, py, Color(
						c.r + tint.r * k, c.g + tint.g * k, c.b + tint.b * k))
	# Звёзды.
	for _i in 900:
		var x := rng.randi_range(1, W - 2)
		var y := rng.randi_range(1, H - 2)
		var b := rng.randf_range(0.4, 1.0)
		var c := Color(b, b, b)
		var roll := rng.randf()
		if roll < 0.2:
			c = Color(b * 0.7, b * 0.85, b)
		elif roll < 0.35:
			c = Color(b, b * 0.9, b * 0.65)
		img.set_pixel(x, y, c)
		if rng.randf() < 0.1:
			var half := c * 0.5
			img.set_pixel(x + 1, y, half)
			img.set_pixel(x - 1, y, half)
			img.set_pixel(x, y + 1, half)
			img.set_pixel(x, y - 1, half)
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = ImageTexture.create_from_image(img)
	return mat


## Запасной визуал: корпус + кабина из BoxMesh.
func _build_placeholder_visual(car: Car) -> void:
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.7, 0.6, 3.0)
	body.mesh = body_mesh
	body.position.y = 0.3
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.15, 0.45, 0.9)
	body.material_override = body_mat
	car.add_child(body)

	var cabin := MeshInstance3D.new()
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(1.3, 0.45, 1.3)
	cabin.mesh = cabin_mesh
	cabin.position = Vector3(0, 0.8, 0.2)
	var cabin_mat := StandardMaterial3D.new()
	cabin_mat.albedo_color = Color(0.1, 0.1, 0.14)
	cabin.material_override = cabin_mat
	car.add_child(cabin)

	# «Нос» — визуальный маркер направления вперёд (-Z).
	var nose := MeshInstance3D.new()
	var nose_mesh := BoxMesh.new()
	nose_mesh.size = Vector3(0.6, 0.25, 0.5)
	nose.mesh = nose_mesh
	nose.position = Vector3(0, 0.45, -1.5)
	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = Color(0.95, 0.8, 0.1)
	nose.material_override = nose_mat
	car.add_child(nose)


## Надпись Russo One (индустриальный гротеск, есть кириллица) с
## чернильной обводкой — базовая типографика «гаражного» стиля.
func _make_label(parent: Node, txt: String, font_size: int,
		color := Color.WHITE, outline := 0) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", font_size)
	if _ui_font:
		l.add_theme_font_override("font", _ui_font)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", UiKit.INK)
	parent.add_child(l)
	return l


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_ui_font = UiKit.font()
	_slot_empty_tex = load("res://assets/ui/garage/slot_empty.png")

	# Скорость: белая эмалевая табличка, чернильные цифры, аварийная
	# полоска по нижней кромке (как SPEED-табличка референса).
	var speed_panel := UiKit.plate(canvas, "white", Vector2(16, 12),
			Vector2(190, 70))
	_speed_label = _make_label(speed_panel, "0", 40, UiKit.INK)
	_speed_label.position = Vector2(14, 4)
	_speed_label.size = Vector2(106, 54)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var kmh := _make_label(speed_panel, "КМ/Ч", 14,
			Color(UiKit.INK.r, UiKit.INK.g, UiKit.INK.b, 0.7))
	kmh.position = Vector2(130, 30)
	UiKit.hazard(speed_panel, Vector2(10, 57), Vector2(170, 7), 0.95)

	# Круг — жёлтая эмаль, место — оранжевая (как Lap / 1st референса).
	var lap_panel := UiKit.plate(canvas, "yellow", Vector2(16, 90),
			Vector2(190, 44))
	_lap_label = _make_label(lap_panel, "КРУГ 1/%d" % LAPS, 20, UiKit.INK)
	_lap_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lap_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var pos_panel := UiKit.plate(canvas, "orange", Vector2(16, 142),
			Vector2(190, 44))
	_pos_label = _make_label(pos_panel, "МЕСТО 1/4", 20, Color.WHITE, 5)
	_pos_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pos_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Мини-карта в правом верхнем углу: стальная табличка, внутри контур
	# трассы. Панель привязана к ПРАВОМУ краю (anchor 1.0), чтобы не
	# уезжать при другом разрешении окна.
	var map_panel := UiKit.plate(canvas, "steel", Vector2.ZERO,
			Vector2(228, 158))
	map_panel.anchor_left = 1.0
	map_panel.anchor_right = 1.0
	map_panel.offset_left = -244
	map_panel.offset_right = -16
	map_panel.offset_top = 12
	map_panel.offset_bottom = 170
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_minimap.offset_left = 8
	_minimap.offset_right = -8
	_minimap.offset_top = 8
	_minimap.offset_bottom = -8
	map_panel.add_child(_minimap)
	_minimap.setup(_track, _cars)
	_minimap.my_index = _my_index()

	# Слот оружия: пустой — стальной гекс EMPTY (нарезан из референса),
	# с оружием — его восьмиугольный значок на всю величину слота.
	_weapon_icon = TextureRect.new()
	# expand_mode СТРОГО до size: при дефолтном KEEP_SIZE присвоение size
	# клампится к размеру текстуры и слот выходит гигантским.
	_weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weapon_icon.position = Vector2(24, 196)
	_weapon_icon.size = Vector2(96, 96)
	_weapon_icon.texture = _slot_empty_tex
	canvas.add_child(_weapon_icon)
	_weapon_name = _make_label(canvas, "", 14, UiKit.YELLOW, 4)
	_weapon_name.position = Vector2(0, 294)
	_weapon_name.size = Vector2(144, 22)
	_weapon_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Предупреждение (вылет/переворот/застрял) — красная табличка сверху.
	_warn_panel = UiKit.plate(canvas, "red", Vector2.ZERO, Vector2(440, 56))
	_warn_panel.anchor_left = 0.5
	_warn_panel.anchor_right = 0.5
	_warn_panel.offset_left = -220
	_warn_panel.offset_right = 220
	_warn_panel.offset_top = 84
	_warn_panel.offset_bottom = 140
	_warn_panel.visible = false
	# ВАЖНО: set_anchors_and_offsets_preset, не set_anchors_preset —
	# последний подгоняет offsets под ТЕКУЩИЙ размер контрола (лейбл
	# остаётся крошечным у левого верха), а нужен реальный full rect.
	_warn_label = _make_label(_warn_panel, "", 22, Color.WHITE, 6)
	_warn_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Отсчёт 3-2-1-GO: огромные цифры с «выпрыгиванием» (см. _pop_count).
	_count_label = _make_label(canvas, "", 130, UiKit.YELLOW, 18)
	_count_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.visible = false

	# Финиш: стальная плита с шахматными лентами сверху и снизу.
	_finish_root = Control.new()
	_finish_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_finish_root.visible = false
	canvas.add_child(_finish_root)
	var fin_plate := UiKit.plate(_finish_root, "steel", Vector2.ZERO,
			Vector2(640, 190), false)
	fin_plate.anchor_left = 0.5
	fin_plate.anchor_right = 0.5
	fin_plate.anchor_top = 0.5
	fin_plate.anchor_bottom = 0.5
	fin_plate.offset_left = -320
	fin_plate.offset_right = 320
	fin_plate.offset_top = -130
	fin_plate.offset_bottom = 60
	UiKit.checker(fin_plate, Vector2(20, 14), Vector2(600, 24))
	UiKit.checker(fin_plate, Vector2(20, 152), Vector2(600, 24))
	_finish_label = _make_label(fin_plate, "", 34, Color.WHITE, 8)
	_finish_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_finish_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_finish_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_finish_label.offset_bottom = -40.0   # чуть выше: снизу строка опыта
	_finish_xp_label = _make_label(fin_plate, "", 20, UiKit.YELLOW, 6)
	_finish_xp_label.anchor_left = 0.0
	_finish_xp_label.anchor_right = 1.0
	_finish_xp_label.offset_top = 112.0
	_finish_xp_label.offset_bottom = 146.0
	_finish_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var finish_hint := _make_label(fin_plate, "ENTER — В ГАРАЖ", 16,
			Color(1, 1, 1, 0.8), 5)
	finish_hint.anchor_left = 0.0
	finish_hint.anchor_right = 1.0
	finish_hint.anchor_top = 1.0
	finish_hint.anchor_bottom = 1.0
	finish_hint.offset_top = 12
	finish_hint.offset_bottom = 40
	finish_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var help := Label.new()
	help.text = "WASD — движение | Space — ручник | Shift — прыжок | " \
			+ "E — оружие | R — на трассу | Esc — меню"
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.position = Vector2(20, -30)
	help.add_theme_font_size_override("font_size", 13)
	if _ui_font:
		help.add_theme_font_override("font", _ui_font)
	help.modulate = Color(1, 1, 1, 0.65)
	canvas.add_child(help)

	# Всплывающие анонсы (двойные убийства, последний круг…) — поверх
	# всего HUD, но ПОД сетевым лобби.
	_announcer = Announcer.new()
	_announcer.name = "Announcer"
	canvas.add_child(_announcer)

	# Лента событий оружия («кто кого чем») — правый край, под мини-картой.
	_feed_box = VBoxContainer.new()
	_feed_box.anchor_left = 1.0
	_feed_box.anchor_right = 1.0
	_feed_box.offset_left = -336
	_feed_box.offset_right = -16
	_feed_box.offset_top = 182
	_feed_box.offset_bottom = 460
	_feed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed_box.add_theme_constant_override("separation", 6)
	_feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_feed_box)

	# Сетевое лобби — полноэкранный Control ПОВЕРХ всего HUD (добавлен
	# последним, поэтому рисуется сверху). Отдельной сценой лобби быть не
	# может: RPC адресуются по пути узла, клиент обязан сидеть в /root/Main
	# с самого рукопожатия (грабли №1 сетевой части).
	if Net.is_client():
		_lobby = Lobby.new()
		_lobby.name = "Lobby"
		canvas.add_child(_lobby)


# ════════════════════ СЕТЕВАЯ ЧАСТЬ ════════════════════
# Модель — выделенный сервер, но машины живых игроков КЛИЕНТ-АВТОРИТЕТНЫ:
# каждую считает её собственный клиент и шлёт серверу состояние
# (_rx_pstate), сервер ведёт её марионеткой и ретранслирует второму
# игроку. Ботов и всё оружие считает сервер. Прежняя схема («сервер
# считает всех, клиентскую копию мягко подтягивает») на реальном канале
# дёргала машину: серверное состояние отстаёт на пинг, подтяжка тянула
# назад каждый снимок, а невязка больше 5 м давала телепорт.
# Эффекты оружия по машине игрока сервер пересылает владельцу (_rx_fx) —
# физику толчка/разворота/телепорта применяет клиент.


## Сервер: подключился игрок — слот ему уже выдал Net, здесь переводим
## машину этого слота с бота на марионетку: физику считает клиент игрока
## и присылает состояние (_rx_pstate).
func _on_peer_joined(_id: int, slot: int) -> void:
	if slot < 0 or slot >= _cars.size():
		return
	var car := _cars[slot]
	# ЗАЕЗД НАЧАЛСЯ — вход закрыт (31.08). Кто не успел к лобби, машину в
	# чужой гонке НЕ получает: её и дальше ведёт бот, а игроку поднимают
	# ОТДЕЛЬНЫЙ заезд-комнату (см. _route_elsewhere). Прежние 25 секунд
	# «подсадки вместо бота» отменены: за них бот уезжал на сотни метров,
	# и подсевший появлялся далеко впереди уже играющих — они друг друга
	# даже не видели. Полумеры («сажать в хвост») тоже не годятся: гонка,
	# в которой ты начал с чужого места и с чужим кругом, — не твоя гонка.
	var late: bool = _net_started
	if late:
		_late_slots[slot] = true
	else:
		_late_slots.erase(slot)
		car.net_make_puppet()
	_join_time[slot] = Time.get_ticks_msec() / 1000.0
	# О занятии слота сообщаем СРАЗУ, до всех ветвлений. Раньше это стояло в
	# конце, и когда второй игрок запускал заезд своим подключением, функция
	# выходила раньше отправки: у первого игрока метка живого соперника так и
	# не загоралась. Поймано двухклиентским прогоном теста.
	_rx_slot_taken.rpc(slot, true)
	if _net_started:
		_rx_lobby.rpc(Net.slot_of_peer.size(), 0)
		return
	# Гонка ещё не началась — этот слот точно не «опоздавший».
	_late_slots.erase(slot)
	# Зашёл человек, пока лобби показывало ботов, — отменяем эту попытку
	# старта: слот отдаём ему, а не боту (см. _start_with_bots).
	if _starting:
		_starting = false
		_start_gen += 1
		_rx_bots.rpc(0)
	# Стартовать ЗДЕСЬ нельзя, даже если все слоты заняты: подключение —
	# это ENet-рукопожатие, а сцена у игрока может ещё грузиться (первый
	# вход = компиляция шейдеров). Старт — только когда все загрузились
	# (прислали hello), см. _maybe_start.
	# Первый игрок: даём LOBBY_WAIT секунд на то, чтобы подтянулись остальные.
	if _lobby_wait < 0.0:
		_lobby_wait = LOBBY_WAIT
	# Пришёл ещё один — продлеваем ожидание до JOIN_GRACE, если оставалось
	# меньше. Друзья жмут «играть» не по секундомеру: один заходит на
	# двадцатой секунде чужого ожидания, и без продления заезд стартовал бы
	# у него под носом, а он подсел бы к идущей гонке.
	_lobby_wait = maxf(_lobby_wait, JOIN_GRACE)
	_rx_lobby.rpc(Net.slot_of_peer.size(), ceili(_lobby_wait))


## Сервер: игрок ушёл — его машину снова ведёт бот, гонка продолжается.
func _on_peer_left(_id: int, slot: int) -> void:
	if slot < 0 or slot >= _cars.size():
		return
	# Машину бросил живой игрок — возвращаем её боту. Иначе она зависла бы
	# марионеткой на последнем присланном состоянии навсегда.
	var car := _cars[slot]
	car.net_make_local()
	_hello_done.erase(slot)
	_join_time.erase(slot)
	_late_slots.erase(slot)
	# До старта слот снова ждёт человека — боту свежий ник (имя ушедшего не
	# зомбируем: он может тут же перезайти). ВО ВРЕМЯ заезда имя не трогаем:
	# бот доигрывает под именем ушедшего, и для остальных этот «игрок»
	# просто продолжает ехать — боты неотличимы от людей (01.09).
	if not _net_started and slot < _names.size():
		_names[slot] = PlayerNames.pick_one(_names)
		_rx_names.rpc(_names)
	_rx_lobby.rpc(Net.slot_of_peer.size(), maxi(ceili(_lobby_wait), 0))
	_rx_slot_taken.rpc(slot, false)
	# Ушли все — заезд некому доигрывать. Перезапускаем трассу, чтобы
	# следующая пара получила чистую гонку, а не догоняла ботов.
	if Net.slot_of_peer.is_empty() and _net_started:
		print("[net] игроков не осталось, перезапуск трассы")
		get_tree().reload_current_scene()
		return
	# Ушёл последний, а гонка ещё не начиналась: ожидание лобби ОБНУЛЯЕМ.
	# Иначе оно дотикивало в пустоту и сервер начинал заезд, в котором нет
	# ни одного человека (в логе VDS — «старт заезда, игроков: 0»); зашедший
	# следом игрок подсаживался к этой ничьей гонке вместо своей новой.
	if Net.slot_of_peer.is_empty():
		_lobby_wait = -1.0
		_want_start = false
		_loading_told = false
		# Ушёл ВО ВРЕМЯ показа ботов (BOTS_SHOW) — отменяем и эту попытку
		# старта, как _on_peer_joined отменяет её при входе. Без этого await
		# в _start_with_bots дотикивал и заезд стартовал ПУСТЫМ (VDS 27.08
		# 13:52:30: «старт заезда, игроков: 0» — и зашедший через полминуты
		# игрок был выслан «опоздавшим» в комнату вместо своей новой гонки).
		if _starting:
			_starting = false
			_start_gen += 1
		return
	# Может, ждали загрузку именно ушедшего — тогда старт освободился.
	_maybe_start()


## Связь с сервером пропала посреди заезда (сервер умер, канал упал) —
## классика сетевых игр: без обработки клиент навсегда оставался бы с
## замершими марионетками. Говорим прямо и возвращаемся в гараж.
## После финиша не дёргаемся: результат уже на экране, Enter — в гараж.
func _on_net_lost() -> void:
	if _net_lost or _kicked or _finished or _my_finished \
			or not is_inside_tree():
		return
	_net_lost = true
	print("[net] связь с сервером потеряна — возвращаемся в гараж")
	if _car != null:
		_car.controls_enabled = false
	if _lobby:
		_lobby.set_status("Связь с сервером потеряна.
Возвращаемся в гараж…")
		_lobby.show_screen()
	await get_tree().create_timer(3.0).timeout
	if is_inside_tree():
		Net.leave()
		get_tree().change_scene_to_file("res://scenes/CarSelect.tscn")


## После заезда сервер перезапускает сцену: следующие игроки должны
## получить чистую гонку, а не доехавшие машины на финишной прямой.
## Клиентам командуем перезапуститься ТОЖЕ (_rx_reset): раньше их сцена
## оставалась старой, и когда сервер начинал новый заезд, приехавший отсчёт
## включал управление финишировавшему игроку — он ехал дальше прямо с
## баннером «ФИНИШ» на экране.
func _reset_server_after_race() -> void:
	await get_tree().create_timer(8.0).timeout
	if is_inside_tree():
		print("[net] заезд окончен, перезапуск трассы")
		_rx_reset.rpc()
		get_tree().reload_current_scene()


## Представиться серверу и ЖДАТЬ ОТВЕТА, повторяя запрос.
## Один выстрел ненадёжен: сервер перезапускает сцену после каждого заезда
## (8 секунд), и hello, посланный в этот момент, адресуется узлу /root/Main,
## которого прямо сейчас нет — RPC молча пропадает, а клиент навсегда
## остаётся с чужими машинами-марионетками и без своей. Ровно так и вышло
## при проверке: подключился сразу после чужого финиша — и завис.
func _say_hello() -> void:
	for attempt in 12:
		# −1 «ещё не выдан» — повторяем; −2 «сервер отказал» — уже нет.
		if Net.my_slot != -1 or not Net.is_client():
			return
		_rx_hello.rpc_id(1, GameState.selected_car_id, Net.PROTOCOL,
				GameState.race_size, GameState.display_name())
		await get_tree().create_timer(1.0).timeout
		if not is_inside_tree():
			return
	if Net.my_slot < 0 and _lobby:
		_lobby.set_status("Сервер не выдал слот.
Возможно, версии игры различаются — обнови игру (git pull).
Esc — в гараж")
		_lobby.show_screen()


## Загрузились ли ВСЕ подключённые игроки (прислали hello). Подключённый,
## но молчащий дольше HELLO_GRACE (старый клиент, зависшая загрузка),
## перестаёт блокировать старт — иначе он держал бы всех вечно.
func _all_loaded() -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	for slot: int in Net.slot_of_peer.values():
		if _hello_done.has(slot):
			continue
		if now - float(_join_time.get(slot, now)) < HELLO_GRACE:
			return false
	return true


## Единственная точка решения о старте: старт запрошен (все слоты заняты,
## Пробел или таймаут лобби) И все подключённые загрузились — поехали.
## Так вход из лобби в гонку синхронный: никто не стартует, пока у
## кого-то ещё крутится загрузка.
func _maybe_start() -> void:
	if not Net.is_server() or _net_started or _starting:
		return
	# Заезд без единого человека не нужен НИКОМУ: он жжёт процессор VDS и,
	# главное, зашедший игрок попадал не в свою новую гонку, а в чужую,
	# идущую уже вторую минуту. Пустой сервер просто ждёт первого игрока.
	if Net.slot_of_peer.is_empty():
		_want_start = false
		_lobby_wait = -1.0
		return
	var full := Net.slot_of_peer.size() >= Net.race_size
	if not (_want_start or full):
		return
	if _all_loaded():
		_lobby_wait = -1.0
		_start_with_bots()
	elif not _loading_told:
		# Ждём загрузку: скажем игрокам, чего именно ждём (secs = −1).
		# Один раз, не каждый тик — _tick_lobby зовёт нас каждый кадр.
		_loading_told = true
		_rx_lobby.rpc(Net.slot_of_peer.size(), -1)


func _start_net_race() -> void:
	if _net_started:
		return
	# Последний рубеж от пустого заезда: к этой точке ведут и таймер лобби,
	# и хвост await в _start_with_bots — где бы ни прозевали уход последнего
	# игрока, без людей не стартуем (см. _on_peer_left).
	if Net.slot_of_peer.is_empty():
		_want_start = false
		print("[net] старт отменён: игроков не осталось")
		return
	_net_started = true
	print("[net] старт заезда, игроков: %d" % Net.slot_of_peer.size())
	_countdown()


## Живых игроков хватило не на все слоты — свободные берут боты. Прежде
## чем начинать отсчёт, показываем это в лобби: слот перестаёт быть «ждём
## игрока…» и становится ботом с его машиной. Пауза BOTS_SHOW — чтобы
## игрок успел разглядеть, с кем едет (отсчёт лобби уже прячет).
func _start_with_bots() -> void:
	if _net_started or _starting:
		return
	var bot_mask := ~_taken_mask() & ((1 << Net.race_size) - 1)
	if bot_mask == 0:
		_start_net_race()
		return
	_starting = true
	_start_gen += 1
	var gen := _start_gen
	print("[net] свободные слоты заняли боты (маска %d)" % bot_mask)
	_rx_bots.rpc(bot_mask)
	await get_tree().create_timer(BOTS_SHOW).timeout
	# Успел зайти живой игрок — попытка отменена (см. _on_peer_joined):
	# человек лучше бота, ждём его загрузку и стартуем заново.
	if not is_inside_tree() or gen != _start_gen:
		return
	_starting = false
	_start_net_race()


## Сервер: раз в 1/SNAP_HZ рассылаем состояние всех машин.
func _server_tick(delta: float) -> void:
	_tick_lobby(delta)
	# Визитка в реестре заездов (Rooms): раз в секунду сообщаем, сколько
	# у нас игроков и есть ли место новому, — по ней ворота и комнаты
	# перенаправляют лишних игроков (_route_elsewhere).
	_card_accum += delta
	if _card_accum >= 1.0:
		_card_accum = 0.0
		Rooms.write_card(Net.port, Net.slot_of_peer.size(), _joinable_here())
		# Заодно хороним завершившиеся процессы комнат (у комнат список пуст).
		Rooms.reap_children()
	# Пустая комната без гонки живёт не вечно: погасла — память свободна.
	if Net.is_room:
		if Net.slot_of_peer.is_empty() and not _net_started:
			_room_idle += delta
			if _room_idle > ROOM_IDLE_EXIT:
				print("[rooms] комната на порту %d пуста %d с — гасимся"
						% [Net.port, int(ROOM_IDLE_EXIT)])
				Rooms.remove_card(Net.port)
				get_tree().quit()
				return
		else:
			_room_idle = 0.0
	_snap_accum += delta
	if _snap_accum < 1.0 / SNAP_HZ:
		return
	_snap_accum = 0.0
	var packed := _pack_state()
	_rx_state.rpc(packed[0], packed[1])


## Ожидание остальных игроков. Истекло — стартуем «по старинке»: свободные
## слоты так и остаются за ботами (см. _spawn_cars), и заезд ничем не хуже
## одиночного. Подсевший позже игрок просто заберёт машину у бота.
func _tick_lobby(delta: float) -> void:
	if _net_started or _starting:
		return
	# Старт уже запрошен, но кто-то ещё грузится — проверяем каждый тик:
	# hello может прийти в любой момент, а молчуна отпустит HELLO_GRACE.
	if _want_start:
		_maybe_start()
		return
	if _lobby_wait < 0.0:
		return
	var before := ceili(_lobby_wait)
	_lobby_wait -= delta
	if _lobby_wait <= 0.0:
		_lobby_wait = -1.0
		print("[net] остальных не дождались — запрашиваем старт")
		_want_start = true
		_maybe_start()
	elif ceili(_lobby_wait) != before:
		_rx_lobby.rpc(Net.slot_of_peer.size(), ceili(_lobby_wait))


## Клиент: каждый кадр физики шлёт серверу СОСТОЯНИЕ своей машины — она
## клиент-авторитетна, физика (и прыжок, и руль) целиком локальная, сеть
## её не трогает вовсе. Состояние идёт НЕнадёжным пакетом (потерянный кадр
## перекроет следующий), выстрел — надёжным: его не восстановить.
func _client_tick(_delta: float) -> void:
	if Net.my_slot < 0 or _car == null \
			or _car.net_role != Car.NetRole.OWNED:
		return
	var p := _car.global_position
	var q := _car.global_transform.basis.get_rotation_quaternion()
	var v := _car.linear_velocity
	# Испорченное состояние (NaN после дикого удара) не шлём вовсе —
	# страховка в _check_recovery вернёт машину, а сервер не отравится.
	if not (p.is_finite() and v.is_finite()):
		return
	# 11-е число — наш тик физики: по этим меткам буферы других клиентов
	# восстанавливают РОВНУЮ шкалу нашей машины (см. net_apply_snapshot;
	# протокол 9). 12-е — остаток заморозки (протокол 12): дебаф заразен
	# при касании, и подхватываем мы его ЗДЕСЬ, у себя (машина
	# клиент-авторитетна). Не доложишь — сервер о нашей «синеве» не узнает,
	# и дальше по цепочке она не пойдёт.
	# 13-е — НАШЕ ОТСТАВАНИЕ КАРТИНКИ (протокол 13): по нему сервер
	# отматывает цели, когда мы стреляем, — мы целились в то, что видели.
	# Раньше лазер отматывал на глазок 0.4 c, а снаряды не отматывались
	# вовсе и «пролетали сквозь». Буфер теперь адаптивный (60-350 мс), так
	# что догадка не годится — шлём измеренное.
	_rx_pstate.rpc_id(1, PackedFloat32Array([
			p.x, p.y, p.z, q.x, q.y, q.z, q.w, v.x, v.y, v.z,
			float(Engine.get_physics_frames()), _car.freeze_left(),
			Car.net_buf_delay]))
	if not _car.controls_enabled:
		return
	if Input.is_action_just_pressed("fire") \
			or Input.is_action_just_pressed("drop"):
		_rx_press.rpc_id(1)
		# Лазер — мгновенное оружие: рисуем СВОЙ луч сразу, не дожидаясь,
		# пока просьба слетает на сервер и картинка вернётся (полный пинг:
		# «нажал E, а лазер увидел позже»). Урон по-прежнему решает сервер
		# (с отмоткой целей — см. Car._use_laser); эхо своего выстрела
		# гасится в _rx_weapon_fx.
		if _car.weapon == Weapons.LASER and _car.alive:
			var fwd := -_car.global_transform.basis.z
			fwd.y = 0.0
			if fwd.length_squared() > 1e-6:
				LaserFx.spawn(self,
						_car.global_position + Vector3.UP * 0.5,
						fwd.normalized(), 70.0, _car)
				_laser_predicted = Time.get_ticks_msec() / 1000.0


## Снимок: на машину 11 float (позиция, кватернион, скорость, метка тика
## автора состояния — см. net_apply_snapshot) и 4 байта
## (оружие+1, живость с «призраком», значок эффекта+2, остаток заморозки
## в десятых секунды). Кватернион, а не базис: 4 числа вместо 9 и
## корректная интерполяция поворота.
func _pack_state() -> Array:
	var xf := PackedFloat32Array()
	var flags := PackedByteArray()
	for ci in _cars.size():
		var c: Car = _cars[ci]
		var q := c.global_transform.basis.get_rotation_quaternion()
		var p := c.global_position
		var v := c.linear_velocity
		# Машину живого игрока ретранслируем КАК ПРИСЛАЛ владелец (сырое
		# состояние) ВМЕСТЕ С ЕГО МЕТКОЙ ТИКА: по меткам буферы клиентов
		# строят ровную шкалу его машины. Без меток пробовано и то и другое:
		# тело серверной марионетки — двойное сглаживание (рывки), сырой
		# пакет — биение часов владельца и сервера (состояния в ретрансляции
		# то пропускаются, то дублируются), соперник-игрок дёргался даже на
		# локалхосте: 13.5%% против 3.5-6%% у ботов. Скорость — тоже из
		# пакета: у замороженной кинематики linear_velocity врёт.
		# Боту метка — тик самого сервера: его состояния и рождаются по
		# одному на тик.
		var stamp := float(Engine.get_physics_frames())
		if c.net_role == Car.NetRole.PUPPET and c._snap_seen:
			p = c._snap_pos
			q = c._snap_rot
			v = c._snap_vel
			stamp = maxf(c._snap_stamp, 0.0)
		xf.append_array(PackedFloat32Array([
				p.x, p.y, p.z, q.x, q.y, q.z, q.w, v.x, v.y, v.z, stamp]))
		flags.append(c.weapon + 1)
		flags.append((1 if c.alive else 0) | (2 if c.is_ghost() else 0))
		# ДЕЙСТВУЮЩИЙ эффект, а не _status_shown: тот обновляется лишь при
		# живом Sprite3D, которого на выделенном сервере нет, — значок по
		# сети не видел никто (кодировка та же: <2 — «пусто», протокол цел).
		flags.append(c.status_icon_kind() + 2)
		# Заморозка (протокол 12). Без неё соперник синел и заражал только
		# на СВОЁМ экране: у марионетки _freeze_time не тикал ниоткуда, и
		# «друг подъехал вплотную к замороженному и не заморозился».
		# Десятые секунды, потолок 25.5 c — дебаф живёт 3 c.
		flags.append(clampi(roundi(c.freeze_left() * 10.0), 0, 255))
		# МЕСТО В ГОНКЕ (протокол 13). Клиент считать его сам НЕ МОЖЕТ без
		# вранья: свою машину он видит «сейчас», а чужие — с отставанием
		# буфера, и на равной борьбе КАЖДЫЙ видит себя впереди (жалоба
		# 28.08: «я еду первым, а на его экране — вторым»). У сервера все
		# положения одного времени, поэтому места раздаёт он.
		flags.append(clampi(_place_of(ci), 0, 255))
	return [xf, flags]


# ── клиент → сервер ──

@rpc("any_peer", "call_remote", "reliable")
func _rx_hello(car_id: String, proto: int, want_size := 4,
		pname := "") -> void:
	if not Net.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	# Проверка версии протокола — первым делом. Несовпадающие версии НЕ
	# играют: RPC с другой сигнатурой молча отбрасываются, и рассинхрон
	# выглядел бы как куча загадочных багов. Клиент со СТАРЫМ hello (один
	# аргумент) сюда даже не попадёт — его вызов отбросит сам Godot, и
	# после 12 попыток он увидит подсказку про версии в _say_hello.
	if proto != Net.PROTOCOL:
		print("[net] пир %d: протокол %d, наш %d — отказ" % [id, proto, Net.PROTOCOL])
		_rx_kick.rpc_id(id, "Версии игры не совпадают
(у сервера %d, у тебя %d). Обнови игру: git pull." % [Net.PROTOCOL, proto])
		# Рвём соединение с задержкой, чтобы сообщение успело дойти.
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if multiplayer.multiplayer_peer != null \
					and Net.slot_of_peer.has(id):
				multiplayer.multiplayer_peer.disconnect_peer(id))
		return
	var slot: int = Net.slot_of_peer.get(id, -1)
	# РАЗМЕР ЗАЕЗДА (4..8) задаёт ПЕРВЫЙ игрок пустого лобби: он один, гонка
	# не идёт — принимаем его желание и перестраиваем сцену под новое число
	# машин (сцена сервера уже построена под старое). Соединение и слот
	# живут в autoload Net и перезагрузку переживают; hello клиента
	# повторяется раз в секунду (_say_hello) и застанет новую сцену.
	# Остальным размер диктуется в _rx_track ниже — как вид трассы.
	if slot >= 0 and not _net_started and Net.slot_of_peer.size() == 1:
		var want := clampi(want_size, GameState.RACE_SIZE_MIN,
				GameState.RACE_SIZE_MAX)
		if want != Net.race_size:
			print("[net] первый игрок выбрал заезд на %d машин — перестраиваемся"
					% want)
			Net.race_size = want
			get_tree().reload_current_scene()
			return
	# Игроку ЗДЕСЬ ехать негде: слота нет (гость) или он опоздал к идущему
	# заезду. Раньше гость получал отказ, а опоздавший ждал конца чужой
	# гонки — теперь обоих отправляем в параллельный заезд-комнату
	# (Rooms.gd). Не вышло и слота нет — отказ; слот есть — старое
	# «жди следующего» ниже по функции остаётся запасным путём.
	if slot < 0 or (_net_started and _late_slots.has(slot)):
		if _route_elsewhere(id, slot):
			return
	if slot < 0 or slot >= _roster.size():
		return
	# Игрок приехал на своей машине — ставим её в его слот и раздаём
	# ростер всем, иначе соперник видел бы не ту модель. Имя игрока — в
	# слот вместо ботовского ника.
	_roster[slot] = car_id
	_set_slot_name(slot, pname)
	_set_car_model(_cars[slot], car_id)
	# Вид трассы и размер заезда — ПЕРВЫМИ (надёжные RPC упорядочены): не
	# совпало — клиент перезагрузит сцену и представится заново, welcome
	# старой сцены пропадёт.
	_rx_track.rpc_id(id, _track_kind, Net.race_size)
	_rx_welcome.rpc_id(id, slot, _roster, _taken_mask())
	_rx_roster.rpc(_roster)
	_rx_names.rpc(_names)
	if _net_started and _late_slots.has(slot):
		# ОПОЗДАЛ к старту (см. _on_peer_joined): в идущую гонку не пускаем
		# вовсе, машину в его слоте продолжает вести бот. Обычно сюда он не
		# доходит — выше его уже забрал _route_elsewhere в свою комнату;
		# это запасной путь, когда комнат не осталось: сидит в лобби до
		# конца заезда — сервер тогда перезапустит трассу (_rx_reset), и он
		# войдёт в НОВУЮ гонку с отсчётом, как все.
		_rx_lobby_wait_next.rpc_id(id)
	elif _net_started:
		# Он БЫЛ В ЛОББИ (слот не помечен опоздавшим), но догрузился уже
		# после старта: заезд ушёл без него по HELLO_GRACE. Отсчёт этот
		# игрок пропустил, и без отдельной команды он навсегда остался бы
		# в лобби с выключенным управлением.
		# Вместе с командой отдаём МЕСТО его машины: у себя он строит сцену
		# с нуля и его машина стоит на стартовой решётке, а по трассе в это
		# время едет её серверная копия (её вёл бот). Без этого игрок
		# появлялся у старта посреди заезда — «мы начали вместе, а оказались
		# в разных местах», — а у остальных его машина в тот же миг
		# телепортировалась с трассы назад к решётке («бот приехал откуда-то
		# сзади»).
		# Но САЖАЕМ его в хвост поля, а не туда, куда уехал бот (см.
		# _seat_joiner_at_tail): иначе он появлялся далеко впереди
		# уже играющих.
		_seat_joiner_at_tail(slot)
		var car := _cars[slot]
		var q := car.global_transform.basis.get_rotation_quaternion()
		var p := car.global_position
		_rx_race_running.rpc_id(id, PackedFloat32Array(
				[p.x, p.y, p.z, q.x, q.y, q.z, q.w]))
		# И прогресс всех машин: иначе подсевший считал бы круги с нуля,
		# и его HUD (круг, место) врал бы до конца заезда.
		_rx_progress.rpc_id(id, PackedFloat32Array(_progress),
				PackedInt32Array(_laps_done))
	_rx_lobby.rpc(Net.slot_of_peer.size(),
			0 if _net_started else maxi(ceili(_lobby_wait), 0))
	# hello приходит из ГОТОВОЙ сцены клиента — значит, он загрузился и не
	# пропустит отсчёт. Только теперь его слот перестаёт блокировать старт.
	# Отметка — ПОСЛЕ ветки «заезд уже идёт»: если старт случится прямо
	# сейчас, этому игроку положен отсчёт, а не «включайся сразу».
	_hello_done[slot] = true
	_maybe_start()


## Игрок БЫЛ В ЛОББИ, но догрузился уже после старта. Такое бывает: если
## кто-то молчит дольше HELLO_GRACE, заезд стартует без него, а его машину
## всё это время ведёт бот. Отдать ему место бота нельзя — тот успевает
## уехать вперёд, и игрок появляется ВПЕРЕДИ всех (жалоба 31.08: «второй
## игрок появлялся не у старта, а далеко впереди, я его даже не видел на
## своём экране»). Сажаем в ХВОСТ поля: чуть позади самой отставшей машины.
## НОВЫХ игроков этот путь не касается вовсе — начавшийся заезд их не берёт
## (см. _on_peer_joined), им поднимают свою комнату.
## Двигаем только НАЗАД: кто и так позади всех, остаётся на месте.
## Прогресс и круги пересчитываем здесь же, иначе место в HUD врало бы до
## конца заезда (машина сзади, а по счётчику — лидер).
func _seat_joiner_at_tail(slot: int) -> void:
	if _track == null or slot < 0 or slot >= _cars.size():
		return
	var tail := -1
	for i in _cars.size():
		if i == slot or _finish_order.has(i):
			continue
		if tail < 0 or _progress[i] < _progress[tail]:
			tail = i
	if tail < 0 or _progress[slot] <= _progress[tail]:
		return
	var car: Car = _cars[slot]
	var was := _progress[slot]
	var length := _track._curve.get_baked_length()
	# respawn_transform_at ставит машину на полотно по отметке трассы —
	# берём отметку хвоста, отступив назад (сама функция даёт +6 м вперёд,
	# поэтому отступ считаем от неё).
	car.global_transform = _track.respawn_transform_at(
			_cars[tail].track_offset - JOIN_TAIL_GAP - 6.0)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_speed_memory()
	car.reset_track_offset()
	# Прогресс — от хвоста, на ФАКТИЧЕСКИ получившийся отступ по трассе.
	var gap := _cars[tail].track_offset - car.track_offset
	if gap > length * 0.5:
		gap -= length
	elif gap < -length * 0.5:
		gap += length
	_progress[slot] = _progress[tail] - gap
	_laps_done[slot] = maxi(0, int(floorf(_progress[slot] / length)))
	_last_offset[slot] = car.track_offset
	print("[net] подсевший в слот %d посажен в хвост поля: было %.0f м, стало %.0f м"
			% [slot, was, _progress[slot]])


## Клиент прислал состояние СВОЕЙ машины (она клиент-авторитетна). Сервер
## ведёт её марионеткой: _follow_snapshot экстраполирует между пакетами и
## сглаживает их неровный приход — как у марионеток на клиенте.
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rx_pstate(xf: PackedFloat32Array) -> void:
	if not Net.is_server() or xf.size() < 11:
		return
	var slot: int = Net.slot_of_peer.get(multiplayer.get_remote_sender_id(), -1)
	if slot < 0 or slot >= _cars.size():
		return
	var car := _cars[slot]
	if car.net_role != Car.NetRole.PUPPET:
		return
	# Пакет из ПРОШЛОЙ сцены клиента. После _rx_reset сервер строит новую
	# решётку, а состояние старой машины владельца ещё летит по сети — один
	# такой пакет телепортировал машину со старта туда, где игрок закончил
	# прошлый заезд, снимки разносили это всем, и оба игрока начинали новый
	# заезд «не у старта, а дальше» (жалоба 31.08). Пока клиент не
	# поздоровался В ЭТОЙ сцене, его состояние устарело — выбрасываем.
	if not _hello_done.has(slot):
		return
	var pos := Vector3(xf[0], xf[1], xf[2])
	var vel := Vector3(xf[7], xf[8], xf[9])
	# Санитария клиент-авторитетных данных — сервер обязан не доверять
	# слепо: битые (NaN/бесконечность) и заведомо невозможные значения
	# (за пределами мира, скорость много выше максимума машины) отравили
	# бы марионетку и снимки ВСЕМ клиентам. Молча выбрасываем пакет.
	if not (pos.is_finite() and vel.is_finite()) \
			or pos.length() > 600.0 or vel.length() > 60.0:
		return
	car.net_apply_snapshot(pos,
			Quaternion(xf[3], xf[4], xf[5], xf[6]).normalized(), vel,
			maxf(xf[10], 0.0))
	# Заморозка владельца (протокол 12) — та же санитария: NaN и вечный
	# лёд не пропускаем, потолок 10 c при дебафе в 3 c. Берём МАКСИМУМ со
	# своим значением: попав ледышкой, сервер морозит машину у себя и лишь
	# потом пересылает эффект владельцу — целый пинг тот докладывает «не
	# заморожен», и на голой замене шуба у всех остальных мигала бы.
	if xf.size() >= 12 and is_finite(xf[11]):
		car.net_set_freeze(maxf(car.freeze_left(), clampf(xf[11], 0.0, 10.0)))
	# Отставание картинки владельца (протокол 13) — по нему отматываем цели
	# при его выстрелах. Потолок 0.5 c: больше — это уже не компенсация, а
	# подарок стреляющему (и лазейка для нечестного клиента).
	if xf.size() >= 13 and is_finite(xf[12]):
		car.net_client_lag = clampf(xf[12], 0.0, 0.5)


## Клиент доложил: он протаранил машину другого ЖИВОГО игрока (протокол 11).
## Сервер — арбитр: проверяет правдоподобие по СВОЕЙ картине (обе машины
## рядом), зажимает величины теми же капами, что у рикошета, и пересылает
## толчок владельцу жертвы (_rx_fx SHOVE) — тот применит его к своей
## клиент-авторитетной машине. Без этого таран игрока игроком никого не
## двигал: каждый экран считает только СВОЮ машину, а на экране жертвы
## агрессор отстаёт на буфер и до неё не дотягивается.
@rpc("any_peer", "call_remote", "reliable")
func _rx_shove(victim_slot: int, dir: Vector3, closing: float,
		spin: float) -> void:
	if not Net.is_server():
		return
	var s: int = Net.slot_of_peer.get(multiplayer.get_remote_sender_id(), -1)
	if s < 0 or s >= _cars.size() \
			or victim_slot < 0 or victim_slot >= _cars.size() \
			or victim_slot == s:
		return
	var victim := _cars[victim_slot]
	# Жертва должна быть машиной живого игрока (боты толкаются здесь же,
	# на сервере, обычным рикошетом) и рядом с агрессором ПО НАШЕЙ картине.
	# Допуск 8 м — щедрый: у агрессора жертва отстаёт на ~0.35 c буфера.
	if victim.net_role != Car.NetRole.PUPPET:
		return
	if not (dir.is_finite() and is_finite(closing) and is_finite(spin)):
		return
	# Агрессор видел жертву В ПРОШЛОМ (на свой буфер ~0.35 c): на встречных
	# курсах 30+ м/с серверные «сейчас»-позиции расходятся дальше прежнего
	# допуска, и честный таран молча выбрасывался («тяжело оказывать
	# воздействие», жалоба 01.09). Меряем и к текущей позиции жертвы, и к
	# отмотанной на его лаг — хватит любой из двух.
	var attacker := _cars[s]
	var d_now := attacker.global_position.distance_to(victim.global_position)
	var d_past := attacker.global_position.distance_to(
			victim.past_position(attacker.net_shot_lag()))
	if minf(d_now, d_past) > 8.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var key := s * 100 + victim_slot
	if now - float(_shove_sent.get(key, -1.0e12)) < 0.15:
		return
	_shove_sent[key] = now
	net_forward_fx(victim, Car.NetFx.SHOVE,
			[s, dir, clampf(closing, 0.0, 20.0), clampf(spin, -3.0, 3.0)])


## Клиент просит выстрел. Оружие по-прежнему применяет ТОЛЬКО сервер:
## снаряды/мины настоящие лишь у него, клиенты видят инертные копии.
@rpc("any_peer", "call_remote", "reliable")
func _rx_press() -> void:
	if not Net.is_server():
		return
	var slot: int = Net.slot_of_peer.get(multiplayer.get_remote_sender_id(), -1)
	if slot < 0 or slot >= _cars.size():
		return
	_cars[slot].net_fire = true


@rpc("any_peer", "call_remote", "reliable")
func _rx_start_request() -> void:
	if not Net.is_server():
		return
	# Пробел не стартует гонку в обход загрузки: старт только запрашивается,
	# а состоится, когда все подключённые пришлют hello (_maybe_start).
	_want_start = true
	_maybe_start()


# ── сервер → клиенты ──

## Есть ли в ЭТОМ процессе место новому игроку: свободный слот И ЛОББИ.
## Начавшийся заезд новых не берёт вовсе (31.08) — пришедшему поднимут
## свою комнату. По этому же признаку нас выбирают чужие ворота
## (визитка Rooms).
func _joinable_here() -> bool:
	if Net.slot_of_peer.size() >= Net.race_size:
		return false
	return not _net_started


## Пристроить игрока, которому здесь нет места, в параллельный заезд.
## true — вопрос закрыт (перенаправлен, ждёт поднимающуюся комнату или
## получил отказ); false — пусть сработает старый путь «жди следующего»
## (только для опоздавшего СО слотом). Hello клиента повторяется раз в
## секунду (_say_hello), поэтому «комната ещё поднимается» — не состояние,
## которое надо помнить: следующий hello застанет её визитку и уедет.
func _route_elsewhere(id: int, slot: int) -> bool:
	var target := Rooms.find_joinable(Net.port)
	if target > 0:
		print("[rooms] пир %d отправлен в заезд на порту %d" % [id, target])
		_rx_redirect.rpc_id(id, target)
		return true
	if not Net.is_room:
		# Ворота поднимают новую комнату (комнаты не плодят процессы сами).
		if Rooms.spawn_pending():
			return true
		var port := Rooms.free_port(Net.port)
		if port > 0:
			Rooms.spawn(port)
			return true
	if slot >= 0:
		return false
	print("[rooms] пир %d: мест нет нигде — отказ" % id)
	_rx_kick.rpc_id(id, "Все заезды заняты — попробуй через минуту.")
	# Рвём с задержкой, чтобы сообщение успело дойти (как при отказе версии).
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if multiplayer.multiplayer_peer != null and Net.guests.has(id):
			multiplayer.multiplayer_peer.disconnect_peer(id))
	return true


## Битовая маска слотов, за которыми сидит ЖИВОЙ игрок.
func _taken_mask() -> int:
	var mask := 0
	for sl: int in Net.slot_of_peer.values():
		mask |= 1 << sl
	return mask


## Вид трассы заезда: сервер выбирает случайно, клиент обязан строить ТУ ЖЕ
## (иначе своя клиент-авторитетная машина ездила бы по другой геометрии).
## Не совпало — запоминаем и перезагружаем сцену (приём как у _rx_reset):
## новая сцена построит нужную трассу и заново представится серверу.
@rpc("authority", "call_remote", "reliable")
func _rx_track(kind: String, size := 4) -> void:
	# Размер заезда диктует сервер (его выбрал первый игрок лобби): наша
	# сцена построена под другое число машин — перестраиваемся, как при
	# несовпавшей трассе. Проверка размера ПЕРЕД трассой: совпасть должны оба.
	var want := clampi(size, GameState.RACE_SIZE_MIN, GameState.RACE_SIZE_MAX)
	var size_ok := want == Net.race_size and _cars.size() == want
	if size_ok and (kind == _track_kind or not TrackBuilder.KINDS.has(kind)):
		return
	print("[net] сервер выбрал трассу «%s» на %d машин — перестраиваемся"
			% [kind, want])
	if TrackBuilder.KINDS.has(kind):
		GameState.track_kind = kind
	Net.race_size = want
	Net.my_slot = -1
	_rebuilding = true
	get_tree().reload_current_scene()


@rpc("authority", "call_remote", "reliable")
func _rx_welcome(slot: int, roster: PackedStringArray, taken: int) -> void:
	# Сцена уже помечена на перестройку (чужая трасса/размер) — welcome
	# адресован ЕЙ и в новой сцене недействителен: там мы представимся
	# заново и получим свой. Записав my_slot сейчас, мы бы отучили новую
	# сцену здороваться (см. _rebuilding).
	if _rebuilding:
		return
	Net.my_slot = slot
	# Мы приняты в заезд — счёт прыжков перенаправлений (Rooms) обнуляется.
	Net.redirect_hops = 0
	# Канал меряем заново: могли переехать в другую комнату (Rooms) или
	# вернуться после обрыва — старое «худшее» к новому пути не относится.
	Car.net_reset_buf_delay()
	for s in _slot_taken.size():
		_slot_taken[s] = (taken & (1 << s)) != 0
	_apply_roster(roster)   # заодно обновит машины на экране лобби
	if slot < 0 or slot >= _cars.size():
		return
	# Своя машина перестаёт быть марионеткой: считаем её локально.
	var car := _cars[slot]
	car.freeze = false
	car.net_role = Car.NetRole.OWNED
	car.is_player = true
	# И ВСТАЁТ НА СВОЮ КЛЕТКУ РЕШЁТКИ. Пока мы ждали слот, она была
	# марионеткой, и устаревший снимок (сервер мог поймать хвост _rx_pstate
	# из сцены ПРОШЛОГО заезда — см. защиту в _rx_pstate) успевал увезти её
	# со старта: оба игрока начинали новый заезд там, где закончили прошлый
	# (жалоба 31.08). Подсевшему в идущую гонку место тут же перепишет
	# _rx_race_running — надёжные RPC приходят по порядку.
	if slot < _grid_xf.size():
		car.global_transform = _grid_xf[slot]
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.reset_speed_memory()
		car.reset_track_offset()
		_last_offset[slot] = car.track_offset
		var glen: float = _track._curve.get_baked_length()
		_progress[slot] = car.track_offset - glen \
				if car.track_offset > glen * 0.5 else car.track_offset
		_laps_done[slot] = 0
	# Интерполяция гасится на кадр (пересадка в свою машину — телепорт).
	# Исключения решателя с марионетками ОСТАЮТСЯ (см. net_make_puppet:
	# «твёрдая» версия вешала GodotPhysics на 300+ мс) — непроницаемость
	# даёт ручное выдавливание в _bounce_off_cars.
	car.net_visual_reset()
	_car = car
	var cam := get_node_or_null("IsoCamera") as IsoCamera
	if cam:
		cam.target = _car
	# Маркеры: своя машина зелёная, ВСЕ соперники — оранжевые. Раньше
	# стрелка была только над живыми игроками, но по просьбе 01.09 бот не
	# должен отличаться от человека — стрелка над каждым и ничего не выдаёт.
	_attach_marker(slot)
	for rival in _cars.size():
		if rival == slot:
			continue
		_attach_marker(rival, true)
		if _rival_markers.has(rival):
			_rival_markers[rival].visible = true
		if _minimap:
			_minimap.rivals[rival] = true
	# На карте — те же цвета: своя точка зелёная, соперники оранжевые.
	if _minimap:
		_minimap.my_index = slot


@rpc("authority", "call_remote", "reliable")
func _rx_roster(roster: PackedStringArray) -> void:
	_apply_roster(roster)


func _apply_roster(roster: PackedStringArray) -> void:
	for i in mini(roster.size(), _cars.size()):
		if i < _roster.size() and _roster[i] == roster[i]:
			continue
		_set_car_model(_cars[i], roster[i])
	_roster = roster
	_update_lobby_slots()


## Имена всех слотов (см. _names). Сервер шлёт при каждом изменении.
@rpc("authority", "call_remote", "reliable")
func _rx_names(names: PackedStringArray) -> void:
	_names = names
	_update_lobby_slots()


## Сервер: вписать имя игрока в слот. Чистим той же чисткой, что своё
## (клиенту ничто не мешает прислать мусор), пустое — «Игрок N», дубль
## чужого имени помечаем номером, чтобы в ленте не путать двоих тёзок.
func _set_slot_name(slot: int, pname: String) -> void:
	if slot < 0 or slot >= _names.size():
		return
	var n := GameState.sanitize_name(pname)
	if n == "":
		n = "Игрок %d" % (slot + 1)
	for s in _names.size():
		if s != slot and _names[s] == n:
			n = "%s (%d)" % [n.left(GameState.NAME_MAX - 4), slot + 1]
			break
	_names[slot] = n


## Клиент опоздал к идущему заезду и ждёт следующего (сервер держит его
## машину за ботом). Флаг живёт до конца этой сцены: сервер закончит заезд,
## перезапустит трассу и пришлёт _rx_reset — сцена перезагрузится, и игрок
## войдёт в новую гонку с отсчётом.
## Сервер отправляет нас в параллельный заезд-комнату на другом порту
## (Rooms.gd): здесь мест нет, а там лобби или свежая гонка. Порт комнаты
## НЕ запоминаем в net.cfg — «домашним» адресом остаются ворота. Кап
## прыжков — защита от пинг-понга между заполнившимися наперегонки
## комнатами: три подряд — честный отказ.
@rpc("authority", "call_remote", "reliable")
func _rx_redirect(port: int) -> void:
	if not Net.is_client() or port <= 0 or port > 65535:
		return
	Net.redirect_hops += 1
	if Net.redirect_hops > 3:
		_rx_kick("Свободный заезд не нашёлся — попробуй через минуту.")
		return
	print("[rooms] здесь мест нет — переезжаем в заезд на порту %d" % port)
	if _lobby:
		_lobby.show_screen()
		_lobby.set_status("Здесь всё занято — едем в свободный заезд…")
	var host := Net.host
	Net.leave()
	Net.my_slot = -1
	Net.join_server(host, port, false)
	# Чистая сцена представится комнате сама (_say_hello), как при _rx_track.
	get_tree().reload_current_scene()


## Свой таймаут на устанавливающееся соединение (сцена после _rx_redirect):
## комната могла умереть между визиткой и подключением или оказаться
## недоступной снаружи — ENet при этом молчит дольше CONNECT_TIMEOUT.
func _watch_join_timeout() -> void:
	await get_tree().create_timer(Net.CONNECT_TIMEOUT).timeout
	if not is_inside_tree() or not Net.is_client() or _going_home:
		return
	var peer := multiplayer.multiplayer_peer
	if peer != null and peer.get_connection_status() \
			== MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_on_join_failed_in_race("Сервер не ответил")


## Комната, куда нас отправили, не ответила. Раньше это был тупиковый экран
## «Сервер не ответил, Esc — в гараж» (27.08 у игрока: выслан в комнату,
## та не ответила — а ворота-то живы). Теперь возвращаемся ДОМОЙ к воротам:
## там либо дадут слот, либо перенаправят ещё раз (кап redirect_hops не даст
## кругу крутиться вечно). Тупиковый экран остаётся на случай, когда не
## ответил сам дом.
func _on_join_failed_in_race(reason: String) -> void:
	if _going_home:
		return
	if Net.port != Net.home_port:
		_going_home = true
		print("[rooms] заезд на порту %d не ответил — возвращаемся к воротам (%d)"
				% [Net.port, Net.home_port])
		if _lobby:
			_lobby.show_screen()
			_lobby.set_status("Заезд не ответил — возвращаемся к воротам…")
		var host := Net.host
		Net.leave()
		Net.my_slot = -1
		Net.join_server(host, Net.home_port, false)
		get_tree().reload_current_scene()
		return
	if _lobby:
		_lobby.set_status(reason + "
Esc — в гараж")
		_lobby.show_screen()


@rpc("authority", "call_remote", "reliable")
func _rx_lobby_wait_next() -> void:
	_wait_next_race = true
	if _car != null:
		_car.controls_enabled = false
	if _lobby == null:
		return
	_lobby.show_screen()
	_lobby.set_status("Заезд уже идёт — в него не влезть.
Ждём следующего: начнётся, как только эта гонка закончится.")


@rpc("authority", "call_remote", "reliable")
func _rx_lobby(players: int, secs: int) -> void:
	if _lobby == null:
		return
	# Ждущему следующего заезда общий статус лобби не показываем: он перетёр
	# бы объяснение, ПОЧЕМУ этот игрок стоит в лобби, на «Игроков: 1/4».
	if _wait_next_race:
		return
	if _net_started:
		_lobby.hide_screen()
		return
	_lobby.show_screen()
	var txt := "Игроков: %d/%d" % [players, _cars.size()]
	if secs > 0:
		txt += "
Ждём игроков: %d…" % secs
	elif secs < 0:
		# Старт запрошен, но у кого-то ещё грузится игра — ждём всех,
		# чтобы никто не въехал в уже идущий заезд после загрузки.
		txt += "
Ждём, пока у всех загрузится…"
	_lobby.set_status(txt)


@rpc("authority", "call_remote", "reliable")
func _rx_count(txt: String) -> void:
	# Страховка: отсчёт НОВОГО заезда не должен снова включить управление
	# финишировавшему (штатно до отсчёта придёт _rx_reset и сцена чистая).
	if _my_finished or _finished:
		return
	_net_started = true
	if _lobby:
		_lobby.hide_screen()
	if _count_label:
		_count_label.visible = true
	_pop_count(txt, UiKit.TEAL if txt == "GO!" else UiKit.YELLOW)
	if txt != "GO!":
		return
	# Управление включается по команде сервера: до GO! ввод не шлём.
	for c in _cars:
		c.controls_enabled = true
	await get_tree().create_timer(0.7).timeout
	if is_inside_tree() and _count_label:
		_count_label.visible = false


## Канал 1 — отдельный от reliable-событий (выстрелы, эффекты, лобби):
## на канале 0 потерянный reliable-пакет задерживал бы и поток состояния
## (head-of-line blocking) — стандартная практика сетевых игр: развести
## высокочастотный поток и редкие надёжные события по каналам.
@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _rx_state(xf: PackedFloat32Array, flags: PackedByteArray) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	# Диагностика ровности потока (читает tools/test_net.gd). Считать
	# приходы ОПРОСОМ из _physics_process нельзя: опрос идёт 60 раз в
	# секунду, снимки — тоже, и два прихода между кадрами сливаются в один.
	# Такой замер занижал поток до «43 из 60» даже на локалхосте, где терять
	# нечего. Поэтому счёт здесь, в самом обработчике.
	if _last_state_time > 0.0:
		var gap := now - _last_state_time
		_state_gap_sum += gap
		_state_gap_max = maxf(_state_gap_max, gap)
		_state_seen += 1
		# Крупные дыры печатаем поимённо: «средняя пауза» их прячет, а
		# видно на экране именно их (машина замирает и догоняет).
		# ПРИРОДУ дыры разбираем тут же — от неё зависит лечение, а «средняя
		# пауза» все три случая мешает в одну кучу:
		#   тиков≈дыре и кадров много — сервер работал, и мы опрашивали:
		#     пакеты копились в пути или в очереди отправки (клумпинг);
		#   тиков≈1 — сервер реально стоял (его фриз);
		#   кадров≈1 — стоял НАШ кадр, пакеты ждали в сокете.
		# Метка бота (слот без живого игрока) — часы САМОГО сервера.
		var srv := -1.0
		for i in _cars.size():
			var so := i * 11
			if so + 10 >= xf.size():
				break
			if i < _slot_taken.size() and not _slot_taken[i]:
				srv = xf[so + 10]
				break
		# Отставание воспроизведения подстраиваем под ЭТОТ канал прямо сейчас
		# (см. Car.net_note_gap): рвёт последняя миля, и рвёт по-разному в
		# разные минуты — фиксированные 0.35 c платили за худший случай всегда.
		if Net.is_client():
			Car.net_note_gap(gap)
		# ЗАМЕР ПРИРОДЫ ПОТЕРЬ: сколько снимков подряд не дошло. Метка бота —
		# часы сервера, поэтому разрыв меток и есть число пропавших. От этого
		# распределения зависит, поможет ли избыточность (лечит потери) или
		# нужен только буфер (лечит опоздания).
		if _loss_probe:
			var sv := -1.0
			for i in _cars.size():
				var lo := i * 11
				if lo + 10 >= xf.size():
					break
				if i < _slot_taken.size() and not _slot_taken[i]:
					sv = xf[lo + 10]
					break
			if sv >= 0.0:
				if _loss_prev >= 0.0:
					var miss := int(sv - _loss_prev) - 1
					if miss > 0:
						_loss_hist[miss] = int(_loss_hist.get(miss, 0)) + 1
						_loss_total += miss
					_loss_got += 1
				_loss_prev = sv
		if gap > 0.1:
			_state_gaps_big += 1
			var ticks := -1
			if srv >= 0.0 and _srv_stamp_prev >= 0.0:
				ticks = int(srv - _srv_stamp_prev)
			print("[gap] снимки не шли %d мс (часы %s): тиков сервера %d, "
					% [int(gap * 1000.0),
					Time.get_time_string_from_system(), ticks]
					+ "наших кадров %d"
					% int(Engine.get_process_frames() - _gap_frames_prev))
		if srv >= 0.0:
			_srv_stamp_prev = srv
		_gap_frames_prev = Engine.get_process_frames()
	_last_state_time = now
	for i in _cars.size():
		var o := i * 11
		var f := i * 5
		if o + 10 >= xf.size() or f + 4 >= flags.size():
			break
		# Место — с сервера: у него все машины одного времени (см. _pack_state).
		if i < _net_place.size():
			_net_place[i] = int(flags[f + 4])
		var c := _cars[i]
		var pos := Vector3(xf[o], xf[o + 1], xf[o + 2])
		var rot := Quaternion(
				xf[o + 3], xf[o + 4], xf[o + 5], xf[o + 6]).normalized()
		var vel := Vector3(xf[o + 7], xf[o + 8], xf[o + 9])
		# СВОЯ машина клиент-авторитетна: её позицию, «жизнь» и «призрака»
		# сервер не правит вовсе (раньше подтяжка сюда и давала рывки).
		# Эффекты оружия по ней приходят отдельным RPC (_rx_fx), а от
		# сервера ей нужны только выданное боксом оружие и значок эффекта.
		if c.net_role != Car.NetRole.OWNED:
			c.net_apply_snapshot(pos, rot, vel, maxf(xf[o + 10], 0.0))
			c.alive = (int(flags[f + 1]) & 1) != 0
			# «Призрака» подливаем по чуть-чуть: пока сервер шлёт флаг,
			# таймер не гаснет, а кончился флаг — призрак снимается.
			# Через net_set_ghost, а не записью в _ghost_time: только там
			# заводится фаза мигания и снимаются контакты (31.08 —
			# «не вижу, что он мигает при появлении»).
			c.net_set_ghost((int(flags[f + 1]) & 2) != 0)
			# Заморозка соперника (протокол 12): «синяя» шуба и заразность
			# при касании считаются по _freeze_time, а он у марионетки
			# ниоткуда не берётся. Своей машины это не касается — она
			# клиент-авторитетна, её замораживает _rx_fx.
			c.net_set_freeze(float(flags[f + 3]) * 0.1)
		c.weapon = int(flags[f]) - 1
		var kind := int(flags[f + 2]) - 2
		if kind >= 0:
			c.show_effect_icon(kind, 0.25)


## Клиент: мой рикошет о марионетку ЖИВОГО ИГРОКА (бота двигает сам сервер).
## Его машину моя половина рикошета не сдвинет — она клиент-авторитетна;
## докладываем серверу, тот проверит и перешлёт толчок владельцу (28.08:
## «при столкновении не могу его сдвинуть или поддеть»).
func net_report_shove(victim: Car, dir: Vector3, closing: float,
		spin: float) -> void:
	if not Net.is_client() or Net.my_slot < 0:
		return
	var v := _cars.find(victim)
	if v < 0 or v >= _slot_taken.size() or not _slot_taken[v]:
		return
	# Не чаще, чем раз в 0.15 c на жертву: контакт может мигать серией.
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_shove_sent.get(v, -1.0e12)) < 0.15:
		return
	_shove_sent[v] = now
	_rx_shove.rpc_id(1, v, dir, closing, spin)


## Сервер: переслать эффект оружия владельцу машины (зовёт Car._forward_fx).
## Машина живого игрока клиент-авторитетна — физику эффекта применит он.
func net_forward_fx(car: Car, kind: int, args: Array) -> void:
	if not Net.is_server():
		return
	var slot := _cars.find(car)
	for pid: int in Net.slot_of_peer:
		if Net.slot_of_peer[pid] == slot:
			_rx_fx.rpc_id(pid, kind, args)
			return


## Сервер: машину уничтожили — показать это ВСЕМ клиентам (зовёт
## Car.destroy). Владельцу эффект уезжает отдельно (NetFx.DESTROY): он свою
## машину взрывает и переставляет сам. Остальные раньше не видели НИЧЕГО —
## соперник просто переезжал снимками к месту появления и выглядел как
## спокойно едущий дальше (жалоба 31.08).
func net_broadcast_destroy(car: Car) -> void:
	if not Net.is_server():
		return
	var idx := _cars.find(car)
	if idx < 0:
		return
	_rx_destroy_fx.rpc(idx)


@rpc("authority", "call_remote", "reliable")
func _rx_destroy_fx(idx: int) -> void:
	if idx < 0 or idx >= _cars.size():
		return
	var car := _cars[idx]
	# Своя машина взрывается по _rx_fx DESTROY (она клиент-авторитетна):
	# второй взрыв здесь только удвоил бы вспышку.
	if car.net_role == Car.NetRole.OWNED:
		return
	car.net_show_destroy()


## Сервер: мина рванула — показать взрыв клиентам (зовёт Mine._try_trigger).
## У клиентов мина ИНЕРТНА (только картинка) и о срабатывании не знает:
## без этого она молча лежала бы на дороге до конца жизни, а машины рядом
## разлетались бы «сами по себе».
func net_broadcast_mine_blast(at: Vector3) -> void:
	if not Net.is_server():
		return
	_rx_mine_fx.rpc(at)


@rpc("authority", "call_remote", "reliable")
func _rx_mine_fx(at: Vector3) -> void:
	if not at.is_finite():
		return
	# Инертную копию, которая рванула, убираем: она своей жизнью не живёт.
	for node in get_children():
		var m := node as Mine
		if m != null and m.global_position.distance_to(at) < 3.0:
			m.queue_free()
	FlashFx.spawn(self, at, 3.2, Color(1.0, 0.4, 0.1))
	FxKit.ring(self, at, 5.5, Color(1.0, 0.5, 0.12))
	FxKit.smoke_burst(self, at + Vector3.UP * 0.5, 14, 1.4)
	SparksFx.spawn(self, at + Vector3.UP * 0.3, 12.0)
	FxKit.fire_burst(self, at + Vector3.UP * 0.2)
	FxKit.scorch(self, at, 2.8)


## По НАШЕЙ машине применили оружие — физику эффекта (толчок, закрутку,
## телепорт «призрака») считаем мы: машина клиент-авторитетна, и иначе
## игрок удара просто не почувствовал бы.
@rpc("authority", "call_remote", "reliable")
func _rx_fx(kind: int, args: Array) -> void:
	if _car == null or _car.net_role != Car.NetRole.OWNED:
		return
	match kind:
		Car.NetFx.DESTROY:
			_car.destroy()
		Car.NetFx.BLAST:
			if args.size() >= 4:
				_car.push_from_blast(args[0], args[1], args[2], args[3])
		Car.NetFx.FREEZE:
			if args.size() >= 1:
				_car.apply_freeze(args[0])
		Car.NetFx.SCRAMBLE:
			if args.size() >= 1:
				_car.apply_scramble(args[0])
		Car.NetFx.OIL:
			_car.apply_oil_slip()
		Car.NetFx.BOOST:
			_car.apply_boost(args.size() >= 1 and args[0])
		Car.NetFx.SLOW:
			if args.size() >= 1:
				_car.apply_speed_cut(args[0])
		Car.NetFx.SHOVE:
			if args.size() >= 4:
				var a := int(args[0])
				_car.apply_net_shove(
						_cars[a] if a >= 0 and a < _cars.size() else null,
						args[1], args[2], args[3])


## Живых игроков на все слоты не нашлось — свободные забрали боты. Лобби
## показывает их машины и ники КАК ОБЫЧНЫХ ИГРОКОВ: бот не должен
## отличаться от человека (01.09), поэтому ни слова «бот» на экране.
## mask = 0 — попытка старта отменена (подключился человек), слоты снова
## ждут людей.
@rpc("authority", "call_remote", "reliable")
func _rx_bots(mask: int) -> void:
	_bot_mask = mask
	if _lobby == null:
		return
	_update_lobby_slots()
	if mask == 0:
		_lobby.set_status("Игроков: %d/%d\nПодключился игрок — ждём его…"
				% [_taken_count(), _cars.size()])
		return
	_lobby.show_screen()
	_lobby.set_status("Все в сборе — поехали!")


## Сколько слотов занято живыми игроками (по нашей маске _slot_taken).
func _taken_count() -> int:
	var n := 0
	for t in _slot_taken:
		if t:
			n += 1
	return n


## Слот занял или освободил живой игрок. Стрелку и точку на карте НЕ
## трогаем: они висят над всеми соперниками (бот неотличим от игрока —
## 01.09), а маска занятых нужна лобби и сетевой кухне (по слоту без
## живого игрока _rx_state берёт метку часов сервера).
@rpc("authority", "call_remote", "reliable")
func _rx_slot_taken(slot: int, taken: bool) -> void:
	if slot >= 0 and slot < _slot_taken.size():
		_slot_taken[slot] = taken
		_update_lobby_slots()


## Сервер отказал (несовпадение версий и т.п.) — показываем причину и
## больше не стучимся. Соединение рвёт сервер, ретраи глушим слотом-«−2».
@rpc("authority", "call_remote", "reliable")
func _rx_kick(reason: String) -> void:
	Net.my_slot = -2   # не −1: _say_hello перестаёт повторять hello
	_kicked = true     # чтобы «связь потеряна» не перетёрло причину
	if _lobby:
		_lobby.set_status(reason + "
Esc — в гараж")
		_lobby.show_screen()


## Прогресс всех машин для подсевшего к идущему заезду: без него круги и
## место считались бы с нуля и HUD врал бы до конца заезда.
@rpc("authority", "call_remote", "reliable")
func _rx_progress(progress: PackedFloat32Array, laps: PackedInt32Array) -> void:
	for i in mini(progress.size(), _progress.size()):
		_progress[i] = progress[i]
	for i in mini(laps.size(), _laps_done.size()):
		_laps_done[i] = laps[i]
	# _last_offset — по фактическим позициям, иначе первый же кадр счёта
	# прибавил бы к прогрессу разницу «ноль → текущая точка трассы».
	for i in _cars.size():
		_cars[i].reset_track_offset()
		_last_offset[i] = _cars[i].track_offset


## Клиент подсел к уже идущему заезду — отсчёта не будет, включаемся сразу.
## xf — где сейчас едет НАША машина (её вёл бот, пока слот пустовал): своя
## сцена построена с нуля и машина стоит на стартовой решётке, так что без
## этой пересадки игрок появлялся у старта посреди заезда, а у остальных
## его машина прыгала с трассы к решётке.
@rpc("authority", "call_remote", "reliable")
func _rx_race_running(xf: PackedFloat32Array) -> void:
	if _my_finished or _finished:
		return
	_net_started = true
	if _lobby:
		_lobby.hide_screen()
	if _count_label:
		_count_label.visible = false
	if xf.size() >= 7 and _car != null and _car.net_role == Car.NetRole.OWNED:
		var pos := Vector3(xf[0], xf[1], xf[2])
		if pos.is_finite() and pos.length() < 600.0:
			_car.global_transform = Transform3D(
					Basis(Quaternion(xf[3], xf[4], xf[5], xf[6]).normalized()),
					pos)
			_car.linear_velocity = Vector3.ZERO
			_car.angular_velocity = Vector3.ZERO
			_car.reset_track_offset()
			_last_offset[_my_index()] = _car.track_offset
	for c in _cars:
		c.controls_enabled = true


## Машина i финишировала (порядок пересечения решает сервер). Своя —
## баннер и снятое управление; чужая — race_over для порядка.
@rpc("authority", "call_remote", "reliable")
func _rx_car_finished(i: int, place: int) -> void:
	if i < 0 or i >= _cars.size():
		return
	var car := _cars[i]
	car.race_over = true
	# Порядок финиша — истина сервера, и клиент ОБЯЗАН занести его в свой
	# _finish_order: место в HUD слева считает _place_of, и с пустым списком
	# доехавшие продолжали «соревноваться» прогрессом — слева «МЕСТО 2/4»,
	# а на баннере по центру честное «МЕСТО 3 ИЗ 4». Кладём по месту, а не
	# append: RPC надёжный и упорядоченный, но так дубль не собьёт список.
	if not _finish_order.has(i):
		while _finish_order.size() < place:
			_finish_order.append(-1)
		_finish_order[place - 1] = i
	if i == _my_index() and car.net_role == Car.NetRole.OWNED:
		car.controls_enabled = false
		_show_finish(place)


@rpc("authority", "call_remote", "reliable")
func _rx_finish() -> void:
	# Ждущий следующего заезда в этом не участвовал — баннер «ФИНИШ! МЕСТО N»
	# и опыт за чужую гонку ему не положены (сидит в лобби до _rx_reset).
	if _wait_next_race:
		return
	_finish_race()


## Сервер перезапустил трассу после заезда — перезапускаемся и мы, иначе
## останемся в старой сцене с баннером финиша и получим следующий отсчёт
## прямо в неё (можно было ехать «после финиша»). Соединение живо, слот
## освобождаем: новая сцена представится сервером заново (_say_hello).
@rpc("authority", "call_remote", "reliable")
func _rx_reset() -> void:
	if _net_lost or _kicked or not is_inside_tree():
		return
	print("[net] сервер начал новый заезд — перезагружаем сцену%s" % _mem_note())
	Net.my_slot = -1
	_rebuilding = true
	get_tree().reload_current_scene()


## Память и объекты — одной строкой. Клиент 26.08 закрывался НАСМЕРТЬ
## ровно на перезагрузке сцены после заезда, а перезагрузка — это разом
## снос всей графики заезда и постройка новой. Если дело в накопленном за
## гонку (узлы эффектов, следы шин, меши трассы), это видно в цифрах ДО
## сноса: печатаем их при готовности сцены и при каждом reset, чтобы у
## живого игрока в user://logs осталась улика, а не только факт закрытия.
func _mem_note() -> String:
	return " [память %.0f МБ, узлов %d, объектов %d]" % [
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_COUNT)]


@rpc("authority", "call_remote", "reliable")
func _rx_weapon_fx(idx: int, kind: int, pos: Vector3, dir: Vector3) -> void:
	if idx < 0 or idx >= _cars.size():
		return
	# Эхо СВОЕГО лазера: луч уже нарисован в момент нажатия (_client_tick),
	# второй — с задержкой на пинг — рисовался бы поверх и «двоил» выстрел.
	if kind == Weapons.LASER and idx == _my_index() \
			and Time.get_ticks_msec() / 1000.0 - _laser_predicted < 1.0:
		return
	_spawn_weapon_visual(kind, pos, dir, _cars[idx])


## Сервер зовёт это из Car.use_weapon — чтобы клиенты УВИДЕЛИ выстрел.
func net_broadcast_weapon(car: Car, kind: int) -> void:
	if not Net.is_server():
		return
	var idx := _cars.find(car)
	if idx < 0:
		return
	var fwd := -car.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		fwd = Vector3.FORWARD
	_rx_weapon_fx.rpc(idx, kind, car.global_position, fwd.normalized())


## Клиентская КОПИЯ выстрела — только картинка. Мины, масло и снаряды
## здесь ИНЕРТНЫ: попадания и толчки считает сервер, а его результат и так
## приезжает в снимках. Если бы копии работали по-настоящему, машину било
## бы дважды — и по-разному на каждом экране.
## shooter — машина стрелявшего: луч лазера и волна глушилки ЕДУТ С НЕЙ
## (см. LaserFx), а не висят там, где нажали.
func _spawn_weapon_visual(kind: int, pos: Vector3, dir: Vector3,
		shooter: Car = null) -> void:
	match kind:
		Weapons.MINE:
			var m := Mine.new()
			m.inert = true
			add_child(m)
			m.global_position = pos - dir * 2.4 + Vector3.UP * 0.1
		Weapons.ROCKET, Weapons.FREEZE:
			var pr := Projectile.new()
			pr.inert = true
			pr.direction = dir
			pr.freeze = kind == Weapons.FREEZE
			add_child(pr)
			pr.global_position = pos + dir * 2.3 + Vector3.UP * 0.55
		Weapons.OIL:
			var oil := OilSlick.new()
			oil.inert = true
			add_child(oil)
			oil.global_position = pos - dir * 3.0 + Vector3.UP * 0.12
		Weapons.MAGNET:
			FlashFx.spawn(self, pos + Vector3.UP * 0.5, 3.2,
					Color(0.8, 0.3, 1.0))
			FxKit.ring(self, pos, 5.0, Color(0.8, 0.3, 1.0))
			FxKit.lightning_burst(self, pos + Vector3.UP * 0.8,
					Color(0.85, 0.4, 1.0), 7, 1.4)
		Weapons.LASER:
			LaserFx.spawn(self, pos + Vector3.UP * 0.5, dir, 70.0, shooter)
		Weapons.SCRAMBLE:
			var wave := ScrambleWave.new()
			wave.inert = true
			wave.track = _track
			wave.direction = dir
			add_child(wave)
			wave.global_position = pos + dir * 2.3 + Vector3.UP * 0.55
			# Волна радиуса действия от стрелявшего — как у него самого.
			FxKit.ring(self, pos, ScrambleWave.HIT_R, Color(0.4, 0.95, 1.0))
		Weapons.AIRSTRIKE:
			var strike := Airstrike.new()
			strike.inert = true
			strike.track = _track
			strike.target = leader_car()
			add_child(strike)
		Weapons.BOOST:
			FlashFx.spawn(self, pos + Vector3.UP * 0.5, 1.2,
					Color(0.3, 0.9, 1.0))
			FxKit.ring(self, pos, 2.2, Color(0.3, 0.9, 1.0))


## Обновить экран лобби: какие слоты заняты живыми игроками и на каких
## машинах они приехали (ростер сервер рассылает при каждом изменении).
func _update_lobby_slots() -> void:
	if _lobby == null:
		return
	for s in _slot_taken.size():
		var id := _roster[s] if s < _roster.size() else ""
		_lobby.set_slot(s, _slot_taken[s], id, s == Net.my_slot,
				(_bot_mask & (1 << s)) != 0, car_label(s))


# ════════════════════ ЛЕНТА СОБЫТИЙ ОРУЖИЯ ════════════════════
# «Player 1 [иконка] → Player 2»: кто по кому применил оружие. Попадания
# знает только сервер (у клиентов оружие — инертная картинка) или
# оффлайн-игра, поэтому события порождаются там и рассылаются RPC.

const FEED_MAX := 5        # больше записей разом не держим
const FEED_LIFETIME := 7.0 # сколько запись висит до угасания, с
# Раньше этого запись НЕЛЬЗЯ вытеснить новой: в разгар боя события идут
# чаще, чем раз в секунду, и без этого порога записи сменялись быстрее,
# чем их успеваешь прочитать. Лишние события ждут в _feed_pending.
const FEED_MIN_SHOW := 4.0


## Имя машины для ленты, лобби и анонсов: живой игрок — как представился,
## бот — ник из PlayerNames. Запас «Player N» — только пока клиент ещё не
## получил имена с сервера (_rx_names).
func car_label(i: int) -> String:
	if i >= 0 and i < _names.size() and _names[i] != "":
		return _names[i]
	return "Player %d" % (i + 1)


## Оружие attacker подействовало на victim (зовёт Car.notify_hit_by).
func report_weapon_hit(attacker: Car, victim: Car, kind: int) -> void:
	if attacker == null or victim == null or attacker == victim:
		return
	var ai := _cars.find(attacker)
	var vi := _cars.find(victim)
	if ai < 0 or vi < 0:
		return
	if Net.is_server():
		_rx_weapon_event.rpc(ai, vi, kind)
	elif not Net.is_client():
		_show_weapon_event(ai, vi, kind)


@rpc("authority", "call_remote", "reliable")
func _rx_weapon_event(ai: int, vi: int, kind: int) -> void:
	_show_weapon_event(ai, vi, kind)


## Событие для ленты. Счётчик серий — сразу (_register_kill), а сама
## запись — через очередь _feed_pending: на экран попадает, когда есть
## место или старейшая запись провисела хотя бы FEED_MIN_SHOW.
func _show_weapon_event(ai: int, vi: int, kind: int) -> void:
	if _feed_box == null:
		return
	if kind in LETHAL_KINDS:
		_register_kill(ai, vi)
	# Глушилку одним значком над крышей не объяснить: игрок должен понять,
	# ПОЧЕМУ машина едет не туда, а не решить, что игра сломалась.
	if kind == Weapons.SCRAMBLE and vi == _my_index() and _announcer != null:
		_announcer.small("Управление сбито: лево и право поменялись!", "red")
	_feed_pending.append([ai, vi, kind])
	if _feed_pending.size() > FEED_MAX:
		_feed_pending.pop_front()
	_pump_feed()


## Выпустить ожидающие события на экран (зовёт _process и новые события).
func _pump_feed() -> void:
	if _feed_box == null or _feed_pending.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	while not _feed_pending.is_empty():
		if _feed_box.get_child_count() >= FEED_MAX:
			var oldest := _feed_box.get_child(0)
			if now - float(oldest.get_meta("born", 0.0)) < FEED_MIN_SHOW:
				return   # все записи ещё свежие — событие подождёт
			oldest.free()
		var e: Array = _feed_pending.pop_front()
		_add_feed_entry(e[0], e[1], e[2], now)


## Запись в ленту: имя, иконка оружия, стрелка, жертва. Висит
## FEED_LIFETIME и угасает.
func _add_feed_entry(ai: int, vi: int, kind: int, now: float) -> void:
	var entry := PanelContainer.new()
	entry.set_meta("born", now)
	var sb := UiKit.steel_box()
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	entry.add_theme_stylebox_override("panel", sb)
	entry.size_flags_horizontal = Control.SIZE_SHRINK_END
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	entry.add_child(row)
	_feed_name(row, ai)
	var icon := TextureRect.new()
	icon.texture = Weapons.icon(kind)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(26, 26)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.tooltip_text = Weapons.display_name(kind)
	row.add_child(icon)
	var arrow := _make_label(row, "→", 16, Color(1, 1, 1, 0.7), 4)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_feed_name(row, vi)
	_feed_box.add_child(entry)
	var tw := entry.create_tween()
	tw.tween_interval(FEED_LIFETIME)
	tw.tween_property(entry, "modulate:a", 0.0, 0.8)
	tw.tween_callback(entry.queue_free)


## Имя в ленте: своё — зелёное (как стрелка над машиной), чужие — жёлтые.
func _feed_name(parent: Node, idx: int) -> void:
	var l := _make_label(parent, car_label(idx), 16,
			UiKit.GREEN_ME if idx == _my_index()
			else Color(1, 0.9, 0.45), 4)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER


# ════════════════════ ВСПЛЫВАЮЩИЕ АНОНСЫ ════════════════════
# Крупные события гонки штампуются табличками по центру экрана
# (Announcer): серии убийств, первая кровь, последний круг, лидерство,
# личные «вас уничтожил…». Работает и оффлайн, и на клиенте: события
# оружия приезжают через _rx_weapon_event, прогресс — в снимках.

## Летальное попадание: серия убийств (окно KILL_STREAK_WINDOW — лазер и
## авиаудар кладут нескольких за раз), первая кровь, личные анонсы.
func _register_kill(ai: int, vi: int) -> void:
	if _announcer == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var streak: Dictionary = _kill_streak.get(ai, {"count": 0, "time": -10.0})
	if now - streak["time"] > KILL_STREAK_WINDOW:
		streak["count"] = 0
	streak["count"] += 1
	streak["time"] = now
	_kill_streak[ai] = streak

	if not _first_blood_done:
		_first_blood_done = true
		_announcer.big("ПЕРВАЯ КРОВЬ!", car_label(ai), "orange")
	match streak["count"]:
		2: _announcer.big("ДВОЙНОЕ УБИЙСТВО!", car_label(ai), "red")
		3: _announcer.big("ТРОЙНОЕ УБИЙСТВО!", car_label(ai), "red")

	var me := _my_index()
	if vi == me:
		_announcer.small("Вас уничтожил %s" % car_label(ai), "red")
	elif ai == me:
		_my_kills += 1   # копилка опыта за заезд (см. _show_finish)
		_announcer.small("%s уничтожен!" % car_label(vi), "teal")


## Ежекадровые проверки для анонсов: последний круг и смена лидерства.
## Зовётся из _process только там, где есть HUD (не на сервере).
func _tick_announcements(delta: float) -> void:
	if _announcer == null:
		return
	var racing: bool = _car.controls_enabled and not _finished \
			and not _my_finished
	if racing:
		_race_time += delta

	# Последний круг — один раз, когда МОЯ машина на него выехала.
	if racing and not _last_lap_told \
			and _laps_done[_my_index()] == LAPS - 1:
		_last_lap_told = true
		_announcer.big("ПОСЛЕДНИЙ КРУГ!", "", "yellow")

	# Лидерство: место 1 с дебаунсом 0.8 с (борьба бок-о-бок не должна
	# сыпать анонсы очередью). Первые секунды после старта молчим —
	# состояние только устанавливается.
	if not racing:
		return
	var leading := _player_place() == 1
	if leading == _lead_shown:
		_lead_flip_time = 0.0
		return
	_lead_flip_time += delta
	if _lead_flip_time < 0.8:
		return
	_lead_flip_time = 0.0
	_lead_shown = leading
	if _race_time < 5.0:
		return   # стартовая раздача мест — не событие
	if leading:
		_announcer.big("ВЫ ЛИДЕР!", "", "teal")
	else:
		_announcer.small("Лидерство потеряно", "red")
