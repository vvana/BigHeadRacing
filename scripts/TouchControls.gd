class_name TouchControls
extends CanvasLayer
## Экранные кнопки для телефона (Android, 09.09.2026): слева ГАЗ и ТОРМОЗ,
## справа руль ◀ ▶ и БОНУС (текущее оружие), в углу ✕ — в гараж, внизу по
## центру — кнопка-подсказка «СТАРТ» (лобби) / «В ГАРАЖ» (после финиша).
##
## Кнопки НЕ Button: BaseButton в Godot 4 реагирует только на мышь, а мышь
## эмулируется лишь из ПЕРВОГО пальца — второй палец (руль при зажатом газе)
## обычной кнопке не виден. Поэтому слой сам ловит InputEventScreenTouch /
## ScreenDrag (и мышь — для стендов на столе), ведёт таблицу «палец → кнопка»
## и НАЖИМАЕТ ДЕЙСТВИЯ InputMap через Input.action_press/action_release —
## Car._player_control и Main опрашивают те же действия, что и с клавиатуры,
## так что езда, оружие, Esc и Enter не знают, откуда пришло нажатие.
## Палец, уползший с кнопки, её НЕ отпускает (как в мобильных гонках: руль
## держится, пока палец на экране), а переехавший на соседнюю — переключает.
##
## Показывается на android/ios или с аргументом `--touch` (стенды на столе):
## `godot --path . res://tools/ShotTouch.tscn -- <папка> --touch`.

const HOLD_ACTIONS := ["accelerate", "brake", "steer_left", "steer_right", "fire"]
const SLACK := 14.0          # допуск попадания за край круга, px
const TAP_HOLD_FRAMES := 2   # сколько кадров держать «нажатие» ✕ / СТАРТ

## Описание кнопки. kind: "gas" | "brake" | "left" | "right" | "bonus" |
## "exit" | "tap". Круглые задаются центром и радиусом, прямоугольные (exit,
## tap) — rect.
class Btn:
	var kind: String
	var action: String
	var center := Vector2.ZERO
	var radius := 0.0
	var rect := Rect2()
	var round := true
	var label := ""
	var color := Color.WHITE
	var visible := true

	func hit(p: Vector2) -> bool:
		if not visible:
			return false
		if round:
			return p.distance_to(center) <= radius + SLACK
		return rect.grow(SLACK * 0.5).has_point(p)

var _btns: Array[Btn] = []
var _by_kind := {}
var _pointers := {}           # id пальца (-1 — мышь) → Btn или null
var _held := {}               # action → bool (что сейчас нажато нами)
var _tap_release := {}        # action → кадров до action_release
var _bonus_icon: Texture2D
var _overlay: Control
var _font: Font
var _exit_shift := 0.0        # сдвиг ✕ влево от правого края (под мини-карту)
var _tap_text := ""


## Нужны ли экранные кнопки: телефон/планшет или явная просьба `--touch`.
static func wanted() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") \
			or "--touch" in OS.get_cmdline_user_args()


## exit_shift — на сколько px отодвинуть ✕ от правого края (в гонке справа
## сверху мини-карта, в футболе угол свободен).
func _init(exit_shift := 0.0) -> void:
	_exit_shift = exit_shift
	layer = 20


func _ready() -> void:
	_font = UiKit.font()
	_add("gas", "accelerate", "ГАЗ", Color8(72, 190, 90))
	_add("brake", "brake", "ТОРМОЗ", Color8(207, 51, 39))
	_add("left", "steer_left", "", Color8(90, 98, 107))
	_add("right", "steer_right", "", Color8(90, 98, 107))
	_add("bonus", "fire", "БОНУС", Color8(242, 194, 28))
	_add("exit", "ui_cancel", "", Color8(207, 51, 39), false)
	_add("tap", "ui_accept", "", Color8(242, 194, 28), false)
	_by_kind["tap"].visible = false
	_overlay = Control.new()
	_overlay.name = "TouchOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_buttons)
	add_child(_overlay)
	_layout()
	get_viewport().size_changed.connect(_layout)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _add(kind: String, action: String, label: String, color: Color,
		round := true) -> void:
	var b := Btn.new()
	b.kind = kind
	b.action = action
	b.label = label
	b.color = color
	b.round = round
	_btns.append(b)
	_by_kind[kind] = b


