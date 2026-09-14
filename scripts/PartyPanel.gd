class_name PartyPanel
extends PanelContainer
## КОМАНДА ДРУЗЕЙ в гараже (09.09): на месте доски «АВТОПАРК», как
## WeaponShopPanel. Поиск игрока по имени (имена единые — Social),
## приглашение, состав команды с машинами на подиумах (как в лобби),
## кнопки «ГОТОВ» и «ВЫЙТИ». Все данные — от сервера друзей (Social):
## панель только рисует ростер и шлёт нажатия.

signal closed

const CAR_NAMES: Dictionary = preload("res://scripts/CarSelect.gd").DISPLAY_NAMES
const CARD_W := 128.0
const CARD_H := 150.0
const RESULTS_MAX := 6
const FRIENDS_POLL := 5.0     # секунд между опросами статусов друзей
# (список друзей прокручивается вместе со всей серединой панели, 11.09)
const FRIEND_ROW_H := 28.0

var _font: FontFile
var _box: VBoxContainer
var _status: Label
var _search: LineEdit
var _results: VBoxContainer
var _friends_title: Label
var _mid: ScrollContainer      # прокручиваемая середина панели (11.09)
var _sec_find: VBoxContainer    # секция «друзья + поиск»
var _sec_members: VBoxContainer # секция «состав команды»
var _friends_box: VBoxContainer
var _friend_state := {}       # имя в нижнем регистре → запись статуса (lookup)
var _friends_poll := 0.0
var _members_title: Label
var _grid: GridContainer
var _ready_btn: Button
var _leave_btn: Button
var _notice: Label
var _notice_time := 0.0
var _cards := {}          # uid → {root, table, car, name_l, state_l}
var _last_items: Array = []


func _ready() -> void:
	_font = UiKit.font()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.19, 0.21, 0.24, 0.96)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(UiKit.RIM.r, UiKit.RIM.g, UiKit.RIM.b, 0.45)
	add_theme_stylebox_override("panel", style)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	add_child(_box)
	_build()
	visible = false
	Social.connected_changed.connect(func(_on: bool) -> void: _refresh())
	Social.welcome.connect(func(_ok: bool, _r: String) -> void: _refresh())
	Social.name_result.connect(func(_ok: bool, _n: String, _r: String) -> void:
		_refresh())
	Social.party_changed.connect(_refresh)
	Social.outdated_changed.connect(_refresh)   # «обновите игру» (14.09)
	Social.search_result.connect(_on_results)
	Social.friends_result.connect(_on_friends)
	Social.notice.connect(_on_notice)


func _process(delta: float) -> void:
	if not visible:
		return
	for uid in _cards:
		(_cards[uid].table as Node3D).rotation.y += delta * 0.9
	# Статусы друзей (в сети / в заезде) опрашиваем, пока панель открыта.
	_friends_poll -= delta
	if _friends_poll <= 0.0:
		_friends_poll = FRIENDS_POLL
		_poll_friends()
	if _notice_time > 0.0:
		_notice_time -= delta
		if _notice_time <= 0.0:
			_notice.text = ""


## focus_search — дать фокус полю «имя друга» (на столе удобно сразу
## печатать). На телефоне фокус в LineEdit поднимает экранную клавиатуру,
## поэтому там поле фокус не получает никогда (жалоба 14.09: после
## «ПРИНЯТЬ» приглашение открывалась панель — и вылезала клавиатура).
## После «ПРИНЯТЬ» и на столе фокус не даём: игрок вступает в команду,
## а не ищет друга (ответ сервера ещё не пришёл, in_party() пока ложно).
func open(focus_search: bool = true) -> void:
	visible = true
	_refresh()
	_friends_poll = FRIENDS_POLL
	_poll_friends()
	if focus_search and not TouchControls.wanted() 			and not Social.in_party() and _search:
		_search.call_deferred("grab_focus")


func close() -> void:
	visible = false
	closed.emit()


