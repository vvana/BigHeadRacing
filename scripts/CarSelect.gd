extends Node3D
## Экран выбора машины: слева тачка крутится на подиуме, справа — сетка
## миниатюр всех машин (рендерятся в текстуры один раз, кэш в GameState).
## Управление: ←→ / A D — листать, ↑↓ — по рядам сетки, мышь — клик по
## ячейке (повторный клик по выбранной — старт), Enter/Space — в гонку.

## Человеческие названия машин (ID → имя на экране).
const DISPLAY_NAMES := {
	"stock": "Stock Car", "rd": "RD-04", "sharky": "Sharkruiser",
	"invader": "Invader", "arachno": "Arachnorod", "dk": "Drift King",
	"dakar": "Dakar", "jt": "Jet Threat",
	"24seven": "24/Seven", "backdraft": "Backdraft", "ballistik": "Ballistik",
	"corvette": "Corvette", "coupe": "Coupe", "deora": "Deora II",
	"elcamino": "El Camino", "f150": "Ford F-150",
	"irocfirebird": "Firebird IROC", "krazy8s": "Krazy 8s",
	"megaduty": "Mega-Duty", "motocrossed": "Moto-Crossed",
	"muscletone": "Muscletone", "nomad": "Nomad",
	"powerocket": "Power Rocket", "powerpipes": "Power Pipes",
	"powerpistons": "Power Pistons", "rageous": "Rageous",
	"redbaron": "Red Baron", "roadrocket": "Road Rocket",
	"roadrunner": "Road Runner", "sidedraft": "Sidedraft",
	"silverbullet": "Silver Bullet", "slingshot": "Slingshot",
	"sweet16": "Sweet 16 II", "switchback": "Switchback",
	"tbird": "'57 T-Bird", "thunderbolt": "Thunderbolt",
	"toyotarsc": "Toyota RSC", "twinmill": "Twin Mill",
	"vulture": "Vulture", "wildthing": "Wild Thing", "zotic": "Zotic",
}

const GRID_COLUMNS := 5
const THUMB_SIZE := Vector2(104, 78)

var _index := 0
var _turntable: Node3D
var _model: Node3D
var _name_label: Label
var _count_label: Label
var _buttons: Array[Button] = []
var _host_edit: LineEdit          # адрес сетевого сервера
var _net_status: Label
var _scroll: ScrollContainer
var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat
var _ui_font: FontFile  # Russo One — индустриальный, с кириллицей


func _ready() -> void:
	_index = maxi(0, CarModelLibrary.CAR_IDS.find(GameState.selected_car_id))
	_setup_environment()
	_setup_podium()
	_setup_hud()
	_set_index(_index)
	_generate_thumbs()


func _process(delta: float) -> void:
	_turntable.rotation.y += delta * 0.9

	var total := CarModelLibrary.CAR_IDS.size()
	if Input.is_action_just_pressed("ui_right") \
			or Input.is_action_just_pressed("steer_right"):
		_set_index((_index + 1) % total)
	elif Input.is_action_just_pressed("ui_left") \
			or Input.is_action_just_pressed("steer_left"):
		_set_index((_index - 1 + total) % total)
	elif Input.is_action_just_pressed("ui_down"):
		_set_index(mini(_index + GRID_COLUMNS, total - 1))
	elif Input.is_action_just_pressed("ui_up"):
		_set_index(maxi(_index - GRID_COLUMNS, 0))
	elif Input.is_action_just_pressed("ui_accept"):
		_start_race()


func _start_race() -> void:
	Net.leave()   # вдруг остались хвосты прошлого сетевого заезда
	GameState.selected_car_id = CarModelLibrary.CAR_IDS[_index]
	# Трасса на заезд — случайная из доступных.
	GameState.track_kind = TrackBuilder.pick_random_kind()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


