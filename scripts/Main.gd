extends Node3D
## Гонка в духе Rock'n'Roll Racing: трасса, игрок + 3 ИИ-соперника,
## отсчёт 3-2-1-GO, 4 круга, позиции, «резинка» ИИ, HUD (скорость, круг,
## позиция, HP, боезапас), финиш. Всё собирается из кода.

const LAPS := 4
const AI_COUNT := 3
# По сети машин всегда 4: слоты 0 и 1 — живые игроки (пустой слот до
# подключения ведёт бот), 2 и 3 — боты.
const NET_CARS := 4
# Снимков состояния в секунду — с частотой физики. На машину уходит 43 байта,
# на четыре — меньше 200, то есть ~10 КБ/с на клиента: для двух игроков это
# ничто. А ровность движения от частоты зависит прямо: замер «насколько
# пройденный за кадр путь сходится с присланной скоростью» (tools/test_net.gd)
# даёт 5.0% при 30 снимках в секунду и 1.2% при 60 (эталон одиночной игры —
# 0.3%). Игрок жаловался как раз на дёрганое движение, так что берём 60.
const SNAP_HZ := 60.0
# Сколько ждать ВТОРОГО живого игрока после подключения первого.
# Не дождались — едем по старинке, пустой слот берёт бот.
# 5 с оказалось мало в жизни: у второго игрока игра грузится дольше
# (первый вход — компиляция шейдеров), и первый успевал уехать с ботами.
# Пробел по-прежнему стартует сразу, ждать 20 с никто не заставляет.
const LOBBY_WAIT := 20.0
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
var _progress: Array[float] = []    # накопленный путь вдоль оси, м
var _last_offset: Array[float] = []
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
var _rival_marker: Node3D           # и над машиной живого соперника
var _marker_time := 0.0

var _net_started := false           # сервер: гонка идёт (иначе лобби)
var _snap_accum := 0.0              # накопитель до следующего снимка
var _net_lost := false              # клиент: связь пропала, уходим в гараж
var _kicked := false                # клиент: сервер отказал (версии и т.п.)
var _last_state_time := 0.0         # клиент: когда пришёл последний снимок
var _lobby_wait := -1.0             # сервер: остаток ожидания, <0 — не идёт
var _roster := PackedStringArray()  # id моделей машин по слотам
var _lobby: Lobby                   # полноэкранное лобби на клиенте
# Клиент: какие слоты заняты живыми игроками (для экрана лобби).
var _slot_taken: Array[bool] = [false, false]
var _feed_box: VBoxContainer        # лента «кто кого чем» (события оружия)

var _speed_label: Label
var _lap_label: Label
var _pos_label: Label
var _weapon_icon: TextureRect   # иконка оружия в круглом слоте
var _weapon_name: Label
var _q_mark_tex: Texture2D      # «?» в пустом слоте
var _last_weapon := -2          # чтобы не перезагружать иконку каждый кадр
var _warn_panel: Panel
var _warn_label: Label
var _minimap: Minimap           # мини-карта в правом верхнем углу
var _count_label: Label         # отсчёт 3-2-1-GO
var _finish_root: Control       # баннер финиша
var _finish_label: Label
var _ui_font: FontFile          # Softie Cyr — мультяшный шрифт (с кириллицей)