func _build() -> void:
	# Шапка: заголовок, «ЗАКРЫТЬ».
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_box.add_child(head)
	var title := _label("КОМАНДА ДРУЗЕЙ", 20, UiKit.YELLOW)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "ЗАКРЫТЬ"
	UiKit.style_button(close_btn, "steel", 14)
	close_btn.custom_minimum_size = Vector2(110, 34)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	_status = _label("", 12, Color(1, 1, 1, 0.6))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_status)
	_box.add_child(HSeparator.new())

	# СЕРЕДИНА ПАНЕЛИ ПРОКРУЧИВАЕТСЯ (11.09): друзья, поиск и карточки
	# состава вместе перерастали доску (замер стендом: при команде из 4 —
	# 741 px в отведённых 594, при 8 — 919), панель тянулась вниз, и ряд
	# «ГОТОВ»/«ВЫЙТИ» уходил за нижнюю кромку экрана. Теперь всё, что
	# может расти, живёт в ScrollContainer: он отдаёт ровно столько,
	# сколько осталось от доски, а кнопки прибиты к её низу и видны всегда.
	_mid = ScrollContainer.new()
	_mid.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box.add_child(_mid)
	var mid_box := VBoxContainer.new()
	mid_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_box.add_theme_constant_override("separation", 6)
	_mid.add_child(mid_box)

	# Две секции середины: «кого позвать» (друзья + поиск) и «состав».
	# Порядок меняется в _refresh: пока команды нет, сверху поиск, а в
	# команде сверху состав — иначе карточки товарищей оказывались под
	# списком друзей и их приходилось прокручивать.
	_sec_find = VBoxContainer.new()
	_sec_find.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sec_find.add_theme_constant_override("separation", 6)
	mid_box.add_child(_sec_find)
	_sec_members = VBoxContainer.new()
	_sec_members.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sec_members.add_theme_constant_override("separation", 6)
	mid_box.add_child(_sec_members)

	# Друзья (09.09, вечер): кого звал в команду или с кем в ней был —
	# списком, с кнопкой «ПРИГЛАСИТЬ»: заново искать по имени не надо.
	_friends_title = _label("ДРУЗЬЯ", 15, Color.WHITE)
	_sec_find.add_child(_friends_title)
	# Строки компактные (плоские кнопки, ~FRIEND_ROW_H px). Своей прокрутки
	# у списка больше нет — она была вложенной, и палец на телефоне попадал
	# то в список, то в панель. Прокручивается вся середина целиком (_mid),
	# а список показывает всех друзей (их не больше GameState.FRIENDS_MAX).
	_friends_box = VBoxContainer.new()
	_friends_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friends_box.add_theme_constant_override("separation", 3)
	_sec_find.add_child(_friends_box)
	_sec_find.add_child(HSeparator.new())

	# Поиск по имени.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_sec_find.add_child(row)
	_search = LineEdit.new()
	_search.placeholder_text = "имя друга"
	_search.max_length = GameState.NAME_MAX
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_font_override("font", _font)
	_search.add_theme_font_size_override("font_size", 16)
	var sb := UiKit.steel_box(6, 0.95)
	sb.set_content_margin_all(6)
	for state in ["normal", "focus"]:
		_search.add_theme_stylebox_override(state, sb)
	_search.add_theme_color_override("font_color", Color.WHITE)
	_search.add_theme_color_override("caret_color", UiKit.YELLOW)
	_search.text_submitted.connect(func(_t: String) -> void: _do_search())
	row.add_child(_search)
	var find := Button.new()
	find.text = "НАЙТИ"
	UiKit.style_button(find, "yellow", 14)
	find.custom_minimum_size = Vector2(110, 36)
	find.pressed.connect(_do_search)
	row.add_child(find)

	_results = VBoxContainer.new()
	_results.add_theme_constant_override("separation", 3)
	_sec_find.add_child(_results)
	_sec_find.add_child(HSeparator.new())

	# Состав команды.
	_members_title = _label("", 15, Color.WHITE)
	_sec_members.add_child(_members_title)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_sec_members.add_child(_grid)

	_notice = _label("", 13, UiKit.TEAL)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_notice)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	_box.add_child(bottom)
	_ready_btn = Button.new()
	_ready_btn.text = "ГОТОВ"
	UiKit.style_button(_ready_btn, "teal", 18)
	_ready_btn.custom_minimum_size = Vector2(300, 48)
	_ready_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ready_btn.pressed.connect(_toggle_ready)
	bottom.add_child(_ready_btn)
	_leave_btn = Button.new()
	_leave_btn.text = "ВЫЙТИ"
	UiKit.style_button(_leave_btn, "red", 16)
	_leave_btn.custom_minimum_size = Vector2(150, 48)
	_leave_btn.pressed.connect(func() -> void: Social.leave_party())
	bottom.add_child(_leave_btn)


func _do_search() -> void:
	if not Social.connected:
		_on_notice("Нет связи с сервером друзей")
		return
	Social.search(_search.text)


