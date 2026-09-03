class_name TuningPanel
extends PanelContainer
## Панель «ТЮНИНГ» в гараже: ЧИСТАЯ КОСМЕТИКА выбранной машины (03.09 —
## характеристик тюнинг больше не даёт вовсе, чтобы в сетевом заезде все
## ехали на равных; улучшать можно будет только оружие и бонусы,
## ЭКОНОМИКА.md раздел 7).
## У ЛЮБОЙ своей машины здесь краски (с 03.09 цвета выбираются только
## тут — ряда красок в гараже больше нет): у советских и Unity-машин —
## 10 бесплатных цветов, у аркадных конструкторов — 36 красок и
## «Металлик». Слоты деталей (мотор, колёса, спойлер, выхлоп) — у
## аркадных ×10 вариантов и у СОВЕТСКИХ (03.09 вечер) — свой подобранный
## набор на каждую (CarModelLibrary.SOVIET_PARTS); наклейки и полоса —
## только у аркадных. У деталей и у полосы СВОЙ цвет (pcolor/lcolor),
## бесплатно.
## ПРИМЕРКА (03.09 вечер): клик по некупленному элементу НЕ покупает,
## а надевает его на машину на подиуме (оранжевая рамка); всё примеренное
## собирается в строку «ПРИМЕРКА … итого N» с кнопкой «КУПИТЬ» — она
## покупает разом и ставит. Примерка живёт только в панели (_preview):
## профиль, selected_car_id и миниатюры её не видят; закрыл панель —
## примерка сброшена. Купленное/бесплатное ставится сразу (set_tuning).
## Всё состояние — в GameState (профиль); панель лишь рисует и зовёт
## try_buy_item/set_tuning, после чего шлёт changed — гараж перестраивает
## подиум (с примеркой — preview_id) и миниатюру.

signal changed
signal closed

const SLOT_NAMES := {
	"engine": "МОТОР", "wheel": "КОЛЁСА", "spoiler": "СПОЙЛЕР", "exhaust": "ВЫХЛОП",
}
## Что стоит в слоте (только внешний вид, на езду не влияет).
const SLOT_EFFECT := {
	"engine": "компрессоры на капот",
	"wheel": "комплекты дисков",
	"spoiler": "спойлеры на корму",
	"exhaust": "выхлопы",
}
## Названия цветов советских машин для подсказок.
const COLOR_NAMES := {
	"black": "чёрный", "blue": "синий", "gray": "серый",
	"green": "зелёный", "lightblue": "голубой", "purple": "фиолетовый",
	"red": "красный", "sand": "песочный", "white": "белый",
	"yellow": "жёлтый",
}
## Цвет квадратика-образца советских машин. НЕ на глазок: это настоящие
## пиксели палитры пака (albedo.png, цвет машины выбирается её UV) — сняты
## стендом tools/dump_car_colors.gd по самой большой площади кузова.
const SWATCH_COLORS := {
	"black": Color(0.09, 0.09, 0.09), "blue": Color(0.000, 0.129, 0.612),
	"gray": Color(0.314, 0.314, 0.314), "green": Color(0.000, 0.686, 0.016),
	"lightblue": Color(0.082, 0.557, 1.000), "purple": Color(0.235, 0.102, 0.329),
	"red": Color(0.678, 0.000, 0.000), "sand": Color(0.886, 0.835, 0.545),
	"white": Color(1.0, 1.0, 1.0), "yellow": Color(1.000, 0.847, 0.000),
}
const ICON_DIR := "res://assets/ui/parts/"
const CELL := 42          # иконка детали, px
const SWATCH := 24        # квадратик краски (аркадные), px
const SWATCH_BIG := 34    # квадратик цвета советских машин, px
const ROMAN := ["", "I", "II", "III"]
const PREVIEW_COLOR := Color(1.0, 0.55, 0.15)   # рамка примеренного

var _base := ""
var _font: FontFile
var _box: VBoxContainer
var _flash_gen := 0
## Примерка: ключ комплектации → значение (только НЕкупленное платное).
var _preview := {}


