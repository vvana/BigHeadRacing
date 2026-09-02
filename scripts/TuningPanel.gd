class_name TuningPanel
extends PanelContainer
## Панель «ТЮНИНГ» в гараже: улучшения и косметика выбранной машины.
## Четыре слота (мотор, колёса, спойлер, выхлоп) × 3 ступени — покупаются
## за монеты по ЭКОНОМИКА.md (раздел 5) и открываются уровнем. У аркадных
## конструкторов (CarModelLibrary.ARCADE_IDS) ступень открывает по три
## детали на кузов — ряд иконок под слотом; плюс 36 красок (бесплатно),
## пакет «Металлик» и пакет «Наклейки» (раздел 7а). У остальных машин —
## только ступени характеристик. Всё состояние — в GameState (профиль);
## панель лишь рисует и зовёт try_buy_*/set_tuning, после чего шлёт
## changed — гараж перестраивает подиум и миниатюру.

signal changed
signal closed

const SLOT_NAMES := {
	"engine": "МОТОР", "wheel": "КОЛЁСА", "spoiler": "СПОЙЛЕР", "exhaust": "ВЫХЛОП",
}
const SLOT_EFFECT := {
	"engine": "разгон +4% за ступень",
	"wheel": "сцепление и руль +4%/ст.",
	"spoiler": "скорость +2% за ступень",
	"exhaust": "буст на 10% дольше/ст.",
}
const ICON_DIR := "res://assets/ui/parts/"
const CELL := 42          # иконка детали, px
const SWATCH := 24        # квадратик краски, px
const ROMAN := ["", "I", "II", "III"]

var _base := ""
var _font: FontFile
var _box: VBoxContainer
var _flash_gen := 0


func _ready() -> void:
	_font = UiKit.font()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiKit.INK.r, UiKit.INK.g, UiKit.INK.b, 0.94)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(UiKit.RIM.r, UiKit.RIM.g, UiKit.RIM.b, 0.45)
	add_theme_stylebox_override("panel", style)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_box)
	visible = false


## Открыть панель для машины base (только своя машина).
func open(base: String) -> void:
	_base = base
	visible = true
	rebuild()


func close() -> void:
	visible = false
	closed.emit()


## Перерисовать всё по текущему состоянию GameState.
func rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_flash_gen += 1
	var arcade := CarModelLibrary.is_arcade(_base)

	# Шапка: имя машины, кошелёк, «ЗАКРЫТЬ».
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_box.add_child(head)
	var title := _label("ТЮНИНГ · %s" % _car_name(), 20, UiKit.YELLOW, false)
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

	for slot in GameState.UPGRADE_SLOTS:
		_build_slot(slot, arcade)

	if arcade:
		_build_paint()
		_build_stickers()
	else:
		_box.add_child(_label(
				"Детали на кузов ставятся только на аркадные машины-конструкторы;"
				+ " здесь ступени дают характеристики.", 12,
				Color(1, 1, 1, 0.55)))


# ---- Слот улучшения ----

func _build_slot(slot: String, arcade: bool) -> void:
	var lv := GameState.upgrade_level(_base, slot)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	var pips := ""
	for i in GameState.UPGRADE_STEPS:
		pips += "▮" if i < lv else "▯"
	var lbl := _label("%s  %s   %s" % [SLOT_NAMES[slot], pips, SLOT_EFFECT[slot]],
			14, Color.WHITE)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	row.add_child(_step_button(slot))

	if not arcade:
		return
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 4)
	_box.add_child(icons)
	var cfg := GameState.tuning_of(_base)
	var first := 1 if slot == "wheel" else 0
	for idx in range(first, CarModelLibrary.PART_COUNT + 1):
		var tier := CarModelLibrary.part_tier(slot, idx)
		var b := _icon_button("%s_%d.png" % [slot, idx])
		var mounted: bool = int(cfg[slot]) == idx
		var open_ := tier <= lv
		_frame(b, mounted, open_)
		if open_:
			b.tooltip_text = "Сток" if tier == 0 else "Ступень %s" % ROMAN[tier]
			b.pressed.connect(_mount.bind(slot, idx))
		else:
			b.tooltip_text = "Ступень %s — %s" % [ROMAN[tier],
					_step_hint(slot, tier)]
			b.pressed.connect(_buy_step_and_mount.bind(slot, tier, idx))
		icons.add_child(b)