func _ready() -> void:
	# Выделенный сервер: тот же Main, но без камеры, HUD и своей машины.
	# Запуск: godot --headless --path . res://scenes/Main.tscn -- --server
	if Net.wants_server() and not Net.is_online():
		if not Net.start_server():
			get_tree().quit(1)
			return
	_setup_environment()

	_track = TrackBuilder.new()
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
		print("[net] трасса готова, ждём игроков")
		# Сцена могла быть перезагружена после прошлого заезда — тогда
		# игроки УЖЕ подключены, и peer_connected по ним больше не придёт.
		# Возвращаем их машины на присланный ввод руками.
		for pid: int in Net.slot_of_peer.keys():
			_on_peer_joined(pid, Net.slot_of_peer[pid])
	elif Net.is_client():
		# Клиент ничего не начинает сам: представляемся серверу и ждём
		# от него слот, ростер машин и команду отсчёта. Если рукопожатие
		# ещё не закончилось (сцену могли открыть сразу), ждём сигнала —
		# RPC, отправленный до соединения, просто пропадёт.
		Net.left.connect(_on_net_lost)
		if _lobby:
			_lobby.show_screen()
		var peer := multiplayer.multiplayer_peer
		if peer != null and peer.get_connection_status() 				== MultiplayerPeer.CONNECTION_CONNECTED:
			_say_hello()
		else:
			Net.joined.connect(_say_hello, CONNECT_ONE_SHOT)
	else:
		_countdown()


## Стартовая решётка: 2 колонны. Оффлайн — игрок впереди слева и 3 бота.
## По сети — 4 машины: слоты 0 и 1 держатся за живыми игроками, 2 и 3 всегда
## боты. Пустой слот игрока до подключения ведёт бот (net_role LOCAL), при
## подключении сервер переключает машину на присланный ввод — так гонка
## идёт и с одним игроком, и никто не ждёт второго впустую.
func _spawn_cars() -> void:
	var st := _track.start_transform()
	var dir := -st.basis.z
	var right := st.basis.x
	var count := NET_CARS if Net.is_online() else AI_COUNT + 1
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

		var row := i / 2
		var col := i % 2
		var pos: Vector3 = st.origin - dir * (2.0 + row * 5.0) 				+ right * (2.2 if col == 1 else -2.2)
		car.transform = Transform3D(st.basis, pos)
		add_child(car)
		_set_car_model(car, ids[i])

		_cars.append(car)
		_progress.append(0.0)
		_laps_done.append(0)
		_offtrack_time.append(0.0)
		_flip_time.append(0.0)
		_stall_time.append(0.0)
		_last_offset.append(0.0)

	_roster = ids
	_car = _cars[0]
	if Net.is_client():
		# Пока сервер не выдал слот, СВОЕЙ машины нет — все марионетки.
		for c in _cars:
			c.net_make_puppet()
	elif not Net.is_server():
		_attach_marker(0)

	var length := _track._curve.get_baked_length()
	for i in _cars.size():
		var off := _track._curve.get_closest_offset(_cars[i].global_position)
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
	else:
		_build_placeholder_visual(car)


## Стрелка-указатель над машиной: своя — зелёная, живой соперник — оранжевая
## (боты без маркера). Именно так «реальный игрок» отличается от ботов.
func _attach_marker(index: int, rival := false) -> void:
	if index < 0 or index >= _cars.size():
		return
	var marker := _build_player_marker(
			Color(1.0, 0.55, 0.1) if rival else Color(0.15, 0.95, 0.25))
	_cars[index].add_child(marker)
	_cars[index].has_marker = true
	if rival:
		_rival_marker = marker
	else:
		_player_marker = marker


## Боксы с оружием: ПО ОДНОМУ на отметку, посреди полотна. Раньше их
## ставили тройками поперёк трассы, и бокс исчезал после подбора — кто
## успел, тот и съел. Теперь бокс один, не исчезает, и каждый проехавший
## забирает свой случайный бонус (см. WeaponBox).
func _spawn_weapon_boxes() -> void:
	var curve: Curve3D = _track._curve
	var length := curve.get_baked_length()
	for t: float in [0.12, 0.3, 0.52, 0.7, 0.92]:
		var off := length * t
		var box := WeaponBox.new()
		add_child(box)
		box.global_position = curve.sample_baked(off) + Vector3.UP * 0.85


