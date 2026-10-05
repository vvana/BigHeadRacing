class_name SettingsPanel
extends PanelContainer
## НАСТРОЙКИ в гараже (29.09): на месте доски «АВТОПАРК». КАЧЕСТВО
## ГРАФИКИ (низкая / средняя / максимальная; в браузере раздела нет — там
## графика облегчена всегда), УПРАВЛЕНИЕ (автоматический газ, сторона руля
## на экране телефона) и ЯЗЫК (05.10). Что именно меняет каждый уровень
## графики и почему — у GameState.gfx_quality. Выбор запоминается на
## устройстве (user://settings.cfg) и действует сразу: разрешение и свет
## гаража — на месте, свет и тени заезда — при его постройке; язык —
## перезагрузкой гаража (сигнал lang_changed).

signal closed
signal changed
signal lang_changed

var _font: FontFile
var _box: VBoxContainer
var _head: HBoxContainer          # шапка с «ЗАКРЫТЬ» — вне прокрутки


func _ready() -> void:
	_font = UiKit.font()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.19, 0.21, 0.24, 0.96)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(UiKit.RIM.r, UiKit.RIM.g, UiKit.RIM.b, 0.45)
	add_theme_stylebox_override("panel", style)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	_head = HBoxContainer.new()
	_head.add_theme_constant_override("separation", 10)
	root.add_child(_head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_box)
	visible = false


func open() -> void:
	visible = true
	rebuild()


func close() -> void:
	visible = false
	closed.emit()


func rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	for c in _head.get_children():
		_head.remove_child(c)
		c.queue_free()
	var touch := TouchControls.wanted()
	var title := _label(Loc.t("НАСТРОЙКИ"), 20, UiKit.YELLOW)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = Loc.t("ЗАКРЫТЬ")
	UiKit.style_button(close_btn, "steel", 18 if touch else 14)
	close_btn.custom_minimum_size = Vector2(150, 48) if touch else Vector2(110, 34)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(close)
	_head.add_child(close_btn)

	if not GameState.lite_gfx():
		_box.add_child(_label(Loc.t("КАЧЕСТВО ГРАФИКИ"), 14, UiKit.TEAL))
		var names := [Loc.t("НИЗКАЯ"), Loc.t("СРЕДНЯЯ"), Loc.t("МАКСИМАЛЬНАЯ")]
		var row := _choice_row(names, GameState.gfx_quality, touch)
		for q in names.size():
			(row.get_child(q) as Button).pressed.connect(_pick.bind(q))
		var about := [
			Loc.t("Без теней и точечного света, картинка мягче. Самая плавная езда — для слабых телефонов."),
			Loc.t("Тени проще, картинка чуть мягче."),
			Loc.t("Все тени, полная чёткость. Для мощных устройств."),
		]
		_box.add_child(_text(about[GameState.gfx_quality]))
		var note := _label(Loc.t("Если игра идёт рывками — выбери уровень ниже. Свет и тени меняются со следующего заезда."),
				12, Color(1, 1, 1, 0.5))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_box.add_child(note)
		_box.add_child(HSeparator.new())

	_box.add_child(_label(Loc.t("УПРАВЛЕНИЕ"), 14, UiKit.TEAL))
	var gas := Button.new()
	gas.text = Loc.t("АВТОМАТИЧЕСКИЙ ГАЗ: ВКЛ") if GameState.auto_gas \
			else Loc.t("АВТОМАТИЧЕСКИЙ ГАЗ: ВЫКЛ")
	UiKit.style_button(gas, "yellow" if GameState.auto_gas else "steel",
			17 if touch else 15, 8)
	gas.custom_minimum_size = Vector2(0, 76 if touch else 64)
	gas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gas.pressed.connect(_toggle_auto_gas)
	_box.add_child(gas)
	_box.add_child(_text(Loc.t("Машина сама держит газ. Тормоз снимает газ и тормозит.")))
	# Сторона руля — только там, где есть экранные кнопки.
	if touch:
		var sides := _choice_row([Loc.t("РУЛЬ СЛЕВА"), Loc.t("РУЛЬ СПРАВА")],
				1 if GameState.steer_right else 0, touch)
		for i in 2:
			(sides.get_child(i) as Button).pressed.connect(_pick_side.bind(i == 1))
		_box.add_child(_text(Loc.t("Кнопки руля справа, газ и тормоз слева.")
				if GameState.steer_right
				else Loc.t("Кнопки руля слева, газ и тормоз справа.")))

	_box.add_child(HSeparator.new())
	# Заголовок сразу на двух языках: его должен найти и тот, кто не читает
	# по-русски, а названия языков пишутся на самих этих языках.
	_box.add_child(_label("ЯЗЫК / LANGUAGE", 14, UiKit.TEAL))
	var codes := ["", "ru", "en"]
	var langs := _choice_row([Loc.t("АВТО"), "РУССКИЙ", "ENGLISH"],
			codes.find(GameState.lang_choice), touch)
	for i in codes.size():
		(langs.get_child(i) as Button).pressed.connect(_pick_lang.bind(codes[i]))
	_box.add_child(_text(Loc.t("Авто — язык устройства: русский или английский.")))


## Ряд кнопок «выбери одно»: выбранная — жёлтая эмаль, остальные — сталь.
func _choice_row(names: Array, picked: int, touch: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	for i in names.size():
		var b := Button.new()
		b.text = names[i]
		UiKit.style_button(b, "yellow" if i == picked else "steel",
				17 if touch else 15, 8)
		b.custom_minimum_size = Vector2(0, 76 if touch else 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		row.add_child(b)
	return row


func _text(txt: String) -> Label:
	var l := _label(txt, 14, Color(1, 1, 1, 0.85))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _pick_side(right: bool) -> void:
	if right == GameState.steer_right:
		return
	GameState.set_steer_right(right)
	rebuild()


func _pick_lang(code: String) -> void:
	if code == GameState.lang_choice:
		return
	var was := TranslationServer.get_locale()
	GameState.set_lang_choice(code)
	rebuild()
	# Гараж собран на прежнем языке — пересобрать его целиком.
	if TranslationServer.get_locale() != was:
		lang_changed.emit()


func _toggle_auto_gas() -> void:
	GameState.set_auto_gas(not GameState.auto_gas)
	rebuild()
	changed.emit()


func _pick(q: int) -> void:
	if q == GameState.gfx_quality:
		return
	GameState.set_gfx_quality(q)
	rebuild()
	changed.emit()


func _label(txt: String, size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	return l