## Кнопка следующей ступени слота: «СТУПЕНЬ II · 240», «С 6 УРОВНЯ · 240»
## (серая) или «МАКС».
func _step_button(slot: String) -> Button:
	var b := Button.new()
	var lv := GameState.upgrade_level(_base, slot)
	b.custom_minimum_size = Vector2(190, 32)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if lv >= GameState.UPGRADE_STEPS:
		_style_disabled(b, "МАКС")
		return b
	var need := GameState.upgrade_unlock_level(_base, slot)
	var price := GameState.upgrade_price(_base, slot)
	if GameState.level_info().x < need:
		_style_disabled(b, "С %d УРОВНЯ · %s" % [need, _fmt(price)])
	else:
		UiKit.style_button(b, "orange", 13)
		b.text = "СТУПЕНЬ %s · %s" % [ROMAN[lv + 1], _fmt(price)]
		b.pressed.connect(_buy_step.bind(slot, lv + 1, b))
	return b


## Серая недоступная табличка (UiKit.style_button стиль «disabled» не
## задаёт — без него кнопка теряет фон).
func _style_disabled(b: Button, text: String) -> void:
	UiKit.style_button(b, "steel", 13)
	b.add_theme_stylebox_override("disabled", b.get_theme_stylebox("normal"))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.55))
	b.text = text
	b.disabled = true


## Подсказка к закрытой детали: что нужно для её ступени.
func _step_hint(slot: String, tier: int) -> String:
	var lv := GameState.upgrade_level(_base, slot)
	if tier > lv + 1:
		return "сначала ступень %s" % ROMAN[lv + 1]
	var need := GameState.upgrade_unlock_level(_base, slot)
	if GameState.level_info().x < need:
		return "с %d уровня, %s монет" % [need, _fmt(GameState.upgrade_price(_base, slot))]
	return "%s монет — нажмите, чтобы купить" % _fmt(GameState.upgrade_price(_base, slot))


func _buy_step(slot: String, tier: int, btn: Button) -> void:
	if GameState.upgrade_level(_base, slot) != tier - 1:
		return
	if GameState.try_buy_upgrade(_base, slot):
		changed.emit()
		rebuild()
	else:
		_flash(btn, "НЕ ХВАТАЕТ МОНЕТ")


## Клик по закрытой детали: если это ближайшая ступень и уровень позволяет —
## купить и сразу поставить; иначе просто подсказка.
func _buy_step_and_mount(slot: String, tier: int, idx: int) -> void:
	var lv := GameState.upgrade_level(_base, slot)
	if tier != lv + 1 or GameState.level_info().x < GameState.upgrade_unlock_level(_base, slot):
		return
	if GameState.try_buy_upgrade(_base, slot):
		GameState.set_tuning(_base, slot, idx)
		changed.emit()
		rebuild()


func _mount(slot: String, idx: int) -> void:
	if GameState.set_tuning(_base, slot, idx):
		changed.emit()
		rebuild()


# ---- Краски и металлик ----

func _build_paint() -> void:
	var cfg := GameState.tuning_of(_base)
	var metallic := GameState.pack_owned(_base, GameState.PACK_METALLIC)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	var lbl := _label("КРАСКА   12 цветов × 3 оттенка — бесплатно", 14, Color.WHITE)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var mb := Button.new()
	mb.custom_minimum_size = Vector2(190, 32)
	mb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if metallic:
		UiKit.style_button(mb, "teal" if int(cfg["glitter"]) == 1 else "steel", 13)
		mb.text = "МЕТАЛЛИК: %s" % ("ВКЛ" if int(cfg["glitter"]) == 1 else "ВЫКЛ")
		mb.pressed.connect(func() -> void:
			if GameState.set_tuning(_base, "glitter", 1 - int(cfg["glitter"])):
				changed.emit()
				rebuild())
	else:
		UiKit.style_button(mb, "orange", 13)
		mb.text = "МЕТАЛЛИК · %s" % _fmt(GameState.pack_price(_base, GameState.PACK_METALLIC))
		mb.tooltip_text = "Металлик-версия всех красок этой машины"
		mb.pressed.connect(_buy_pack.bind(GameState.PACK_METALLIC, mb))
	row.add_child(mb)

	for shade in [1, 2, 3]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		_box.add_child(line)
		for color in CarModelLibrary.ARCADE_COLORS:
			var paints: Array = CarModelLibrary.ARCADE_PAINTS[color]
			var b := Button.new()
			b.custom_minimum_size = Vector2(SWATCH, SWATCH)
			b.focus_mode = Control.FOCUS_NONE
			b.tooltip_text = color
			var cur: bool = cfg["color"] == color and int(cfg["shade"]) == shade
			var sb := StyleBoxFlat.new()
			sb.bg_color = paints[shade - 1]
			sb.set_corner_radius_all(5)
			sb.set_border_width_all(3 if cur else 1)
			sb.border_color = UiKit.YELLOW if cur else Color(0, 0, 0, 0.5)
			for state in ["normal", "hover", "pressed", "focus"]:
				b.add_theme_stylebox_override(state, sb)
			b.pressed.connect(_paint.bind(color, shade))
			line.add_child(b)