## Лидер гонки (по прогрессу) — цель авиаудара.
func leader_car() -> Car:
	var best := 0
	for i in range(1, _cars.size()):
		if _progress[i] > _progress[best]:
			best = i
	return _cars[best]


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
		_pop_count(txt, Color(1, 0.85, 0.25))
		if Net.is_server():
			_rx_count.rpc(txt)
		await get_tree().create_timer(0.8).timeout
		if not is_inside_tree():
			return
	_pop_count("GO!", Color(0.5, 1.0, 0.35))
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
	if _cars.is_empty():
		return
	var curve: Curve3D = _track._curve
	var length := curve.get_baked_length()

	for i in _cars.size():
		var off := curve.get_closest_offset(_cars[i].global_position)
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
	# Мерим от ЛИДЕРА, а не от машины 0: по сети машина 0 — просто один
	# из слотов, и привязка к ней сделала бы резинку бессмысленной.
	if not Net.is_client():
		var lead := _progress[0]
		for i in _cars.size():
			lead = maxf(lead, _progress[i])
		for i in _cars.size():
			if _cars[i].net_role == Car.NetRole.LOCAL and not _cars[i].is_player:
				_cars[i].ai_rubber = clampf(
						1.0 + (lead - _progress[i]) / 120.0, 0.85, 1.3)

	if Net.is_server():
		_server_tick(_delta)
	elif Net.is_client():
		_client_tick(_delta)


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
	marker.position = Vector3(0, 2.4, 0)
	return marker


func _process(delta: float) -> void:
	# Лёгкое покачивание по высоте (без вращения — оно отвлекало).
	_marker_time += delta
	var bob := 2.4 + 0.12 * sin(_marker_time * 3.0)
	if _player_marker:
		_player_marker.position.y = bob
	if _rival_marker:
		_rival_marker.position.y = bob
	if _car and _speed_label:
		_speed_label.text = str(int(_car.speed_kmh()))
		if _car.weapon != _last_weapon:
			_last_weapon = _car.weapon
			if _car.weapon >= 0:
				_weapon_icon.texture = Weapons.icon(_car.weapon)
				_weapon_icon.modulate = Color.WHITE
				_weapon_name.text = Weapons.display_name(_car.weapon)
			else:
				_weapon_icon.texture = _q_mark_tex
				_weapon_icon.modulate = Color(1, 1, 1, 0.4)
				_weapon_name.text = "возьми бокс"
		_lap_label.text = "КРУГ %d/%d" % [
				clampi(_laps_done[_my_index()] + 1, 1, LAPS), LAPS]
		_pos_label.text = "МЕСТО %d/%d" % [_player_place(), _cars.size()]

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
		# автовозврат) для неё делаем мы, сервер её не двигает.
		if _car != null and _car.net_role == Car.NetRole.OWNED:
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


func _place_of(idx: int) -> int:
	var place := 1
	for j in _cars.size():
		if j != idx and _progress[j] > _progress[idx]:
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
## кто доехал позже, на него уже не влияет.
func _show_finish(place: int) -> void:
	_my_finished = true
	if _count_label:
		_count_label.visible = false
	_finish_label.text = "ФИНИШ!  Место: %d из %d" % [place, _cars.size()]
	_finish_root.visible = true


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
	var car := _cars[i]
	car.global_transform = _track.respawn_transform(car.global_position)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_speed_memory()
	_offtrack_time[i] = 0.0
	_flip_time[i] = 0.0
	_stall_time[i] = 0.0
	if _warn_panel and i == _my_index():
		_warn_panel.visible = false


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

		var dist := _track.distance_from_axis(car.global_position)
		if dist > _track.half_width_at_pos(car.global_position) + OFFTRACK_MARGIN:
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


func _setup_environment() -> void:
	if Net.is_server():
		return   # см. _set_car_model: сервер без косметики
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	# Голубое градиентное небо (мультяшный день — под стать декору трассы).
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.55, 0.87)
	sky_mat.sky_horizon_color = Color(0.74, 0.85, 0.95)
	sky_mat.ground_horizon_color = Color(0.74, 0.85, 0.95)
	sky_mat.ground_bottom_color = Color(0.28, 0.4, 0.24)  # в тон травы
	sky_mat.sun_angle_max = 15.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.65, 0.67, 0.72)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)


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