func _ready() -> void:
	_font = UiKit.font()
	var style := StyleBoxFlat.new()
	# Тёмно-стальная, а не чернильная: гараж стал светлым (03.09), чёрная
	# панель на нём выглядела дырой.
	style.bg_color = Color(0.19, 0.21, 0.24, 0.96)
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


## Открыть панель для машины base (только своя машина). Другая машина —
## примерка прежней сбрасывается.
func open(base: String) -> void:
	if base != _base:
		_preview.clear()
	_base = base
	visible = true
	rebuild()


func close() -> void:
	_preview.clear()
	visible = false
	closed.emit()


func base() -> String:
	return _base


# ---- Примерка ----

func has_preview() -> bool:
	return not _preview.is_empty()


## Комплектация с примеркой поверх настоящей (цвет кузова — текущий).
func preview_cfg() -> Dictionary:
	var cfg := GameState.tuning_of(_base)
	cfg["color"] = GameState.color_of(_base)
	for k in _preview:
		cfg[k] = _preview[k]
	return cfg


## Полный id машины С примеркой — для подиума гаража.
func preview_id() -> String:
	return CarModelLibrary.tuned_id(_base, preview_cfg())


## Ключи элементов, которые надо купить ради примерки (некупленные).
func _preview_items() -> Array[String]:
	var keys: Array[String] = []
	for k in _preview:
		var key := ""
		match k:
			"wheel", "engine", "spoiler", "exhaust":
				key = "%s:%d" % [k, int(_preview[k])]
			"sticker":
				key = "sticker:%d" % int(_preview[k])
			"line":
				key = "line"
			"glitter":
				key = "metal:%s" % str(preview_cfg()["color"])
		if not key.is_empty() and not GameState.item_owned(_base, key) \
				and not keys.has(key):
			keys.append(key)
	return keys


func _preview_total() -> int:
	var sum := 0
	for key in _preview_items():
		sum += GameState.item_price(_base, key)
	return sum


## Примерить: положить в _preview и перестроить подиум; повторный клик по
## тому же — снять с примерки.
func _try_on(key: String, value: Variant) -> void:
	if _preview.has(key) and _preview[key] == value:
		_preview.erase(key)
		if key == "glitter":
			_preview.erase("color")
			_preview.erase("shade")
	else:
		_preview[key] = value
	changed.emit()
	rebuild()


## Купить всё примеренное разом и поставить. Не хватило уровня или монет
## — мигнуть кнопкой, ничего не покупать.
func _buy_preview(btn: Button) -> void:
	var keys := _preview_items()
	var lvl: int = GameState.level_info().x
	for key in keys:
		var need := GameState.item_unlock_level(_base, key)
		if lvl < need:
			_flash(btn, "НУЖЕН %d УРОВЕНЬ" % need)
			return
	if GameState.money < _preview_total():
		_flash(btn, "НЕ ХВАТАЕТ МОНЕТ")
		return
	for key in keys:
		GameState.try_buy_item(_base, key)
	for k in _preview:
		GameState.set_tuning(_base, k, _preview[k])
	_preview.clear()
	changed.emit()
	rebuild()


func _drop_preview() -> void:
	_preview.clear()
	changed.emit()
	rebuild()


## Строка примерки: что надето и почём, «КУПИТЬ · N», «СБРОС».
func _build_preview_row() -> void:
	if _preview.is_empty():
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	var names: Array[String] = []
	for k in _preview:
		match k:
			"wheel", "engine", "spoiler", "exhaust":
				names.append("%s №%d" % [String(SLOT_NAMES[k]).to_lower(), int(_preview[k])])
			"sticker": names.append("наклейка №%d" % int(_preview[k]))
			"line": names.append("полоса")
			"glitter": names.append("металлик %s" % str(preview_cfg()["color"]))
	var lbl := _label("ПРИМЕРКА: %s · итого %s" % [", ".join(names),
			_fmt(_preview_total())], 14, PREVIEW_COLOR)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var buy := Button.new()
	buy.text = "КУПИТЬ · %s" % _fmt(_preview_total())
	UiKit.style_button(buy, "orange", 14)
	buy.custom_minimum_size = Vector2(170, 34)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.pressed.connect(_buy_preview.bind(buy))
	row.add_child(buy)
	var drop := Button.new()
	drop.text = "СБРОС"
	UiKit.style_button(drop, "steel", 13)
	drop.custom_minimum_size = Vector2(90, 34)
	drop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	drop.pressed.connect(_drop_preview)
	row.add_child(drop)


