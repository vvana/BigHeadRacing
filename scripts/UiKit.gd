class_name UiKit
extends RefCounted
## «Гаражный» стиль интерфейса (по референсам в корне проекта):
## эмалевые таблички с заклёпками, аварийные жёлто-чёрные полосы,
## индустриальный шрифт Russo One. Ассеты в assets/ui/garage
## генерируются скриптом tools/gen_ui_assets.py.

const INK := Color8(23, 27, 32)          # чернильный — текст на эмали
const STEEL := Color8(38, 43, 49)        # тёмная сталь
const RIM := Color8(90, 98, 107)         # металлический кант
const ENAMEL := Color8(239, 232, 216)    # белая эмаль
const YELLOW := Color8(242, 194, 28)
const ORANGE := Color8(232, 100, 27)
const RED := Color8(207, 51, 39)
const TEAL := Color8(43, 191, 174)
const GREEN_ME := Color(0.45, 1.0, 0.55)     # «свой» цвет меток
const ORANGE_RIVAL := Color(1.0, 0.65, 0.25) # цвет соперника

const FONT_PATH := "res://assets/ui/RussoOne.ttf"
const DIR := "res://assets/ui/garage/"

## Табличка тёмная (текст светлый) или эмалевая (текст чернильный)?
const DARK_PLATES := ["steel", "red", "orange", "teal"]


static func font() -> FontFile:
	return load(FONT_PATH)


## Табличка-девятислайс. kind: white|yellow|orange|red|teal|steel.
## small=true — вариант 256x96 с полями 20 (для панелей HUD), иначе
## 384x192 с полями 40 (крупные баннеры).
static func plate(parent: Node, kind: String, pos: Vector2,
		size: Vector2, small := true) -> NinePatchRect:
	var p := NinePatchRect.new()
	p.texture = load(DIR + "plate_%s%s.png" % [kind, "_s" if small else ""])
	var m := 20 if small else 40
	p.patch_margin_left = m
	p.patch_margin_right = m
	p.patch_margin_top = m
	p.patch_margin_bottom = m
	p.position = pos
	p.size = size
	parent.add_child(p)
	return p


## Цвет текста, читаемый на этой табличке.
static func text_on(kind: String) -> Color:
	return Color.WHITE if kind in DARK_PLATES else INK


## Полоса аварийных полос (тайлится по горизонтали).
static func hazard(parent: Node, pos: Vector2, size: Vector2,
		dim := 1.0) -> TextureRect:
	var h := TextureRect.new()
	h.texture = load(DIR + "hazard.png")
	h.stretch_mode = TextureRect.STRETCH_TILE
	h.position = pos
	h.size = size
	h.modulate = Color(dim, dim, dim)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(h)
	return h


## Шахматная лента (финишная).
static func checker(parent: Node, pos: Vector2, size: Vector2) -> TextureRect:
	var c := TextureRect.new()
	c.texture = load(DIR + "checker.png")
	c.stretch_mode = TextureRect.STRETCH_TILE
	c.position = pos
	c.size = size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


## Надпись Russo One. Обводка чернильная (на эмали текст и так
## чернильный — обводку не ставим, outline=0).
static func label(parent: Node, txt: String, font_size: int,
		color := Color.WHITE, outline := 0) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", INK)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## Надпись, растянутая на всю родительскую табличку, по центру.
static func plate_label(parent: Control, txt: String, font_size: int,
		color := Color.WHITE, outline := 0) -> Label:
	var l := label(parent, txt, font_size, color, outline)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## Стили кнопки: эмалевая табличка + осветление на hover, затемнение
## при нажатии. Текст ставит вызывающий (цвет — text_on(kind)).
static func style_button(btn: Button, kind: String, font_size: int) -> void:
	var tex: Texture2D = load(DIR + "plate_%s_s.png" % kind)
	for state in ["normal", "hover", "pressed"]:
		var st := StyleBoxTexture.new()
		st.texture = tex
		st.set_texture_margin_all(20.0)
		if state == "hover":
			st.modulate_color = Color(1.12, 1.12, 1.12)
		elif state == "pressed":
			st.modulate_color = Color(0.78, 0.78, 0.78)
		btn.add_theme_stylebox_override(state, st)
	btn.add_theme_font_override("font", font())
	btn.add_theme_font_size_override("font_size", font_size)
	var col := text_on(kind)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		btn.add_theme_color_override(state, col)
	if col == Color.WHITE:
		btn.add_theme_constant_override("outline_size", 5)
		btn.add_theme_color_override("font_outline_color", INK)
	btn.focus_mode = Control.FOCUS_NONE


## Плоский стальной стиль для мелких элементов (лента событий и т.п.).
static func steel_box(radius := 6, alpha := 0.92) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(STEEL.r, STEEL.g, STEEL.b, alpha)
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = Color(RIM.r, RIM.g, RIM.b, 0.55)
	return sb