func _on_results(items: Array) -> void:
	_last_items = items
	for c in _results.get_children():
		_results.remove_child(c)
		c.queue_free()
	if items.is_empty():
		_results.add_child(_label("Никого не нашлось" if _search.text != ""
				else "Сейчас никого нет в игре", 12, Color(1, 1, 1, 0.5)))
		return
	var shown := 0
	for it: Dictionary in items:
		if shown >= RESULTS_MAX:
			break
		shown += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_results.add_child(row)
		var online := bool(it.get("online", false))
		var nm := _label(str(it.get("name", "")), 15,
				Color.WHITE if online else Color(1, 1, 1, 0.45))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var st := "не в сети"
		if online:
			st = "в заезде" if str(it.get("status", "")) == "race" else "в гараже"
			if bool(it.get("party", false)):
				st += ", в команде"
		row.add_child(_label(st, 12, Color(1, 1, 1, 0.55)))
		var inv := Button.new()
		inv.text = "ПРИГЛАСИТЬ"
		UiKit.style_button(inv, "orange", 12)
		inv.custom_minimum_size = Vector2(120, 30)
		inv.disabled = not online or bool(it.get("party", false)) \
				or Social.members().size() >= SocialServer.PARTY_MAX
		var who := str(it.get("name", ""))
		inv.pressed.connect(func() -> void: Social.invite(who))
		row.add_child(inv)


## Спросить у сервера друзей статусы списка (ответ — _on_friends).
func _poll_friends() -> void:
	if Social.connected and Social.name_ok and not GameState.friends.is_empty():
		Social.lookup(GameState.friends.duplicate())


func _on_friends(items: Array) -> void:
	for it: Dictionary in items:
		_friend_state[str(it.get("name", "")).to_lower()] = it
	_refresh_friends()


## Список друзей из профиля: имя, статус (по последнему ответу сервера),
## «ПРИГЛАСИТЬ» и «✕» (забыть). Без связи — имена есть, звать нельзя.
func _refresh_friends() -> void:
	if _friends_box == null:
		return
	for c in _friends_box.get_children():
		_friends_box.remove_child(c)
		c.queue_free()
	var names: Array = GameState.friends
	_friends_title.text = "ДРУЗЬЯ (%d)" % names.size() if not names.is_empty() \
			else "ДРУЗЬЯ"
	if names.is_empty():
		_friends_box.add_child(_label(
				"Пока никого: найди друга ниже и пригласи — он останется здесь",
				12, Color(1, 1, 1, 0.5)))
		return
	var can_invite := Social.connected and Social.name_ok \
			and Social.members().size() < SocialServer.PARTY_MAX
	for n in names:
		var who := str(n)
		var it: Dictionary = _friend_state.get(who.to_lower(), {})
		var known := not it.is_empty() and Social.connected
		var online := known and bool(it.get("online", false))
		var in_party := known and bool(it.get("party", false))
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, FRIEND_ROW_H)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 8)
		_friends_box.add_child(row)
		var nm := _label(who, 14, Color.WHITE if online else Color(1, 1, 1, 0.45))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nm.clip_text = true
		row.add_child(nm)
		var st := "…" if not known else "не в сети"
		if online:
			st = "в заезде" if str(it.get("status", "")) == "race" else "в гараже"
			if in_party:
				st += ", в команде"
		var st_l := _label(st, 11, Color(1, 1, 1, 0.55))
		st_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(st_l)
		var inv := _flat_button("ПРИГЛАСИТЬ", UiKit.ORANGE, 100)
		inv.disabled = not (can_invite and online) or in_party
		inv.pressed.connect(func() -> void: Social.invite(who))
		row.add_child(inv)
		var del := _flat_button("✕", UiKit.STEEL, 28)
		del.tooltip_text = "Убрать из списка"
		del.pressed.connect(func() -> void:
			GameState.forget_friend(who)
			_refresh_friends())
		row.add_child(del)


## Плоская низкая кнопка для строк списка (стальная плитка UiKit слишком
## высока — поля текстуры по 20 px).
func _flat_button(text: String, bg: Color, width: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, FRIEND_ROW_H - 4.0)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 11)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		if state == "hover":
			sb.bg_color = bg.lightened(0.12)
		elif state == "pressed":
			sb.bg_color = bg.darkened(0.2)
		elif state == "disabled":
			sb.bg_color = Color(bg.r, bg.g, bg.b, 0.35)
		sb.set_corner_radius_all(5)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.5))
	return b


func _on_notice(text: String) -> void:
	_notice.text = text
	_notice_time = 6.0


func _toggle_ready() -> void:
	Social.set_ready(not Social.my_ready())


