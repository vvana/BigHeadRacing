class_name WeaponShopPanel
extends PanelContainer
## МАГАЗИН ОРУЖИЯ в гараже (08.09): на месте доски «АВТОПАРК», как
## TuningPanel. Девять видов, у каждого три ступени I/II/III — покупаются
## ПО ПОРЯДКУ за монеты, каждая открывается уровнем профиля (таблица —
## Weapons.STEP_LEVELS / STEP_PRICES, экономика — ЭКОНОМИКА.md разд. 7).
## Что даёт ступень — Weapons.STEP_DESC. Это единственная прокачка,
## влияющая на игру: само оружие по-прежнему выпадает из боксов.

signal changed
signal closed

## Порядок строк — по группам: лёгкие, средние, тяжёлые (как в таблице
## экономики: раньше и дешевле → позже и дороже).
const ORDER := [
	Weapons.MINE, Weapons.OIL, Weapons.BOOST,
	Weapons.MAGNET, Weapons.FREEZE, Weapons.SCRAMBLE,
	Weapons.ROCKET, Weapons.LASER, Weapons.AIRSTRIKE,
]
const ICON := 46

var _font: FontFile
var _box: VBoxContainer
var _flash_gen := 0


func _ready() -> void:
	_font = UiKit.font()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.19, 0.21, 0.24, 0.96)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(UiKit.RIM.r, UiKit.RIM.g, UiKit.RIM.b, 0.45)
	add_theme_stylebox_override("panel", style)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
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
	_flash_gen += 1

	# Шапка: заголовок, кошелёк, «ЗАКРЫТЬ».
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_box.add_child(head)
	var title := _label("ОРУЖИЕ · ПРОКАЧКА", 20, UiKit.YELLOW, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_label("МОНЕТЫ %s" % _fmt(GameState.money), 15, Color.WHITE, false))
	var close_btn := Button.new()
	close_btn.text = "ЗАКРЫТЬ"
	UiKit.style_button(close_btn, "steel", 14)
	close_btn.custom_minimum_size = Vector2(110, 34)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	_box.add_child(_label(
			"У каждого оружия три ступени — I, II, III. Покупаются по порядку"
			+ " за монеты, каждая открывается с определённого уровня. Само"
			+ " оружие по-прежнему выпадает из боксов на трассе; III ступень"
			+ " роняет его в полтора раза чаще. Уровень %d." % GameState.level_info().x,
			12, Color(1, 1, 1, 0.55)))
	_box.add_child(HSeparator.new())

	for kind: int in ORDER:
		_build_row(kind)


## Строка вида: значок, имя со ступенями, что даёт следующая ступень,
## справа — «КУПИТЬ · цена» / «с N ур.» / «МАКС».
func _build_row(kind: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_box.add_child(row)

	var icon := TextureRect.new()
	icon.texture = Weapons.icon(kind)
	icon.custom_minimum_size = Vector2(ICON, ICON)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)

	var step := GameState.weapon_step(kind)
	var next := GameState.weapon_next_step(kind)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	head.add_child(_label(Weapons.display_name(kind), 15, UiKit.YELLOW, false))
	head.add_child(_pips(step, next))
	head.add_child(_label(Weapons.GROUP_NAMES[Weapons.group_of(kind)], 11,
			Color(1, 1, 1, 0.4), false))

	var desc := ""
	if next > 0:
		desc = "%s: %s" % [Weapons.ROMAN[next], Weapons.step_desc(kind, next)]
	else:
		desc = "Все ступени куплены."
	col.add_child(_label(desc, 12, Color(1, 1, 1, 0.8)))

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 40)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	if next <= 0:
		btn.text = "МАКС"
		UiKit.style_button(btn, "steel", 13)
		btn.disabled = true
	elif GameState.level_info().x < Weapons.step_level(kind, next):
		btn.text = "с %d ур." % Weapons.step_level(kind, next)
		UiKit.style_button(btn, "steel", 13)
		btn.disabled = true
	else:
		btn.text = "КУПИТЬ · %s" % _fmt(Weapons.step_price(kind, next))
		UiKit.style_button(btn, "orange", 13)
		btn.pressed.connect(_buy.bind(kind, btn))
	row.add_child(btn)
	_box.add_child(HSeparator.new())


## Три ярлыка I · II · III: купленные — жёлтые, следующая — светлая
## рамка, дальние — серые.
func _pips(step: int, next: int) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	for s in range(1, Weapons.STEPS + 1):
		var l := Label.new()
		l.text = Weapons.ROMAN[s]
		if _font:
			l.add_theme_font_override("font", _font)
		l.add_theme_font_size_override("font_size", 10)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(26, 18)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 3
		sb.content_margin_right = 3
		if s <= step:
			sb.bg_color = UiKit.YELLOW
			l.add_theme_color_override("font_color", UiKit.INK)
		elif s == next:
			sb.bg_color = Color(0.3, 0.33, 0.37)
			sb.set_border_width_all(1)
			sb.border_color = Color(1, 1, 1, 0.7)
			l.add_theme_color_override("font_color", Color.WHITE)
		else:
			sb.bg_color = Color(0.27, 0.29, 0.32)
			l.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
		l.add_theme_stylebox_override("normal", sb)
		box.add_child(l)
	return box


func _buy(kind: int, btn: Button) -> void:
	if GameState.try_buy_weapon_step(kind):
		rebuild()
		changed.emit()
	else:
		_flash(btn, "НЕ ХВАТАЕТ МОНЕТ")


func _label(txt: String, size: int, color: Color, wrap := true) -> Label:
	var l := Label.new()
	l.text = txt
	if _font:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## Цена с тонкой шпацией между тысячами: 24000 → «24 000».
func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = " " + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


func _flash(btn: Button, text: String) -> void:
	_flash_gen += 1
	var gen := _flash_gen
	var old := btn.text
	btn.text = text
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(btn) and _flash_gen == gen:
		btn.text = old