## Панель сетевой игры: адрес сервера и кнопка подключения. Сама гонка
## начнётся, когда сервер подтвердит соединение (сигнал Net.joined).
func _build_net_ui(canvas: Node) -> void:
	_net_status = Label.new()
	_net_status.text = ""
	if _ui_font:
		_net_status.add_theme_font_override("font", _ui_font)
	_net_status.add_theme_font_size_override("font_size", 18)
	_net_status.add_theme_constant_override("outline_size", 5)
	_net_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_net_status.add_theme_color_override("font_color", UiKit.YELLOW)
	canvas.add_child(_net_status)
	# Панель жмётся к левой половине экрана: справа от 685 px начинается
	# сетка машин, и на анкере 0.75 кнопка уезжала ПОД неё — в кадре её
	# было не видно вовсе (поймано скриншот-стендом ScreenshotSelect).
	_net_status.anchor_left = 0.0
	_net_status.anchor_right = 0.0
	_net_status.anchor_top = 1.0
	_net_status.anchor_bottom = 1.0
	_net_status.offset_left = 450
	_net_status.offset_right = 690
	_net_status.offset_top = -196
	_net_status.offset_bottom = -172
	_net_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_host_edit = LineEdit.new()
	_host_edit.text = "%s:%d" % [Net.host, Net.port]
	_host_edit.placeholder_text = "адрес:порт"
	_host_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _ui_font:
		_host_edit.add_theme_font_override("font", _ui_font)
	_host_edit.add_theme_font_size_override("font_size", 20)
	# Стальная рамка вместо системной серой.
	var edit_sb := UiKit.steel_box(6, 0.95)
	edit_sb.set_content_margin_all(6)
	for state in ["normal", "focus"]:
		_host_edit.add_theme_stylebox_override(state, edit_sb)
	_host_edit.add_theme_color_override("font_color", Color.WHITE)
	_host_edit.add_theme_color_override("caret_color", UiKit.YELLOW)
	_host_edit.anchor_left = 0.0
	_host_edit.anchor_right = 0.0
	_host_edit.anchor_top = 1.0
	_host_edit.anchor_bottom = 1.0
	_host_edit.offset_left = 470
	_host_edit.offset_right = 670
	_host_edit.offset_top = -166
	_host_edit.offset_bottom = -130
	canvas.add_child(_host_edit)

	var net_btn := Button.new()
	net_btn.text = "ПО СЕТИ"
	UiKit.style_button(net_btn, "teal", 26)
	net_btn.anchor_left = 0.0
	net_btn.anchor_right = 0.0
	net_btn.anchor_top = 1.0
	net_btn.anchor_bottom = 1.0
	net_btn.offset_left = 460
	net_btn.offset_right = 680
	net_btn.offset_top = -122
	net_btn.offset_bottom = -52
	net_btn.pressed.connect(_join_pressed)
	canvas.add_child(net_btn)

	Net.joined.connect(_on_joined)
	Net.join_failed.connect(_on_join_failed)


func _join_pressed() -> void:
	var text := _host_edit.text.strip_edges()
	var addr := text
	var port := Net.PORT
	# Порт можно дописать через двоеточие: 1.2.3.4:9977. Режем ПОСЛЕДНЕЕ
	# двоеточие — в IPv6-адресе их много.
	var colon := text.rfind(":")
	if colon > 0:
		addr = text.substr(0, colon)
		port = int(text.substr(colon + 1))
		if port <= 0:
			port = Net.PORT
	if addr.is_empty():
		_net_status.text = "Укажите адрес сервера"
		return
	GameState.selected_car_id = CarModelLibrary.CAR_IDS[_index]
	_net_status.text = "Подключение к %s:%d…" % [addr, port]
	if Net.join_server(addr, port):
		_watch_connect_timeout()


## ENet сам по себе может молчать очень долго, поэтому ограничиваем
## ожидание вручную: не ответил за CONNECT_TIMEOUT — рвём и говорим об этом,
## чтобы не сидеть на экране «Подключение…» неизвестно сколько.
func _watch_connect_timeout() -> void:
	await get_tree().create_timer(Net.CONNECT_TIMEOUT).timeout
	if not is_inside_tree() or not Net.is_client():
		return
	var peer := multiplayer.multiplayer_peer
	if peer != null and peer.get_connection_status() 			== MultiplayerPeer.CONNECTION_CONNECTED:
		return
	Net.leave()
	if _net_status:
		_net_status.text = "Сервер не ответил за %d с — можно играть с ботами" 				% int(Net.CONNECT_TIMEOUT)