## Раскладка от размера видимой области (не от 1280×720 жёстко — при
## stretch/aspect=expand полотно шире).
func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	var w := s.x
	var h := s.y
	_set_round("brake", Vector2(104, h - 96), 58)
	_set_round("gas", Vector2(252, h - 112), 74)
	# Руль крупнее (r76, просьба 09.09), бонус НАД ▶ (по его оси, просьба
	# 09.09): верх круга (h−316 = 404) ниже пятой строки ленты событий (~388).
	_set_round("left", Vector2(w - 272, h - 96), 76)
	_set_round("right", Vector2(w - 96, h - 96), 76)
	_set_round("bonus", Vector2(w - 96, h - 256), 60)
	var ex: Btn = _by_kind["exit"]
	ex.rect = Rect2(Vector2(w - 16 - _exit_shift - 48, 12), Vector2(48, 48))
	var tp: Btn = _by_kind["tap"]
	tp.rect = Rect2(Vector2(w * 0.5 - 130, h - 92), Vector2(260, 64))
	if _overlay:
		_overlay.queue_redraw()


func _set_round(kind: String, c: Vector2, r: float) -> void:
	var b: Btn = _by_kind[kind]
	b.center = c
	b.radius = r


## Значок текущего оружия на кнопке БОНУС (null — надпись «БОНУС»).
func set_bonus_icon(tex: Texture2D) -> void:
	if _bonus_icon == tex:
		return
	_bonus_icon = tex
	_overlay.queue_redraw()


