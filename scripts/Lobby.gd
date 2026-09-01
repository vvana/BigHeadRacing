class_name Lobby
extends Control
## Полноэкранное сетевое лобби: тёмный «гараж», четыре подиума в ряд с
## вращающимися машинами подключённых игроков (Player 1..4), статус
## ожидания и подсказки. Экран живёт ВНУТРИ сцены Main и просто
## перекрывает её: отдельной сценой лобби быть не может — RPC адресуются
## по пути узла, и клиент обязан сидеть в /root/Main с самого рукопожатия.

## Человеческие названия машин — из экрана выбора (у CarSelect нет
## class_name, поэтому preload скрипта).
const CAR_NAMES: Dictionary = preload("res://scripts/CarSelect.gd").DISPLAY_NAMES
# Подиумов — по числу машин заезда (Net.race_size, 4..8). До 4 — один ряд
# полноразмерных панелей (4×288 + 3×14 = 1194, умещается в окно 1280);
# 5..8 — ДВА ряда панелей поменьше, иначе ряд не влезает по ширине,
# а полноразмерные два ряда — по высоте (2×330+14 = 674 при окне 720).
const SLOT_W := 288.0
const SLOT_H := 330.0
const SLOT_W2 := 250.0    # панель в двухрядной раскладке
const SLOT_H2 := 250.0
const SLOT_GAP := 14.0

var _slots := 4           # сколько подиумов построено (_ready)