func _on_joined() -> void:
	# По сети вид трассы диктует сервер (_rx_track): строим классику, а
	# если сервер выбрал другую — Main перезагрузит сцену с нужной.
	GameState.track_kind = ""
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_join_failed(reason: String) -> void:
	if _net_status:
		_net_status.text = reason


func _set_index(i: int) -> void:
	var prev := _index
	_index = i
	if _model:
		_model.queue_free()
	var id: String = CarModelLibrary.CAR_IDS[_index]
	_model = CarModelLibrary.build(id, 3.2, 0.02)
	if _model:
		_turntable.add_child(_model)
	_name_label.text = DISPLAY_NAMES.get(id, id)
	_count_label.text = "%d / %d" % [_index + 1, CarModelLibrary.CAR_IDS.size()]
	# Подсветка ячейки в сетке.
	if _buttons.size() > prev:
		_apply_style(_buttons[prev], _style_normal)
	if _buttons.size() > _index:
		_apply_style(_buttons[_index], _style_selected)
		_scroll.ensure_control_visible(_buttons[_index])


func _on_cell_pressed(i: int) -> void:
	if i == _index:
		_start_race()  # повторный клик по выбранной — старт
	else:
		_set_index(i)


const THUMB_CACHE_DIR := "user://thumbs"
const THUMB_BATCH := 8  # сколько машин рендерим за один кадр

## Раздаёт миниатюры кнопкам: из памяти → с диска → рендер недостающих
## пачками по THUMB_BATCH вьюпортов за кадр (и сохранение в user://thumbs).
func _generate_thumbs() -> void:
	DirAccess.make_dir_recursive_absolute(THUMB_CACHE_DIR)
	var missing: Array[int] = []
	for i in CarModelLibrary.CAR_IDS.size():
		var id: String = CarModelLibrary.CAR_IDS[i]
		if GameState.car_thumbs.has(id):
			_buttons[i].icon = GameState.car_thumbs[id]
			continue
		var png_path := "%s/%s.png" % [THUMB_CACHE_DIR, id]
		if FileAccess.file_exists(png_path):
			var img := Image.new()
			if img.load(png_path) == OK:
				var tex := ImageTexture.create_from_image(img)
				GameState.car_thumbs[id] = tex
				_buttons[i].icon = tex
				continue
		missing.append(i)
	if missing.is_empty():
		return

	# Пул вьюпортов — по одному на машину в пачке.
	var pool: Array[Dictionary] = []
	for k in mini(THUMB_BATCH, missing.size()):
		pool.append(_make_thumb_viewport())

	for start in range(0, missing.size(), THUMB_BATCH):
		var batch: Array[int] = missing.slice(start, start + THUMB_BATCH)
		for k in batch.size():
			var vp_info := pool[k]
			var holder: Node3D = vp_info["holder"]
			for old in holder.get_children():
				old.free()
			var m := CarModelLibrary.build(
					CarModelLibrary.CAR_IDS[batch[k]], 3.2, 0.0)
			if m:
				holder.add_child(m)
			(vp_info["vp"] as SubViewport).render_target_update_mode = \
					SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return  # сцену сменили во время генерации
		for k in batch.size():
			var i: int = batch[k]
			var id: String = CarModelLibrary.CAR_IDS[i]
			var img := (pool[k]["vp"] as SubViewport).get_texture().get_image()
			img.save_png("%s/%s.png" % [THUMB_CACHE_DIR, id])
			var tex := ImageTexture.create_from_image(img)
			GameState.car_thumbs[id] = tex
			_buttons[i].icon = tex
	for vp_info in pool:
		(vp_info["vp"] as SubViewport).queue_free()


## Вьюпорт с камерой/светом/столиком для рендера одной миниатюры.
func _make_thumb_viewport() -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(208, 156)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.9, 4.4)
	cam.rotation_degrees = Vector3(-16, 0, 0)
	cam.fov = 45
	vp.add_child(cam)
	cam.current = true

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.3
	vp.add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.8)
	e.ambient_light_energy = 0.9
	env.environment = e
	vp.add_child(env)

	var holder := Node3D.new()
	holder.rotation.y = deg_to_rad(150)  # 3/4-ракурс
	vp.add_child(holder)
	return {"vp": vp, "holder": holder}