## Плоская скруглённая панель с тонкой рамкой. Именно плоская: у всех
## «прямоугольников» GUI Pack Cartoon края пузатые (гуляют до 12-19 px),
## и растянутая 9-slice панель выходит «облаком с выпуклостями».
func _make_panel(parent: Node, pos: Vector2, panel_size: Vector2,
		bg := Color(0.09, 0.13, 0.25, 0.82)) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.22)
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.size = panel_size
	parent.add_child(p)
	return p


## Надпись мультяшным шрифтом Softie Cyr (есть кириллица) с обводкой.
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
		l.add_theme_color_override("font_outline_color", Color(0.09, 0.1, 0.17))
	parent.add_child(l)
	return l


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_ui_font = load("res://assets/ui/Softie.ttf")
	_q_mark_tex = load("res://assets/ui/q_mark.png")
	# Скорость: крупные цифры.
	var speed_panel := _make_panel(canvas, Vector2(16, 12), Vector2(190, 66))
	_speed_label = _make_label(speed_panel, "0", 40, Color.WHITE, 6)
	_speed_label.position = Vector2(20, 5)
	_speed_label.size = Vector2(100, 56)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var kmh := _make_label(speed_panel, "км/ч", 15,
			Color(1, 1, 1, 0.75), 4)
	kmh.position = Vector2(130, 36)

	# Круг и место.
	var info_panel := _make_panel(canvas, Vector2(16, 86), Vector2(190, 78))
	_lap_label = _make_label(info_panel, "КРУГ 1/%d" % LAPS, 20,
			Color(1, 0.9, 0.45), 5)
	_lap_label.position = Vector2(22, 12)
	_pos_label = _make_label(info_panel, "МЕСТО 1/4", 20,
			Color.WHITE, 5)
	_pos_label.position = Vector2(22, 42)

	# Мини-карта в правом верхнем углу: контур трассы и точки-машины.
	# Панель привязана к ПРАВОМУ краю (anchor 1.0), чтобы не уезжать при
	# другом разрешении окна.
	var map_panel := _make_panel(canvas, Vector2.ZERO, Vector2(228, 158),
			Color(0.07, 0.09, 0.16, 0.92))
	map_panel.anchor_left = 1.0
	map_panel.anchor_right = 1.0
	map_panel.offset_left = -244
	map_panel.offset_right = -16
	map_panel.offset_top = 12
	map_panel.offset_bottom = 170
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_panel.add_child(_minimap)
	_minimap.setup(_track, _cars)
	_minimap.my_index = _my_index()

	# Слот оружия: тёмный глянцевый круг + иконка + подпись.
	var slot := TextureRect.new()
	slot.texture = load("res://assets/ui/circle_dark.png")
	# expand_mode СТРОГО до size: при дефолтном KEEP_SIZE присвоение size
	# клампится к размеру текстуры (512) и слот выходит гигантским.
	slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	slot.position = Vector2(24, 178)
	slot.size = Vector2(96, 96)
	canvas.add_child(slot)
	_weapon_icon = TextureRect.new()
	_weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weapon_icon.position = Vector2(17, 15)
	_weapon_icon.size = Vector2(62, 62)
	slot.add_child(_weapon_icon)
	_weapon_name = _make_label(canvas, "", 15, Color(1, 0.9, 0.45), 4)
	_weapon_name.position = Vector2(0, 276)
	_weapon_name.size = Vector2(144, 22)
	_weapon_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Предупреждение (вылет/переворот/застрял) — красная плашка сверху.
	_warn_panel = _make_panel(canvas, Vector2.ZERO, Vector2(440, 56),
			Color(0.82, 0.16, 0.2, 0.92))
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
	_count_label = _make_label(canvas, "", 120, Color(1, 0.85, 0.25), 16)
	_count_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.visible = false

	# Финиш: розовый баннер-лента + текст.
	_finish_root = Control.new()
	_finish_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_finish_root.visible = false
	canvas.add_child(_finish_root)
	var banner := TextureRect.new()
	banner.texture = load("res://assets/ui/flag_banner.png")
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.anchor_top = 0.5
	banner.anchor_bottom = 0.5
	banner.offset_left = -310
	banner.offset_right = 310
	banner.offset_top = -170
	banner.offset_bottom = 28
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_finish_root.add_child(banner)
	_finish_label = _make_label(banner, "", 30, Color.WHITE, 8)
	_finish_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_finish_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_finish_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var finish_hint := _make_label(_finish_root, "Enter — в гараж", 18,
			Color(1, 1, 1, 0.85), 5)
	finish_hint.anchor_left = 0.5
	finish_hint.anchor_right = 0.5
	finish_hint.anchor_top = 0.5
	finish_hint.anchor_bottom = 0.5
	finish_hint.offset_left = -150
	finish_hint.offset_right = 150
	finish_hint.offset_top = 44
	finish_hint.offset_bottom = 72
	finish_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var help := Label.new()
	help.text = "WASD — движение | Space — ручник | Shift — прыжок | " \
			+ "E — оружие | R — на трассу | Esc — меню"
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.position = Vector2(20, -30)
	help.add_theme_font_size_override("font_size", 14)
	if _ui_font:
		help.add_theme_font_override("font", _ui_font)
	help.modulate = Color(1, 1, 1, 0.7)
	canvas.add_child(help)

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
	car.net_make_puppet()
	# О занятии слота сообщаем СРАЗУ, до всех ветвлений. Раньше это стояло в
	# конце, и когда второй игрок запускал заезд своим подключением, функция
	# выходила раньше отправки: у первого игрока метка живого соперника так и
	# не загоралась. Поймано двухклиентским прогоном теста.
	_rx_slot_taken.rpc(slot, true)
	if _net_started:
		_rx_lobby.rpc(Net.slot_of_peer.size(), 0)
		return
	if Net.slot_of_peer.size() >= Net.PLAYER_SLOTS:
		# Второй приехал — ждать больше некого, стартуем сразу.
		_lobby_wait = -1.0
		_start_net_race()
		return
	# Первый игрок: даём LOBBY_WAIT секунд на то, чтобы подтянулся второй.
	if _lobby_wait < 0.0:
		_lobby_wait = LOBBY_WAIT
	_rx_lobby.rpc(Net.slot_of_peer.size(), ceili(_lobby_wait))