## Перерисовать всё по текущему состоянию GameState.
func rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_flash_gen += 1
	var arcade := CarModelLibrary.is_arcade(_base)
	var parts := CarModelLibrary.has_parts(_base)

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

	_box.add_child(_label(
			"Тюнинг — только внешний вид: на скорость, разгон и управляемость"
			+ " он не влияет. Клик по некупленному — примерить, покупка —"
			+ " кнопкой «КУПИТЬ».", 12, Color(1, 1, 1, 0.55)))
	_build_preview_row()
	if parts:
		for slot in GameState.UPGRADE_SLOTS:
			_build_slot(slot)
	if arcade:
		_build_paint()
	else:
		_build_simple_paint()
	if parts:
		_build_part_color()
	if arcade:
		_build_stickers()


# ---- Слот деталей: каждая покупается отдельно ----

func _build_slot(slot: String) -> void:
	var options := CarModelLibrary.slot_options(_base, slot)
	var total := 0
	for idx in options:
		if CarModelLibrary.part_tier(slot, idx) > 0:
			total += 1
	var owned := GameState.items_owned_count(_base, slot + ":")
	var prices := []
	for tier in [1, 2, 3]:
		prices.append(_fmt(_tier_price(slot, tier)))
	_box.add_child(_label("%s  %d из %d   %s · ярус I / II / III — %s / %s / %s"
			% [SLOT_NAMES[slot], owned, total, SLOT_EFFECT[slot],
					prices[0], prices[1], prices[2]], 14, Color.WHITE))

	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 4)
	_box.add_child(icons)
	var real := GameState.tuning_of(_base)
	for idx in options:
		var key := "%s:%d" % [slot, idx]
		var tier := CarModelLibrary.part_tier(slot, idx)
		# Иконка «нет/родные» у колёс советских (индекс 0) — общий значок ∅.
		var file := "%s_%d.png" % [slot, idx]
		if idx == 0 and not ResourceLoader.exists(ICON_DIR + file):
			file = "engine_0.png"
		var b := _icon_button(file)
		var mounted: bool = int(real[slot]) == idx
		var previewed: bool = _preview.has(slot) and int(_preview[slot]) == idx
		var open_ := tier == 0 or GameState.item_owned(_base, key)
		_frame(b, mounted and not _preview.has(slot), open_, previewed)
		if open_:
			if idx == 0:
				b.tooltip_text = "Родные колёса" if slot == "wheel" else "Пусто"
			else:
				b.tooltip_text = "Сток" if tier == 0 else "Куплено · ярус %s" % ROMAN[tier]
			b.pressed.connect(_mount.bind(slot, idx))
		else:
			_price_tag(b, key)
			b.tooltip_text = "Ярус %s — %s" % [ROMAN[tier], _item_hint(key)]
			b.pressed.connect(_try_on.bind(slot, idx))
		icons.add_child(b)


## Цена детали яруса tier в этом слоте (все детали яруса стоят одинаково).
func _tier_price(slot: String, tier: int) -> int:
	var first := 2 if slot == "wheel" else 1
	return GameState.item_price(_base, "%s:%d" % [slot, first + (tier - 1) * 3])