func _setup_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.06, 0.1)  # тёмный «гараж»
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.6)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -35, 0)
	key.light_energy = 1.3
	key.shadow_enabled = true
	add_child(key)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-30, 140, 0)
	rim.light_energy = 0.5
	rim.light_color = Color(0.7, 0.8, 1.0)
	add_child(rim)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 2.0, 4.6)
	cam.rotation_degrees = Vector3(-14, 0, 0)
	cam.fov = 50
	# Сетка занимает правые ~600px из 1280 → видимая зона 0..680,
	# её центр = 0.266 ширины экрана. Сдвиг кадра: (0.5-0.266) от ширины
	# фрустума на дистанции до подиума (~4.8 м) ≈ 1.85 м.
	cam.h_offset = 1.85
	add_child(cam)
	cam.make_current()


func _setup_podium() -> void:
	var podium := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 2.2
	mesh.bottom_radius = 2.5
	mesh.height = 0.35
	podium.mesh = mesh
	podium.position.y = -0.175
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.16, 0.2)
	mat.metallic = 0.6
	mat.roughness = 0.35
	podium.material_override = mat
	add_child(podium)

	_turntable = Node3D.new()
	_turntable.name = "TurnTable"
	add_child(_turntable)


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_ui_font = UiKit.font()

	# Заголовок — белая эмалевая табличка с чернильным текстом и
	# аварийной лентой по нижней кромке («гаражный» стиль).
	var banner := UiKit.plate(canvas, "white", Vector2.ZERO,
			Vector2(420, 92), false)
	banner.anchor_left = 0.25
	banner.anchor_right = 0.25
	banner.offset_left = -210
	banner.offset_right = 210
	banner.offset_top = 14
	banner.offset_bottom = 106
	UiKit.hazard(banner, Vector2(14, 92 - 22), Vector2(420 - 28, 12), 0.95)
	var title := Label.new()
	title.text = "ВЫБОР МАШИНЫ"
	if _ui_font:
		title.add_theme_font_override("font", _ui_font)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiKit.INK)
	banner.add_child(title)
	# and_offsets: обычный set_anchors_preset сохранил бы крошечный размер.
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.offset_bottom = -10
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Уровень и опыт профиля — жёлтая строка под заголовком. Опыт даётся
	# за место на финише (GameState), за уровни дальше откроем «штуки».
	var info: Vector3i = GameState.level_info()
	var xp_label := Label.new()
	xp_label.text = "УРОВЕНЬ %d   ·   ОПЫТ %d / %d" % [info.x, info.y, info.z]
	if _ui_font:
		xp_label.add_theme_font_override("font", _ui_font)
	xp_label.add_theme_font_size_override("font_size", 17)
	xp_label.add_theme_color_override("font_color", UiKit.YELLOW)
	xp_label.add_theme_constant_override("outline_size", 5)
	xp_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	xp_label.anchor_left = 0.25
	xp_label.anchor_right = 0.25
	xp_label.offset_left = -210
	xp_label.offset_right = 210
	xp_label.offset_top = 112
	xp_label.offset_bottom = 138
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	canvas.add_child(xp_label)

	# Имя машины — на стальной табличке.
	var name_panel := UiKit.plate(canvas, "steel", Vector2.ZERO,
			Vector2(380, 70))
	name_panel.anchor_left = 0.25
	name_panel.anchor_right = 0.25
	name_panel.anchor_top = 1.0
	name_panel.anchor_bottom = 1.0
	name_panel.offset_left = -190
	name_panel.offset_right = 190
	name_panel.offset_top = -216
	name_panel.offset_bottom = -146
	_name_label = Label.new()
	if _ui_font:
		_name_label.add_theme_font_override("font", _ui_font)
	_name_label.add_theme_font_size_override("font_size", 30)
	_name_label.add_theme_constant_override("outline_size", 6)
	_name_label.add_theme_color_override("font_outline_color", UiKit.INK)
	name_panel.add_child(_name_label)
	_name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_count_label = Label.new()
	if _ui_font:
		_count_label.add_theme_font_override("font", _ui_font)
	_count_label.add_theme_font_size_override("font_size", 16)
	_count_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_count_label.anchor_right = 0.5
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.position.y = -144
	_count_label.modulate = Color(1, 1, 1, 0.7)
	canvas.add_child(_count_label)

	# Стрелки листания по бокам подиума — оранжевые таблички.
	_make_arrow(canvas, "res://assets/ui/garage/arrow_l.png", 0.06,
			func() -> void: _set_index(
					(_index - 1 + CarModelLibrary.CAR_IDS.size())
					% CarModelLibrary.CAR_IDS.size()))
	_make_arrow(canvas, "res://assets/ui/garage/arrow_r.png", 0.44,
			func() -> void: _set_index(
					(_index + 1) % CarModelLibrary.CAR_IDS.size()))

	# Кнопка «СТАРТ» — оранжевая эмалевая табличка (как START референса).
	var start_btn := Button.new()
	start_btn.text = "СТАРТ"
	UiKit.style_button(start_btn, "orange", 30)
	start_btn.anchor_left = 0.25
	start_btn.anchor_right = 0.25
	start_btn.anchor_top = 1.0
	start_btn.anchor_bottom = 1.0
	start_btn.offset_left = -130
	start_btn.offset_right = 130
	start_btn.offset_top = -122
	start_btn.offset_bottom = -52
	start_btn.pressed.connect(_start_race)
	canvas.add_child(start_btn)
	_build_net_ui(canvas)

	var help := Label.new()
	help.text = "←→↑↓ / AD — выбор  |  клик — выбрать, ещё раз — старт  |  Enter — в гонку"
	if _ui_font:
		help.add_theme_font_override("font", _ui_font)
	help.add_theme_font_size_override("font_size", 15)
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.anchor_right = 0.5
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.position.y = -36
	help.modulate = Color(1, 1, 1, 0.7)
	canvas.add_child(help)

	_setup_grid(canvas)