## Сервер: игрок ушёл — его машину снова ведёт бот, гонка продолжается.
func _on_peer_left(_id: int, slot: int) -> void:
	if slot < 0 or slot >= _cars.size():
		return
	# Машину бросил живой игрок — возвращаем её боту. Иначе она зависла бы
	# марионеткой на последнем присланном состоянии навсегда.
	var car := _cars[slot]
	car.net_make_local()
	_rx_lobby.rpc(Net.slot_of_peer.size(), maxi(ceili(_lobby_wait), 0))
	_rx_slot_taken.rpc(slot, false)
	# Ушли все — заезд некому доигрывать. Перезапускаем трассу, чтобы
	# следующая пара получила чистую гонку, а не догоняла ботов.
	if Net.slot_of_peer.is_empty() and _net_started:
		print("[net] игроков не осталось, перезапуск трассы")
		get_tree().reload_current_scene()


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


## После заезда сервер перезапускает сцену: следующая пара игроков должна
## получить чистую гонку, а не доехавшие машины на финишной прямой.
func _reset_server_after_race() -> void:
	await get_tree().create_timer(8.0).timeout
	if is_inside_tree():
		print("[net] заезд окончен, перезапуск трассы")
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
		_rx_hello.rpc_id(1, GameState.selected_car_id, Net.PROTOCOL)
		await get_tree().create_timer(1.0).timeout
		if not is_inside_tree():
			return
	if Net.my_slot < 0 and _lobby:
		_lobby.set_status("Сервер не выдал слот.
Возможно, версии игры различаются — обнови игру (git pull).
Esc — в гараж")
		_lobby.show_screen()


func _start_net_race() -> void:
	if _net_started:
		return
	_net_started = true
	print("[net] старт заезда, игроков: %d" % Net.slot_of_peer.size())
	_countdown()


## Сервер: раз в 1/SNAP_HZ рассылаем состояние всех машин.
func _server_tick(delta: float) -> void:
	_tick_lobby(delta)
	_snap_accum += delta
	if _snap_accum < 1.0 / SNAP_HZ:
		return
	_snap_accum = 0.0
	var packed := _pack_state()
	_rx_state.rpc(packed[0], packed[1])


## Ожидание второго игрока. Истекло — стартуем «по старинке»: свободный
## слот так и остаётся за ботом (см. _spawn_cars), и заезд ничем не хуже
## одиночного. Подсевший позже игрок просто заберёт машину у бота.
func _tick_lobby(delta: float) -> void:
	if _net_started or _lobby_wait < 0.0:
		return
	var before := ceili(_lobby_wait)
	_lobby_wait -= delta
	if _lobby_wait <= 0.0:
		_lobby_wait = -1.0
		print("[net] второго игрока не дождались — старт с ботами")
		_start_net_race()
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
	_rx_pstate.rpc_id(1, PackedFloat32Array([
			p.x, p.y, p.z, q.x, q.y, q.z, q.w, v.x, v.y, v.z]))
	if not _car.controls_enabled:
		return
	if Input.is_action_just_pressed("fire") \
			or Input.is_action_just_pressed("drop"):
		_rx_press.rpc_id(1)


## Снимок: на машину 10 float (позиция, кватернион, скорость) и 3 байта
## (оружие+1, живость с «призраком», значок эффекта+2). Кватернион, а не
## базис: 4 числа вместо 9 и корректная интерполяция поворота.
func _pack_state() -> Array:
	var xf := PackedFloat32Array()
	var flags := PackedByteArray()
	for c in _cars:
		var q := c.global_transform.basis.get_rotation_quaternion()
		var p := c.global_position
		var v := c.linear_velocity
		# Машину живого игрока ретранслируем КАК ПРИСЛАЛ владелец (сырое
		# последнее состояние), а не позицию серверной марионетки: та сама
		# сглаживает и экстраполирует, и пересылка её трансформа давала
		# ДВОЙНОЕ сглаживание — у второго игрока машина шла рывками. Плюс
		# linear_velocity замороженного тела и так врёт (Godot считает её
		# по сдвигу трансформа). Серверная марионетка остаётся для физики
		# самого сервера: боксы, оружие, боты.
		if c.net_role == Car.NetRole.PUPPET and c._snap_seen:
			p = c._snap_pos
			q = c._snap_rot
			v = c._snap_vel
		xf.append_array(PackedFloat32Array([
				p.x, p.y, p.z, q.x, q.y, q.z, q.w, v.x, v.y, v.z]))
		flags.append(c.weapon + 1)
		flags.append((1 if c.alive else 0) | (2 if c.is_ghost() else 0))
		flags.append(c._status_shown + 2)
	return [xf, flags]


# ── клиент → сервер ──

@rpc("any_peer", "call_remote", "reliable")
func _rx_hello(car_id: String, proto: int) -> void:
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
	if slot < 0 or slot >= _roster.size():
		return
	# Игрок приехал на своей машине — ставим её в его слот и раздаём
	# ростер всем, иначе соперник видел бы не ту модель.
	_roster[slot] = car_id
	_set_car_model(_cars[slot], car_id)
	_rx_welcome.rpc_id(id, slot, _roster, _taken_mask())
	_rx_roster.rpc(_roster)
	if _net_started:
		# Заезд уже идёт: отсчёт этот игрок пропустил, и без отдельной
		# команды он навсегда остался бы в лобби с выключенным управлением.
		_rx_race_running.rpc_id(id)
		# И прогресс всех машин: иначе подсевший считал бы круги с нуля,
		# и его HUD (круг, место) врал бы до конца заезда.
		_rx_progress.rpc_id(id, PackedFloat32Array(_progress),
				PackedInt32Array(_laps_done))
	_rx_lobby.rpc(Net.slot_of_peer.size(),
			0 if _net_started else maxi(ceili(_lobby_wait), 0))


## Клиент прислал состояние СВОЕЙ машины (она клиент-авторитетна). Сервер
## ведёт её марионеткой: _follow_snapshot экстраполирует между пакетами и
## сглаживает их неровный приход — как у марионеток на клиенте.
@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _rx_pstate(xf: PackedFloat32Array) -> void:
	if not Net.is_server() or xf.size() < 10:
		return
	var slot: int = Net.slot_of_peer.get(multiplayer.get_remote_sender_id(), -1)
	if slot < 0 or slot >= _cars.size():
		return
	var car := _cars[slot]
	if car.net_role != Car.NetRole.PUPPET:
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
			Quaternion(xf[3], xf[4], xf[5], xf[6]).normalized(), vel)


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
	if Net.is_server():
		_start_net_race()