## Подсказка к закрытому элементу: что нужно, чтобы его купить.
func _item_hint(key: String) -> String:
	var need := GameState.item_unlock_level(_base, key)
	var price := _fmt(GameState.item_price(_base, key))
	if GameState.level_info().x < need:
		return "с %d уровня, %s монет — нажмите, чтобы примерить" % [need, price]
	return "%s монет — нажмите, чтобы примерить" % price


## Ценник на закрытой иконке: жёлтый ярлык с числом внизу (уровень мал —
## серый «N ур.»).
func _price_tag(b: Button, key: String) -> void:
	var need := GameState.item_unlock_level(_base, key)
	var locked := GameState.level_info().x < need
	var tag := Label.new()
	tag.text = "%d ур." % need if locked else _fmt(GameState.item_price(_base, key))
	if _font:
		tag.add_theme_font_override("font", _font)
	tag.add_theme_font_size_override("font_size", 9)
	tag.add_theme_color_override("font_color", UiKit.INK)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.6, 0.6, 0.62) if locked else UiKit.YELLOW
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	tag.add_theme_stylebox_override("normal", sb)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tag.offset_left = 2
	tag.offset_right = -2
	tag.offset_top = -14
	tag.offset_bottom = -2
	b.add_child(tag)


## Поставить купленную/бесплатную деталь по-настоящему; примерка этого
## слота снимается.
func _mount(slot: String, idx: int) -> void:
	_preview.erase(slot)
	if GameState.set_tuning(_base, slot, idx):
		changed.emit()
		rebuild()


# ---- Краски и металлик ----

func _build_paint() -> void:
	var cfg := GameState.tuning_of(_base)
	var shown := preview_cfg()
	var glitter: bool = int(cfg["glitter"]) == 1 and not _preview.has("glitter")
	_box.add_child(_label("КРАСКА   12 цветов × 3 оттенка — бесплатно", 14, Color.WHITE))
	for shade in [1, 2, 3]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		_box.add_child(line)
		for color in CarModelLibrary.ARCADE_COLORS:
			var paints: Array = CarModelLibrary.ARCADE_PAINTS[color]
			var cur: bool = cfg["color"] == color and int(cfg["shade"]) == shade \
					and not glitter and not _preview.has("glitter")
			var b := _swatch(paints[shade - 1], cur, SWATCH)
			b.tooltip_text = color
			b.pressed.connect(_paint.bind(color, shade, false))
			line.add_child(b)

	# Металлик — каждый цвет покупается отдельно (03.09), покрывает три
	# его оттенка: оттенок берётся из выбранного выше. Некупленный —
	# примеряется.
	var owned := GameState.items_owned_count(_base, "metal:")
	_box.add_child(_label("МЕТАЛЛИК  %d из %d   по %s за цвет · зеркальный блик и лак"
			% [owned, CarModelLibrary.ARCADE_COLORS.size(),
					_fmt(GameState.item_price(_base, "metal:red"))], 14, Color.WHITE))
	var mline := HBoxContainer.new()
	mline.add_theme_constant_override("separation", 4)
	_box.add_child(mline)
	var shade_now: int = clampi(int(shown["shade"]), 1, 3)
	for color in CarModelLibrary.ARCADE_COLORS:
		var key := "metal:%s" % color
		var paints: Array = CarModelLibrary.ARCADE_PAINTS[color]
		var cur: bool = cfg["color"] == color and glitter
		var previewed: bool = _preview.has("glitter") and shown["color"] == color
		var b := _swatch(paints[shade_now - 1], cur, CELL, previewed)
		# Белая искра-кант — «металлик», а не обычная краска.
		if not cur and not previewed:
			(b.get_theme_stylebox("normal") as StyleBoxFlat).border_color = \
					Color(1, 1, 1, 0.8)
			(b.get_theme_stylebox("normal") as StyleBoxFlat).set_border_width_all(2)
		if GameState.item_owned(_base, key):
			b.tooltip_text = "Металлик · %s" % color
			b.pressed.connect(_paint.bind(color, shade_now, true))
		else:
			b.modulate = Color(0.7, 0.7, 0.72)
			_price_tag(b, key)
			b.tooltip_text = "Металлик · %s — %s" % [color, _item_hint(key)]
			b.pressed.connect(func() -> void:
				if previewed:
					_try_on("glitter", 1)   # повторный клик — снять
					return
				_preview["color"] = color
				_preview["shade"] = shade_now
				_try_on("glitter", 1))
		mline.add_child(b)


