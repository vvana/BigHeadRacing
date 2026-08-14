extends Node3D
## Гонка в духе Rock'n'Roll Racing: трасса, игрок + 3 ИИ-соперника,
## отсчёт 3-2-1-GO, 4 круга, позиции, «резинка» ИИ, HUD (скорость, круг,
## позиция, HP, боезапас), финиш. Всё собирается из кода.

const LAPS := 4
const AI_COUNT := 3
# Машина на полотне отстоит от оси максимум на ~6.2 м (полуширина трассы 7
# минус полукорпус), поэтому всё, что дальше 7.5 м, — уже за ограждением.
const OFFTRACK_DIST := TrackBuilder.TRACK_HALF_WIDTH + 0.5
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
var _finished := false

var _player_marker: Node3D          # стрелка-указатель над машиной игрока
var _marker_time := 0.0

var _speed_label: Label
var _lap_label: Label
var _pos_label: Label
var _ammo_label: Label
var _hp_fill: ColorRect
var _warn_label: Label
var _center_label: Label


func _ready() -> void:
	_setup_environment()

	_track = TrackBuilder.new()
	_track.name = "Track"
	add_child(_track)

	_spawn_cars()

	var cam := IsoCamera.new()
	cam.name = "IsoCamera"
	cam.target = _car
	add_child(cam)
	cam.make_current()

	_setup_hud()
	_countdown()


## Стартовая решётка: 2 колонны, игрок — впереди слева.
func _spawn_cars() -> void:
	var st := _track.start_transform()
	var dir := -st.basis.z
	var right := st.basis.x
	var ai_ids := _pick_ai_ids()

	for i in AI_COUNT + 1:
		var is_p := i == 0
		var car := Car.new()
		car.is_player = is_p
		car.name = "PlayerCar" if is_p else "AiCar%d" % i
		car.track = _track
		if not is_p:
			# Лёгкий разброс характеристик, чтобы ИИ не ехали строем.
			car.max_speed += randf_range(-1.2, 1.2)
			car.engine_power += randf_range(-8.0, 8.0)

		var id: String = GameState.selected_car_id if is_p else ai_ids[i - 1]
		var model := CarModelLibrary.build(id)
		if model:
			car.add_child(model)
			car.collect_wheels(model)
		else:
			_build_placeholder_visual(car)

		var row := i / 2
		var col := i % 2
		var pos: Vector3 = st.origin - dir * (2.0 + row * 5.0) \
				+ right * (2.2 if col == 1 else -2.2)
		car.transform = Transform3D(st.basis, pos)
		add_child(car)

		_cars.append(car)
		_progress.append(0.0)
		_laps_done.append(0)
		_offtrack_time.append(0.0)
		_flip_time.append(0.0)
		_stall_time.append(0.0)
		_last_offset.append(0.0)

	_car = _cars[0]
	_player_marker = _build_player_marker()
	_car.add_child(_player_marker)
	for i in _cars.size():
		_last_offset[i] = _track._curve.get_closest_offset(
				_cars[i].global_position)


## Случайные машины соперников (не совпадающие с машиной игрока).
func _pick_ai_ids() -> Array[String]:
	var pool := CarModelLibrary.CAR_IDS.duplicate()
	pool.shuffle()
	var res: Array[String] = []
	for id: String in pool:
		if id != GameState.selected_car_id:
			res.append(id)
		if res.size() == AI_COUNT:
			break
	return res


func _countdown() -> void:
	_center_label.visible = true
	for txt in ["3", "2", "1"]:
		_center_label.text = txt
		await get_tree().create_timer(0.8).timeout
		if not is_inside_tree():
			return
	_center_label.text = "GO!"
	for c in _cars:
		c.controls_enabled = true
	await get_tree().create_timer(0.7).timeout
	if is_inside_tree():
		_center_label.visible = false


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
			_cars[i].refill_ammo()
			if i == 0 and lap >= LAPS and not _finished:
				_finish_race()

	# «Резинка»: отстающий ИИ едет бодрее, убежавший — спокойнее.
	for i in range(1, _cars.size()):
		var diff := _progress[0] - _progress[i]
		_cars[i].ai_rubber = clampf(1.0 + diff / 120.0, 0.85, 1.3)


## Маркер игрока: ярко-жёлтая стрелка (конус остриём вниз) над машиной.
## Материал unshaded + emission — видна при любом освещении.
func _build_player_marker() -> Node3D:
	var marker := MeshInstance3D.new()
	marker.name = "PlayerMarker"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.34
	cone.bottom_radius = 0.0   # остриё вниз — указывает на машину
	cone.height = 0.6
	marker.mesh = cone
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.05)
	marker.material_override = mat
	marker.position = Vector3(0, 2.4, 0)
	return marker