# ── сервер → клиенты ──

## Битовая маска слотов, за которыми сидит ЖИВОЙ игрок.
func _taken_mask() -> int:
	var mask := 0
	for sl: int in Net.slot_of_peer.values():
		mask |= 1 << sl
	return mask


@rpc("authority", "call_remote", "reliable")
func _rx_welcome(slot: int, roster: PackedStringArray, taken: int) -> void:
	Net.my_slot = slot
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
	_car = car
	var cam := get_node_or_null("IsoCamera") as IsoCamera
	if cam:
		cam.target = _car
	# Маркеры: своя машина зелёная, второй ЖИВОЙ игрок — оранжевый.
	# Боты без маркера — так «реальный игрок» виден с первого взгляда.
	_attach_marker(slot)
	# Оранжевая стрелка — признак ЖИВОГО соперника, а не «второй машины».
	# Пока слот пустует, его ведёт бот, и метка над ним врала бы: игрок
	# как раз и просил отличать настоящего человека от ботов.
	var rival := 1 - slot
	_attach_marker(rival, true)
	var rival_here := (taken & (1 << rival)) != 0
	if _rival_marker:
		_rival_marker.visible = rival_here
	# На карте — те же цвета: своя точка зелёная, живой соперник оранжевый.
	if _minimap:
		_minimap.my_index = slot
		_minimap.rival_index = rival if rival_here else -1


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