## Перекрасить: цвет, оттенок, металлик (true — только у купленного
## металлика этого цвета, иначе set_tuning откажет и краска будет обычной).
## Примерка металлика при этом снимается.
func _paint(color: String, shade: int, metal: bool) -> void:
	for k in ["color", "shade", "glitter"]:
		_preview.erase(k)
	GameState.set_tuning(_base, "color", color)
	GameState.set_tuning(_base, "shade", shade)
	GameState.set_tuning(_base, "glitter", 1 if metal else 0)
	changed.emit()
	rebuild()


## Краски советских и Unity-машин: бесплатные цвета пака (у машин без
## скинов — одна подпись).
func _build_simple_paint() -> void:
	var colors := CarModelLibrary.colors_for(_base)
	if colors.is_empty():
		_box.add_child(_label("У этой машины один цвет — перекрасить нельзя.",
				14, Color(1, 1, 1, 0.7)))
		return
	_box.add_child(_label("КРАСКА   %d цветов — бесплатно" % colors.size(),
			14, Color.WHITE))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	_box.add_child(line)
	var current: String = GameState.color_of(_base)
	for color in colors:
		var b := _swatch(SWATCH_COLORS.get(color, Color.MAGENTA),
				color == current, SWATCH_BIG)
		b.tooltip_text = String(COLOR_NAMES.get(color, color)).capitalize()
		b.pressed.connect(func() -> void:
			GameState.set_car_color(_base, color)
			changed.emit()
			rebuild())
		line.add_child(b)