## Мультяшная кнопка-стрелка листания (позиция — доля ширины экрана).
func _make_arrow(canvas: CanvasLayer, tex_path: String, anchor_x: float,
		on_press: Callable) -> void:
	var btn := TextureButton.new()
	btn.texture_normal = load(tex_path)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.focus_mode = Control.FOCUS_NONE
	btn.anchor_left = anchor_x
	btn.anchor_right = anchor_x
	btn.anchor_top = 0.5
	btn.anchor_bottom = 0.5
	btn.offset_left = 0
	btn.offset_right = 76
	btn.offset_top = -38
	btn.offset_bottom = 38
	btn.modulate = Color(1, 1, 1, 0.92)
	btn.pressed.connect(on_press)
	btn.button_down.connect(func() -> void: btn.modulate = Color(0.75, 0.75, 0.75))
	btn.button_up.connect(func() -> void: btn.modulate = Color(1, 1, 1, 0.92))
	canvas.add_child(btn)


## Правая половина: прокручиваемая сетка миниатюр всех машин.
func _setup_grid(canvas: CanvasLayer) -> void:
	_style_normal = UiKit.steel_box()
	_style_selected = UiKit.steel_box()
	_style_selected.bg_color = Color(0.30, 0.27, 0.14, 0.95)
	_style_selected.set_border_width_all(3)
	_style_selected.border_color = UiKit.YELLOW

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(UiKit.INK.r, UiKit.INK.g, UiKit.INK.b, 0.88)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(10)
	panel_style.set_border_width_all(1)
	panel_style.border_color = Color(UiKit.RIM.r, UiKit.RIM.g,
			UiKit.RIM.b, 0.45)
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -600
	panel.offset_top = 20
	panel.offset_bottom = -20
	panel.offset_right = -16
	canvas.add_child(panel)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_scroll)

	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(grid)

	for i in CarModelLibrary.CAR_IDS.size():
		var id: String = CarModelLibrary.CAR_IDS[i]
		var btn := Button.new()
		btn.custom_minimum_size = THUMB_SIZE
		btn.expand_icon = true
		btn.tooltip_text = DISPLAY_NAMES.get(id, id)
		btn.focus_mode = Control.FOCUS_NONE
		_apply_style(btn, _style_normal)
		btn.pressed.connect(_on_cell_pressed.bind(i))
		grid.add_child(btn)
		_buttons.append(btn)


func _apply_style(btn: Button, style: StyleBoxFlat) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, style)