var _font: FontFile
var _status: Label
var _name_labels: Array[Label] = []
var _car_labels: Array[Label] = []
var _wait_labels: Array[Label] = []
var _views: Array[SubViewportContainer] = []
var _viewports: Array[SubViewport] = []
var _turntables: Array[Node3D] = []
var _slot_ids := PackedStringArray()   # размер задаёт _ready


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_font = UiKit.font()

	# Фон — затемнённая ржавая панель из референса (сумрак гаража).
	var bg := TextureRect.new()
	bg.texture = load("res://assets/ui/garage/backdrop_rust.jpg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Заголовок — стальная плита с аварийной лентой по нижней кромке.
	var banner := UiKit.plate(self, "steel", Vector2.ZERO,
			Vector2(400, 96), false)
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.offset_left = -200
	banner.offset_right = 200
	banner.offset_top = 16
	banner.offset_bottom = 112
	UiKit.hazard(banner, Vector2(14, 96 - 22), Vector2(400 - 28, 12), 0.9)
	var title := _label(banner, "ЛОББИ", 34, Color.WHITE, 7)
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.offset_bottom = -10
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_status = _label(self, "Подключение…", 22, UiKit.YELLOW, 6)
	_status.anchor_left = 0.5
	_status.anchor_right = 0.5
	_status.offset_left = -420
	_status.offset_right = 420
	_status.offset_top = 128
	_status.offset_bottom = 196
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_slots = Net.race_size
	_slot_ids.resize(_slots)
	for s in _slots:
		_build_slot(s)

	var hint := _label(self,
			"Пробел — старт, не дожидаясь остальных  |  Esc — в гараж",
			16, Color(1, 1, 1, 0.7), 4)
	hint.anchor_left = 0.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_top = -48
	hint.offset_bottom = -16
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Двухрядная раскладка (5..8 подиумов) съедает место статуса под
	# баннером — статус переезжает ВНИЗ, а подсказка ужимается под него.
	if _slots > 4:
		_status.offset_top = 656
		_status.offset_bottom = 700
		_status.add_theme_font_size_override("font_size", 17)
		hint.offset_top = -18
		hint.offset_bottom = -2
		hint.add_theme_font_size_override("font_size", 12)


func _process(delta: float) -> void:
	if not visible:
		return
	for t in _turntables:
		t.rotation.y += delta * 0.9


func set_status(txt: String) -> void:
	_status.text = txt


## Показ/скрытие экрана. Вьюпорты подиумов на скрытом экране не рендерим:
## SubViewport с UPDATE_ALWAYS крутился бы и ПОД гонкой, впустую грея GPU.
func show_screen() -> void:
	visible = true
	for vp in _viewports:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func hide_screen() -> void:
	visible = false
	for vp in _viewports:
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Обновить слот: занят ли живым игроком, на какой машине приехал, я ли это
## и не забрал ли слот бот. Пустой слот — приглушённый «Ждём игрока…» без
## машины; слот бота показывается КАК СЛОТ ЖИВОГО ИГРОКА (ник, машина,
## оранжевый цвет): по просьбе 01.09 бот не должен отличаться от человека,
## слово «БОТ» с экрана убрано.
func set_slot(slot: int, taken: bool, car_id: String, is_me: bool,
		is_bot := false, pname := "") -> void:
	if slot < 0 or slot >= _slots:
		return
	var name_l := _name_labels[slot]
	# Имя видно, только когда в слоте кто-то есть: ники ботов приходят с
	# сервера заранее (_rx_names) и над пустым «Ждём игрока…» выдавали бы,
	# кто именно приедет ботом.
	if taken or is_bot or is_me:
		name_l.text = (pname if pname != "" else "Player %d" % (slot + 1)) \
				+ (" — ты" if is_me else "")
	else:
		name_l.text = ""
	# Цвета — те же, что у стрелок над машинами: свой зелёный, соперник
	# (живой или бот — не различить) оранжевый.
	var color := Color(1, 1, 1, 0.5)
	if is_me:
		color = UiKit.GREEN_ME
	elif taken or is_bot:
		color = UiKit.ORANGE_RIVAL
	name_l.add_theme_color_override("font_color", color)
	var show_car := taken or is_bot
	_views[slot].visible = show_car
	_wait_labels[slot].visible = not show_car
	if not show_car:
		_car_labels[slot].text = ""
		if _slot_ids[slot] != "":
			_slot_ids[slot] = ""
			for old in _turntables[slot].get_children():
				old.queue_free()
		return
	_car_labels[slot].text = CAR_NAMES.get(car_id, car_id)
	if car_id != "" and _slot_ids[slot] != car_id:
		_slot_ids[slot] = car_id
		var table := _turntables[slot]
		for old in table.get_children():
			old.queue_free()
		var model := CarModelLibrary.build(car_id, 3.2, 0.02)
		if model:
			table.add_child(model)


## Панель одного слота: имя игрока, вьюпорт с подиумом и вращающейся
## машиной (свой мир, как миниатюры на экране выбора), название машины.
func _build_slot(s: int) -> void:
	# Раскладка: один ряд до 4 подиумов, дальше два ряда (верхний полнее
	# при нечётном числе). Панели двухрядной раскладки меньше — см. консты.
	var two_rows := _slots > 4
	var w := SLOT_W2 if two_rows else SLOT_W
	var h := SLOT_H2 if two_rows else SLOT_H
	var per_row := ceili(_slots / 2.0) if two_rows else _slots
	var row := floori(s / float(per_row))
	var col := s % per_row
	var in_row := per_row if row == 0 else _slots - per_row
	var panel := UiKit.plate(self, "steel", Vector2.ZERO, Vector2(w, h))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	# Каждый ряд центрирован по горизонтали независимо.
	var total := w * in_row + SLOT_GAP * (in_row - 1)
	var x0 := -total * 0.5 + col * (w + SLOT_GAP)
	panel.offset_left = x0
	panel.offset_right = x0 + w
	var y0 := -h * 0.5 + 40.0
	if two_rows:
		# Центр сдвинут чуть выше (36), чтобы внизу осталась полоса под
		# статус и подсказку (см. _ready).
		y0 = 36.0 - h - SLOT_GAP * 0.5 if row == 0 else 36.0 + SLOT_GAP * 0.5
	panel.offset_top = y0
	panel.offset_bottom = y0 + h

	var name_l := _label(panel, "", 24, Color(1, 1, 1, 0.5), 6)
	name_l.position = Vector2(0, 10)
	name_l.size = Vector2(w, 34)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_labels.append(name_l)

	var view := SubViewportContainer.new()
	view.stretch = true
	view.position = Vector2(10, 52)
	view.size = Vector2(w - 20, h - 106)
	view.visible = false
	panel.add_child(view)
	_views.append(view)

	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	view.add_child(vp)
	_viewports.append(vp)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.9, 4.6)
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
	e.ambient_light_color = Color(0.6, 0.6, 0.7)
	e.ambient_light_energy = 0.9
	env.environment = e
	vp.add_child(env)

	var podium := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.0
	cyl.bottom_radius = 2.3
	cyl.height = 0.3
	podium.mesh = cyl
	podium.position.y = -0.15
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.16, 0.2)
	mat.metallic = 0.6
	mat.roughness = 0.35
	podium.material_override = mat
	vp.add_child(podium)

	var table := Node3D.new()
	table.name = "TurnTable"
	vp.add_child(table)
	_turntables.append(table)

	var car_l := _label(panel, "", 18, Color(1, 0.9, 0.45), 5)
	car_l.position = Vector2(0, h - 44)
	car_l.size = Vector2(w, 30)
	car_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_car_labels.append(car_l)

	var wait_l := _label(panel, "Ждём игрока…", 20, Color(1, 1, 1, 0.45), 5)
	wait_l.position = Vector2(0, h * 0.5 - 16)
	wait_l.size = Vector2(w, 32)
	wait_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait_labels.append(wait_l)


func _label(parent: Node, txt: String, size_px: int, color: Color,
		outline: int) -> Label:
	var l := Label.new()
	l.text = txt
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", UiKit.INK)
	parent.add_child(l)
	return l