## Кнопка-подсказка внизу по центру: "" — спрятать и показать езду;
## текст («СТАРТ», «В ГАРАЖ») — показать её (нажатие = ui_accept) и
## спрятать кнопки езды (машина в лобби/после финиша всё равно стоит).
func show_tap(text: String) -> void:
	if _tap_text == text:
		return
	_tap_text = text
	var driving := text.is_empty()
	for k in ["gas", "brake", "left", "right", "bonus"]:
		_by_kind[k].visible = driving
	_by_kind["tap"].visible = not driving
	_by_kind["tap"].label = text
	if not driving:
		# Кнопки езды исчезли — пальцы на них больше ничего не держат.
		for id in _pointers.keys():
			var b: Btn = _pointers[id]
			if b != null and not b.visible:
				_pointers[id] = null
		_apply_held()
	_overlay.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_pointer_down(t.index, t.position)
		else:
			_pointer_up(t.index, t.position)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_pointer_move(d.index, d.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_pointer_down(-1, mb.position)
		else:
			_pointer_up(-1, mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_pointer_move(-1, mm.position)


func _hit(p: Vector2) -> Btn:
	for b: Btn in _btns:
		if b.hit(p):
			return b
	return null


func _pointer_down(id: int, p: Vector2) -> void:
	var b := _hit(p)
	_pointers[id] = b
	if b != null:
		get_viewport().set_input_as_handled()
		_apply_held()
		_overlay.queue_redraw()


func _pointer_move(id: int, p: Vector2) -> void:
	if not _pointers.has(id):
		return
	var prev: Btn = _pointers[id]
	var b := _hit(p)
	# Уполз с кнопки — держим прежнюю (руль не срывается у края круга);
	# переехал на соседнюю — переключаем.
	if b == null:
		b = prev
	if b != null:
		get_viewport().set_input_as_handled()
	if b != prev:
		_pointers[id] = b
		_apply_held()
		_overlay.queue_redraw()


func _pointer_up(id: int, p: Vector2) -> void:
	if not _pointers.has(id):
		return
	var b: Btn = _pointers[id]
	_pointers.erase(id)
	if b == null:
		return
	get_viewport().set_input_as_handled()
	# ✕ и СТАРТ — по отпусканию внутри кнопки, одним «нажатием» на кадр.
	if not b.round and b.hit(p):
		Input.action_press(b.action)
		_tap_release[b.action] = TAP_HOLD_FRAMES
	_apply_held()
	_overlay.queue_redraw()


## Пересчитать, какие действия держим: действие нажато, если хоть один
## палец лежит на его кнопке. Двойное нажатие (палец + эмулированная из него
## мышь) сюда не доходит — состояние выводится из множества, а не считается.
func _apply_held() -> void:
	var now := {}
	for id in _pointers:
		var b: Btn = _pointers[id]
		if b != null and b.round and b.visible:
			now[b.action] = true
	for a: String in HOLD_ACTIONS:
		var want: bool = now.has(a)
		var have: bool = _held.get(a, false)
		if want and not have:
			Input.action_press(a)
		elif have and not want:
			Input.action_release(a)
		_held[a] = want


func _process(_delta: float) -> void:
	for a in _tap_release.keys():
		_tap_release[a] -= 1
		if _tap_release[a] <= 0:
			Input.action_release(a)
			_tap_release.erase(a)


func _exit_tree() -> void:
	# Сцена уходит (в гараж) — не оставлять зажатый газ следующему заезду.
	for a: String in HOLD_ACTIONS:
		if _held.get(a, false):
			Input.action_release(a)
	for a in _tap_release:
		Input.action_release(a)
	_held.clear()
	_tap_release.clear()


func is_pressed(kind: String) -> bool:
	var b: Btn = _by_kind[kind]
	for id in _pointers:
		if _pointers[id] == b:
			return true
	return false


func _draw_buttons() -> void:
	for b: Btn in _btns:
		if not b.visible:
			continue
		var down := is_pressed(b.kind)
		if b.round:
			_draw_round(b, down)
		else:
			_draw_rect_btn(b, down)


func _draw_round(b: Btn, down: bool) -> void:
	var c := b.center
	var r := b.radius
	var fill := Color(b.color, 0.82) if down \
			else Color(UiKit.STEEL, 0.55).lerp(Color(b.color, 0.55), 0.35)
	_overlay.draw_circle(c, r, fill)
	var rim := UiKit.YELLOW if down else Color(UiKit.RIM, 0.9)
	_overlay.draw_arc(c, r, 0.0, TAU, 48, rim, 4.0, true)
	_overlay.draw_arc(c, r - 7.0, 0.0, TAU, 48, Color(1, 1, 1, 0.18), 1.5, true)
	match b.kind:
		"left", "right":
			var dir := -1.0 if b.kind == "left" else 1.0
			var a := r * 0.42
			var pts := PackedVector2Array([
					c + Vector2(dir * a, 0.0),
					c + Vector2(-dir * a * 0.7, -a * 0.95),
					c + Vector2(-dir * a * 0.7, a * 0.95)])
			_overlay.draw_colored_polygon(pts, Color.WHITE)
			_overlay.draw_polyline(pts + PackedVector2Array([pts[0]]),
					UiKit.INK, 3.0, true)
		"bonus":
			if _bonus_icon != null:
				var side := r * 1.3
				_overlay.draw_texture_rect(_bonus_icon,
						Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)),
						false)
			else:
				_text(c, b.label, 18)
		_:
			_text(c, b.label, 22 if b.kind == "gas" else 16)


func _draw_rect_btn(b: Btn, down: bool) -> void:
	var rc := b.rect
	var sb := UiKit.steel_box(10, 0.9 if down else 0.6)
	if down:
		sb.bg_color = Color(b.color, 0.85)
	sb.border_color = UiKit.YELLOW if down else Color(UiKit.RIM, 0.9)
	sb.set_border_width_all(3)
	_overlay.draw_style_box(sb, rc)
	if b.kind == "exit":
		var m := rc.get_center()
		var k := 11.0
		_overlay.draw_line(m + Vector2(-k, -k), m + Vector2(k, k), Color.WHITE, 5.0, true)
		_overlay.draw_line(m + Vector2(-k, k), m + Vector2(k, -k), Color.WHITE, 5.0, true)
	else:
		_text(rc.get_center(), b.label, 24)


func _text(c: Vector2, txt: String, fs: int) -> void:
	if txt.is_empty():
		return
	var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	var pos := Vector2(c.x - w * 0.5,
			c.y + (_font.get_ascent(fs) - _font.get_descent(fs)) * 0.5)
	_overlay.draw_string_outline(_font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT,
			-1, fs, 6, UiKit.INK)
	_overlay.draw_string(_font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color.WHITE)
