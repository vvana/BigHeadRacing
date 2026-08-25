class_name Announcer
extends Control
## Всплывающие анонсы по центру экрана: «ДВОЙНОЕ УБИЙСТВО», «ПОСЛЕДНИЙ
## КРУГ» и т.п. Табличка-«штамп» влетает с ударом (масштаб 1.7 -> 1.0,
## лёгкий случайный наклон), висит и уходит вверх с растворением.
## Два яруса: big — крупные события (по одному, остальные в очереди),
## small — личная мелочь строкой ниже. Живёт в CanvasLayer поверх HUD.

const BIG_Y := 0.24        # вертикаль ЦЕНТРА большого яруса, доля экрана
const SMALL_Y := 0.42      # вертикаль малого яруса (ниже подписи большого)
const BIG_HOLD := 9.0      # сколько большая табличка висит, с
const SMALL_HOLD := 7.0
const QUEUE_MAX := 3       # больше анонсов в очереди не держим

var _big_queue: Array[Dictionary] = []
var _small_queue: Array[Dictionary] = []
var _big_busy := false
var _small_busy := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Крупный анонс: title на табличке kind, sub — строка-пояснение под ней.
func big(title: String, sub := "", kind := "red") -> void:
	_enqueue(_big_queue, {"title": title, "sub": sub, "kind": kind}, true)


## Малый анонс: короткая строка на узкой табличке.
func small(title: String, kind := "steel") -> void:
	_enqueue(_small_queue, {"title": title, "sub": "", "kind": kind}, false)


func _enqueue(queue: Array[Dictionary], item: Dictionary, is_big: bool) -> void:
	if queue.size() >= QUEUE_MAX:
		return
	queue.append(item)
	_pump(is_big)


func _pump(is_big: bool) -> void:
	if is_big:
		if _big_busy or _big_queue.is_empty():
			return
		_big_busy = true
		_show(_big_queue.pop_front(), true)
	else:
		if _small_busy or _small_queue.is_empty():
			return
		_small_busy = true
		_show(_small_queue.pop_front(), false)


func _show(item: Dictionary, is_big: bool) -> void:
	var kind: String = item["kind"]
	var title: String = item["title"]
	var font := UiKit.font()
	var font_size := 42 if is_big else 20
	var text_w := font.get_string_size(title,
			HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	var plate_w := maxf(text_w + (120.0 if is_big else 70.0),
			360.0 if is_big else 220.0)
	var plate_h := 100.0 if is_big else 48.0

	# Корень анонса — для масштаба/наклона вокруг центра.
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.size = Vector2(plate_w, plate_h)
	root.anchor_left = 0.5
	root.anchor_right = 0.5
	root.anchor_top = BIG_Y if is_big else SMALL_Y
	root.anchor_bottom = root.anchor_top
	root.offset_left = -plate_w * 0.5
	root.offset_right = plate_w * 0.5
	root.offset_top = -plate_h * 0.5
	root.offset_bottom = plate_h * 0.5
	root.pivot_offset = Vector2(plate_w, plate_h) * 0.5

	var plate := UiKit.plate(root, kind, Vector2.ZERO,
			Vector2(plate_w, plate_h), not is_big)
	if is_big:
		# Подпись стиля: аварийная лента по нижней кромке таблички.
		UiKit.hazard(plate, Vector2(14, plate_h - 22),
				Vector2(plate_w - 28, 12), 0.9)
	var text_col := UiKit.text_on(kind)
	var title_l := UiKit.plate_label(plate, title, font_size, text_col,
			7 if text_col == Color.WHITE else 0)
	if is_big:
		title_l.offset_bottom = -10.0  # текст чуть выше — лента снизу

	var sub: String = item["sub"]
	if sub != "":
		var sub_l := UiKit.label(root, sub, 18, Color.WHITE, 6)
		sub_l.anchor_top = 1.0
		sub_l.anchor_bottom = 1.0
		sub_l.anchor_right = 1.0
		sub_l.offset_top = 8.0
		sub_l.offset_bottom = 36.0
		sub_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Влёт-«штамп»: крупнее и прозрачно -> удар в масштаб 1.0 с лёгким
	# случайным наклоном; затем пауза и уход вверх с растворением.
	var tilt := deg_to_rad(randf_range(1.0, 2.2)) \
			* (1.0 if randf() < 0.5 else -1.0)
	root.modulate.a = 0.0
	root.scale = Vector2(1.7, 1.7)
	root.rotation = tilt * 3.0
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(root, "modulate:a", 1.0, 0.10)
	tw.tween_property(root, "scale", Vector2.ONE, 0.26) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "rotation", tilt, 0.26)
	tw.set_parallel(false)
	tw.tween_interval(BIG_HOLD if is_big else SMALL_HOLD)
	tw.set_parallel(true)
	tw.tween_property(root, "modulate:a", 0.0, 0.28)
	tw.tween_property(root, "position:y", root.position.y - 46.0, 0.28) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.set_parallel(false)
	tw.tween_callback(root.queue_free)
	tw.tween_callback(_on_done.bind(is_big))


func _on_done(is_big: bool) -> void:
	if is_big:
		_big_busy = false
	else:
		_small_busy = false
	_pump(is_big)