func _process(delta: float) -> void:
	if _player_marker:
		# Лёгкое покачивание по высоте (без вращения — оно отвлекало).
		_marker_time += delta
		_player_marker.position.y = 2.4 + 0.12 * sin(_marker_time * 3.0)
	if _car:
		_speed_label.text = "%d км/ч" % int(_car.speed_kmh())
		_ammo_label.text = "Снаряды %d   Мины %d" % [_car.ammo, _car.mines]
		var ratio := _car.hp / _car.max_hp
		_hp_fill.size.x = 180.0 * clampf(ratio, 0.0, 1.0)
		if ratio > 0.5:
			_hp_fill.color = Color(0.2, 0.85, 0.3)
		elif ratio > 0.25:
			_hp_fill.color = Color(0.95, 0.8, 0.15)
		else:
			_hp_fill.color = Color(0.9, 0.2, 0.15)
		_lap_label.text = "Круг %d/%d" % [clampi(_laps_done[0] + 1, 1, LAPS), LAPS]
		_pos_label.text = "Позиция %d/%d" % [_player_place(), _cars.size()]

	# Ввод опрашиваем напрямую (как езду в Car), а не через события —
	# надёжнее: событие может не дойти до _unhandled_input.
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/CarSelect.tscn")
		return
	if _finished and Input.is_action_just_pressed("ui_accept"):
		get_tree().change_scene_to_file("res://scenes/CarSelect.tscn")
		return
	if Input.is_action_just_pressed("respawn"):
		_respawn_car(0)
	_check_recovery(delta)


func _player_place() -> int:
	var place := 1
	for j in range(1, _cars.size()):
		if _progress[j] > _progress[0]:
			place += 1
	return place


func _finish_race() -> void:
	_finished = true
	_car.controls_enabled = false
	_center_label.text = "ФИНИШ! Место: %d из %d\nEnter — в гараж" \
			% [_player_place(), _cars.size()]
	_center_label.visible = true


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
	if i == 0:
		_warn_label.visible = false


## Автовозврат на трассу по трём причинам: вылет за ограждение, переворот
## на крышу, длительное застревание. Игроку показываем, что происходит.
func _check_recovery(delta: float) -> void:
	for i in _cars.size():
		var car := _cars[i]
		if not car.alive:
			_offtrack_time[i] = 0.0
			_flip_time[i] = 0.0
			_stall_time[i] = 0.0
			continue

		var reason := ""
		var left := 0.0

		var dist := _track.distance_from_axis(car.global_position)
		if dist > OFFTRACK_DIST:
			_offtrack_time[i] += delta
			var wait := OFFTRACK_WAIT_PLAYER if i == 0 else OFFTRACK_WAIT_AI
			reason = "Вне трассы!"
			left = wait - _offtrack_time[i]
			if _offtrack_time[i] >= wait:
				_respawn_car(i)
				continue
		else:
			_offtrack_time[i] = 0.0

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

		if i == 0:
			if reason == "":
				_warn_label.visible = false
			else:
				_warn_label.text = "%s Возврат через %d…" \
						% [reason, maxi(1, ceili(left))]
				_warn_label.visible = true


func _setup_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.35, 0.18, 0.12)  # красноватое небо чужой планеты
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.5, 0.45)
	e.ambient_light_energy = 0.7
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


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	_speed_label = Label.new()
	_speed_label.position = Vector2(20, 14)
	_speed_label.add_theme_font_size_override("font_size", 30)
	canvas.add_child(_speed_label)

	_lap_label = Label.new()
	_lap_label.position = Vector2(20, 54)
	_lap_label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(_lap_label)

	_pos_label = Label.new()
	_pos_label.position = Vector2(20, 80)
	_pos_label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(_pos_label)

	var hp_bg := ColorRect.new()
	hp_bg.position = Vector2(20, 110)
	hp_bg.size = Vector2(184, 16)
	hp_bg.color = Color(0, 0, 0, 0.55)
	canvas.add_child(hp_bg)
	_hp_fill = ColorRect.new()
	_hp_fill.position = Vector2(2, 2)
	_hp_fill.size = Vector2(180, 12)
	_hp_fill.color = Color(0.2, 0.85, 0.3)
	hp_bg.add_child(_hp_fill)

	_ammo_label = Label.new()
	_ammo_label.position = Vector2(20, 132)
	_ammo_label.add_theme_font_size_override("font_size", 17)
	canvas.add_child(_ammo_label)

	_warn_label = Label.new()
	_warn_label.add_theme_font_size_override("font_size", 28)
	_warn_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn_label.position.y = 100
	_warn_label.modulate = Color(1.0, 0.85, 0.2)
	_warn_label.visible = false
	canvas.add_child(_warn_label)

	_center_label = Label.new()
	_center_label.add_theme_font_size_override("font_size", 56)
	_center_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center_label.visible = false
	canvas.add_child(_center_label)

	var help := Label.new()
	help.text = "WASD — движение | Space — ручник | Shift — прыжок | " \
			+ "Ctrl/J — огонь | L/C — мина | R — на трассу | Esc — меню"
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.position = Vector2(20, -30)
	help.add_theme_font_size_override("font_size", 14)
	help.modulate = Color(1, 1, 1, 0.7)
	canvas.add_child(help)