## Перерисовать по текущему состоянию Social: связь, имя, ростер.
func _refresh() -> void:
	if not is_inside_tree():
		return
	if Social.outdated:
		_status.text = Social.outdated_text
	elif not Social.connected:
		_status.text = "Нет связи с сервером друзей — проверь интернет " \
				+ "или подожди: подключаемся…"
	elif not Social.name_ok:
		_status.text = ("Имя «%s» занято другим игроком — нажми «ИМЯ» вверху "
				+ "и выбери другое") % GameState.display_name() \
				if Social.name_reason == "taken" \
				else "Сначала введи имя (кнопка «ИМЯ» вверху)"
	else:
		_status.text = ("На связи как «%s». Зови друзей (до %d чел.); "
				+ "все нажали «ГОТОВ» — едете в один заезд.") % [
				GameState.display_name(), SocialServer.PARTY_MAX]
	_refresh_friends()
	var ms: Array = Social.members()
	var in_party := Social.in_party()
	_members_title.text = ("В КОМАНДЕ: %d/%d" % [ms.size(), SocialServer.PARTY_MAX]) \
			if in_party else "Команды пока нет — пригласи друга"
	_ready_btn.visible = in_party
	_leave_btn.visible = in_party
	# В команде состав — первым (см. _build).
	if _sec_members and _sec_find:
		var top: Control = _sec_members if in_party else _sec_find
		var bottom_sec: Control = _sec_find if in_party else _sec_members
		top.get_parent().move_child(top, 0)
		bottom_sec.get_parent().move_child(bottom_sec, 1)
	if in_party:
		var mine := Social.my_ready()
		_ready_btn.text = "ГОТОВ ✓ — ждём остальных" if mine else "ГОТОВ"
		if bool(Social.party.get("launching", false)):
			_ready_btn.text = "Ищем заезд…"
	# Карточки членов: по uid, лишние снимаем, новые строим, машины меняем.
	var seen := {}
	for m: Dictionary in ms:
		var uid := str(m.get("uid", ""))
		seen[uid] = true
		if not _cards.has(uid):
			_cards[uid] = _build_card()
		var card: Dictionary = _cards[uid]
		var name_l: Label = card.name_l
		var is_me := uid == str(Social.party.get("me", ""))
		name_l.text = ("★ " if bool(m.get("leader", false)) else "") \
				+ str(m.get("name", "")) + (" (ты)" if is_me else "")
		name_l.add_theme_color_override("font_color",
				UiKit.GREEN_ME if is_me else UiKit.BLUE_MATE)
		var state_l: Label = card.state_l
		if not bool(m.get("online", true)):
			state_l.text = "не в сети"
			state_l.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		elif bool(m.get("ready", false)):
			state_l.text = "ГОТОВ ✓"
			state_l.add_theme_color_override("font_color", UiKit.GREEN_ME)
		elif str(m.get("status", "")) == "race":
			state_l.text = "в заезде"
			state_l.add_theme_color_override("font_color", UiKit.ORANGE_RIVAL)
		else:
			state_l.text = "ждёт"
			state_l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		var cid := str(m.get("car", ""))
		if cid != "" and cid != str(card.car):
			card.car = cid
			var table: Node3D = card.table
			for old in table.get_children():
				old.queue_free()
			var model := CarModelLibrary.build(cid, 3.0, 0.02)
			if model:
				table.add_child(model)
			(card.car_l as Label).text = CAR_NAMES.get(
					CarModelLibrary.base_id(cid), CarModelLibrary.base_id(cid))
	for uid in _cards.keys():
		if not seen.has(uid):
			(_cards[uid].root as Control).queue_free()
			_cards.erase(uid)


## Карточка члена команды: подиум с машиной (свой мир, как в лобби),
## имя, состояние.
func _build_card() -> Dictionary:
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(CARD_W, CARD_H)
	root.add_theme_constant_override("separation", 2)
	_grid.add_child(root)
	var name_l := _label("", 13, Color.WHITE)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.clip_text = true
	root.add_child(name_l)

	var view := SubViewportContainer.new()
	view.stretch = true
	view.custom_minimum_size = Vector2(CARD_W, 92)
	root.add_child(view)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.add_child(vp)
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
	vp.add_child(table)

	var car_l := _label("", 11, Color(1, 0.9, 0.45))
	car_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	car_l.clip_text = true
	root.add_child(car_l)
	var state_l := _label("", 12, Color(1, 1, 1, 0.6))
	state_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(state_l)
	return {root = root, table = table, car = "", name_l = name_l,
			car_l = car_l, state_l = state_l}


func _label(txt: String, size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