@rpc("authority", "call_remote", "reliable")
func _rx_lobby(players: int, secs: int) -> void:
	if _lobby == null:
		return
	if _net_started:
		_lobby.hide_screen()
		return
	_lobby.show_screen()
	var txt := "Игроков: %d/%d" % [players, Net.PLAYER_SLOTS]
	if secs > 0:
		txt += "
Ждём второго: %d…" % secs
	_lobby.set_status(txt)


@rpc("authority", "call_remote", "reliable")
func _rx_count(txt: String) -> void:
	_net_started = true
	if _lobby:
		_lobby.hide_screen()
	if _count_label:
		_count_label.visible = true
	_pop_count(txt, Color(0.5, 1.0, 0.35) if txt == "GO!"
			else Color(1, 0.85, 0.25))
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
	_last_state_time = Time.get_ticks_msec() / 1000.0
	for i in _cars.size():
		var o := i * 10
		var f := i * 3
		if o + 9 >= xf.size() or f + 2 >= flags.size():
			break
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
			c.net_apply_snapshot(pos, rot, vel)
			c.alive = (int(flags[f + 1]) & 1) != 0
			# «Призрака» подливаем по чуть-чуть: пока сервер шлёт флаг,
			# таймер не гаснет, а кончился флаг — быстро сойдёт на нет.
			c._ghost_time = 0.3 if (int(flags[f + 1]) & 2) != 0 else 0.0
		c.weapon = int(flags[f]) - 1
		var kind := int(flags[f + 2]) - 2
		if kind >= 0:
			c.show_effect_icon(kind, 0.25)


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
		Car.NetFx.OIL:
			_car.apply_oil_slip()
		Car.NetFx.BOOST:
			_car.apply_boost()