func _paint(color: String, shade: int) -> void:
	GameState.set_tuning(_base, "color", color)
	if GameState.set_tuning(_base, "shade", shade):
		changed.emit()
		rebuild()


# ---- Наклейки и полоса ----

func _build_stickers() -> void:
	var cfg := GameState.tuning_of(_base)
	var owned := GameState.pack_owned(_base, GameState.PACK_STICKERS)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	var lbl := _label("НАКЛЕЙКИ   10 наклеек и двойная полоса", 14, Color.WHITE)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var pb := Button.new()
	pb.custom_minimum_size = Vector2(190, 32)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if owned:
		var on := int(cfg["line"]) == 1
		UiKit.style_button(pb, "teal" if on else "steel", 13)
		pb.text = "ПОЛОСА: %s" % ("ВКЛ" if on else "ВЫКЛ")
		pb.pressed.connect(func() -> void:
			if GameState.set_tuning(_base, "line", 0 if on else 1):
				changed.emit()
				rebuild())
	else:
		UiKit.style_button(pb, "orange", 13)
		pb.text = "НАКЛЕЙКИ · %s" % _fmt(GameState.pack_price(_base, GameState.PACK_STICKERS))
		pb.tooltip_text = "Открывает все наклейки и полосу для этой машины"
		pb.pressed.connect(_buy_pack.bind(GameState.PACK_STICKERS, pb))
	row.add_child(pb)

	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 4)
	_box.add_child(icons)
	for idx in range(0, CarModelLibrary.PART_COUNT + 1):
		var b := _icon_button("sticker_%d.png" % idx)
		var mounted: bool = int(cfg["sticker"]) == idx
		var open_ := owned or idx == 0
		_frame(b, mounted, open_)
		if open_:
			b.pressed.connect(func() -> void:
				if GameState.set_tuning(_base, "sticker", idx):
					changed.emit()
					rebuild())
		else:
			b.tooltip_text = "Нужен пакет «Наклейки»"
			b.pressed.connect(_buy_pack.bind(GameState.PACK_STICKERS, pb))
		icons.add_child(b)


func _buy_pack(pack: String, btn: Button) -> void:
	if GameState.try_buy_pack(_base, pack):
		changed.emit()
		rebuild()
	else:
		_flash(btn, "НЕ ХВАТАЕТ МОНЕТ")


# ---- Мелочи ----

func _icon_button(file: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(CELL, CELL)
	b.icon = load(ICON_DIR + file)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	return b


## Рамка иконки: жёлтая — стоит на машине, обычная — доступна, тёмная —
## закрыта.
func _frame(b: Button, mounted: bool, open_: bool) -> void:
	var sb := UiKit.steel_box(6)
	if mounted:
		sb.set_border_width_all(3)
		sb.border_color = UiKit.YELLOW
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, sb)
	b.modulate = Color.WHITE if open_ else Color(0.45, 0.45, 0.5)


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


func _car_name() -> String:
	var names: Dictionary = preload("res://scripts/CarSelect.gd").DISPLAY_NAMES
	return names.get(_base, _base)


## Цена с тонкой шпацией между тысячами: 24000 → «24 000».
func _fmt(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = " " + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


## Мигнуть надписью на кнопке (не хватило монет) и вернуть прежний текст.
func _flash(btn: Button, text: String) -> void:
	_flash_gen += 1
	var gen := _flash_gen
	var old := btn.text
	btn.text = text
	await get_tree().create_timer(1.2).timeout
	if is_instance_valid(btn) and _flash_gen == gen:
		btn.text = old