## Цвет деталей (колёса, мотор, спойлер, выхлоп) отдельно от кузова:
## «КАК КУЗОВ» или 36 красок пака — бесплатно.
func _build_part_color() -> void:
	var cur := str(GameState.tuning_of(_base)["pcolor"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	var lbl := _label("ЦВЕТ ДЕТАЛЕЙ   диски, мотор, спойлер, выхлоп — бесплатно",
			14, Color.WHITE)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	row.add_child(_mode_button("КАК КУЗОВ", cur.is_empty(),
			func() -> void: _set_free("pcolor", "")))
	_build_spec_rows(cur, func(spec: String) -> void: _set_free("pcolor", spec))


## Цвет двойной полосы: «ТЁМНАЯ» (как в паке) или 36 красок — бесплатно.
func _build_line_color() -> void:
	var cur := str(GameState.tuning_of(_base)["lcolor"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	var lbl := _label("ЦВЕТ ПОЛОСЫ   бесплатно", 14, Color.WHITE)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	row.add_child(_mode_button("ТЁМНАЯ", cur.is_empty(),
			func() -> void: _set_free("lcolor", "")))
	_build_spec_rows(cur, func(spec: String) -> void: _set_free("lcolor", spec))


## Три ряда по 12 квадратиков красок пака; cur — выбранная спецификация.
func _build_spec_rows(cur: String, on_pick: Callable) -> void:
	for shade in [1, 2, 3]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		_box.add_child(line)
		for color in CarModelLibrary.ARCADE_COLORS:
			var spec := "%s%d" % [color, shade]
			var b := _swatch(CarModelLibrary.paint_color(spec), cur == spec, SWATCH)
			b.tooltip_text = spec
			b.pressed.connect(on_pick.bind(spec))
			line.add_child(b)


func _mode_button(text: String, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	UiKit.style_button(b, "teal" if on else "steel", 13)
	b.custom_minimum_size = Vector2(120, 30)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(cb)
	return b


## Бесплатная настройка (цвет деталей/полосы): сразу в профиль.
func _set_free(key: String, value: Variant) -> void:
	if GameState.set_tuning(_base, key, value):
		changed.emit()
		rebuild()


## Квадратик краски: жёлтая рамка — стоит на машине, оранжевая — примерен.
func _swatch(color: Color, current: bool, size: int, previewed := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(5)
	sb.set_border_width_all(3 if current or previewed else 1)
	sb.border_color = PREVIEW_COLOR if previewed \
			else (UiKit.YELLOW if current else Color(0, 0, 0, 0.5))
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, sb)
	return b


# ---- Наклейки и полоса: каждая покупается отдельно ----

func _build_stickers() -> void:
	var cfg := GameState.tuning_of(_base)
	var owned := GameState.items_owned_count(_base, "sticker:")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_box.add_child(row)
	var lbl := _label("НАКЛЕЙКИ  %d из %d   по %s за штуку" % [owned,
			CarModelLibrary.PART_COUNT, _fmt(GameState.item_price(_base, "sticker:1"))],
			14, Color.WHITE)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	# Двойная полоса — отдельный элемент: некупленная примеряется
	# (кнопка оранжевая, пока примерена), купленная — ВКЛ/ВЫКЛ.
	var pb := Button.new()
	pb.custom_minimum_size = Vector2(190, 32)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var line_owned := GameState.item_owned(_base, "line")
	if line_owned:
		var on := int(cfg["line"]) == 1
		UiKit.style_button(pb, "teal" if on else "steel", 13)
		pb.text = "ПОЛОСА: %s" % ("ВКЛ" if on else "ВЫКЛ")
		pb.pressed.connect(func() -> void:
			if GameState.set_tuning(_base, "line", 0 if on else 1):
				changed.emit()
				rebuild())
	else:
		var previewed := _preview.has("line")
		UiKit.style_button(pb, "orange" if previewed else "steel", 13)
		pb.text = ("ПРИМЕРЕНА · %s" if previewed else "ПОЛОСА · %s") \
				% _fmt(GameState.item_price(_base, "line"))
		pb.tooltip_text = "Двойная полоса по кузову — нажмите, чтобы примерить"
		pb.pressed.connect(func() -> void: _try_on("line", 1))
	row.add_child(pb)

	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 4)
	_box.add_child(icons)
	for idx in range(0, CarModelLibrary.PART_COUNT + 1):
		var key := "sticker:%d" % idx
		var b := _icon_button("sticker_%d.png" % idx)
		var mounted: bool = int(cfg["sticker"]) == idx and not _preview.has("sticker")
		var previewed: bool = _preview.has("sticker") and int(_preview["sticker"]) == idx
		var open_ := idx == 0 or GameState.item_owned(_base, key)
		_frame(b, mounted, open_, previewed)
		if open_:
			b.tooltip_text = "Без наклейки" if idx == 0 else "Куплено"
			b.pressed.connect(func() -> void:
				_preview.erase("sticker")
				if GameState.set_tuning(_base, "sticker", idx):
					changed.emit()
					rebuild())
		else:
			_price_tag(b, key)
			b.tooltip_text = _item_hint(key)
			b.pressed.connect(_try_on.bind("sticker", idx))
		icons.add_child(b)
	# Цвет полосы — когда полоса есть (куплена) или примерена.
	if line_owned or _preview.has("line"):
		_build_line_color()


# ---- Мелочи ----

func _icon_button(file: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(CELL, CELL)
	b.icon = load(ICON_DIR + file)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.focus_mode = Control.FOCUS_NONE
	return b


## Рамка иконки: жёлтая — стоит на машине, оранжевая — примерена,
## обычная — куплена, тёмная — закрыта (не куплена).
func _frame(b: Button, mounted: bool, open_: bool, previewed := false) -> void:
	var sb := UiKit.steel_box(6)
	if mounted or previewed:
		sb.set_border_width_all(3)
		sb.border_color = PREVIEW_COLOR if previewed else UiKit.YELLOW
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, sb)
	b.modulate = Color.WHITE if open_ or previewed else Color(0.55, 0.55, 0.6)


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