## Слот занял или освободил живой игрок — показываем/прячем оранжевую метку.
@rpc("authority", "call_remote", "reliable")
func _rx_slot_taken(slot: int, taken: bool) -> void:
	if slot >= 0 and slot < _slot_taken.size():
		_slot_taken[slot] = taken
		_update_lobby_slots()
	if _rival_marker == null or Net.my_slot < 0 or slot == Net.my_slot:
		return
	_rival_marker.visible = taken
	if _minimap:
		_minimap.rival_index = slot if taken else -1


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
		_last_offset[i] = _track._curve.get_closest_offset(
				_cars[i].global_position)


## Клиент подсел к уже идущему заезду — отсчёта не будет, включаемся сразу.
@rpc("authority", "call_remote", "reliable")
func _rx_race_running() -> void:
	_net_started = true
	if _lobby:
		_lobby.hide_screen()
	if _count_label:
		_count_label.visible = false
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
	if i == _my_index() and car.net_role == Car.NetRole.OWNED:
		car.controls_enabled = false
		_show_finish(place)


@rpc("authority", "call_remote", "reliable")
func _rx_finish() -> void:
	_finish_race()


@rpc("authority", "call_remote", "reliable")
func _rx_weapon_fx(idx: int, kind: int, pos: Vector3, dir: Vector3) -> void:
	if idx < 0 or idx >= _cars.size():
		return
	_spawn_weapon_visual(kind, pos, dir)


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
func _spawn_weapon_visual(kind: int, pos: Vector3, dir: Vector3) -> void:
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
		Weapons.LASER:
			LaserFx.spawn(self, pos + Vector3.UP * 0.5, dir, 70.0)
		Weapons.AIRSTRIKE:
			var strike := Airstrike.new()
			strike.inert = true
			strike.track = _track
			strike.target = leader_car()
			add_child(strike)
		Weapons.BOOST:
			FlashFx.spawn(self, pos + Vector3.UP * 0.5, 1.2,
					Color(0.3, 0.9, 1.0))


## Обновить экран лобби: какие слоты заняты живыми игроками и на каких
## машинах они приехали (ростер сервер рассылает при каждом изменении).
func _update_lobby_slots() -> void:
	if _lobby == null:
		return
	for s in _slot_taken.size():
		var id := _roster[s] if s < _roster.size() else ""
		_lobby.set_slot(s, _slot_taken[s], id, s == Net.my_slot)


# ════════════════════ ЛЕНТА СОБЫТИЙ ОРУЖИЯ ════════════════════
# «Player 1 [иконка] → Player 2»: кто по кому применил оружие. Попадания
# знает только сервер (у клиентов оружие — инертная картинка) или
# оффлайн-игра, поэтому события порождаются там и рассылаются RPC.

const FEED_MAX := 5        # больше записей разом не держим
const FEED_LIFETIME := 3.4 # сколько запись висит до угасания, с


## Имя машины для ленты. Имён игроков пока нет — Player по номеру слота.
func car_label(i: int) -> String:
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


## Запись в ленту: имя, иконка оружия, стрелка, жертва. Висит
## FEED_LIFETIME и угасает; при переполнении старейшая вытесняется.
func _show_weapon_event(ai: int, vi: int, kind: int) -> void:
	if _feed_box == null:
		return
	while _feed_box.get_child_count() >= FEED_MAX:
		_feed_box.get_child(0).free()
	var entry := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.13, 0.25, 0.82)
	sb.set_corner_radius_all(10)
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
			Color(0.45, 1.0, 0.55) if idx == _my_index()
			else Color(1, 0.9, 0.45), 4)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
