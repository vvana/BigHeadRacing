class_name Minimap
extends Control
## Мини-карта в углу экрана: полотно трассы в плане и точки-машины.
##
## Ориентация СОВПАДАЕТ с картинкой: план поворачивается на угол изокамеры
## (yaw 45°) и сжимается по вертикали (наклон -32°), поэтому «вверх на
## карте» = «вверх на экране» — иначе игрок каждый раз пересчитывал бы
## повороты в уме.
##
## Цвета точек те же, что у стрелок над машинами (Main._attach_marker):
## своя — зелёная, живой соперник — оранжевый, боты — светло-серые.
## Своя машина рисуется треугольником по направлению носа, остальные —
## кружками; выбывшая (взорванная) машина гаснет до полупрозрачной.

const PAD := 12.0                  # отступ трассы от края панели, px
const YAW := 45.0                  # = IsoCamera.yaw_deg
# Сжатие карты по вертикали = sin(наклона камеры), наклон -32°. Это не
# произвол: горизонтальный сдвиг на экране изокамеры поднимается ровно на
# sin(наклон). Со взятым сгоряча косинусом (0.85) направления на карте
# расходились с экранными на 12° — ловится тестом TestMinimap.
const SQUISH := 0.53               # = sin(32°)
const ROAD_COLOR := Color(0.42, 0.46, 0.58, 0.95)
const EDGE_COLOR := Color(0.85, 0.28, 0.28, 0.75)   # красные ограждения
const START_COLOR := Color(1, 1, 1, 0.85)
const OWN_COLOR := Color(0.15, 0.95, 0.25)
const RIVAL_COLOR := Color(1.0, 0.55, 0.1)
const BOT_COLOR := Color(0.62, 0.68, 0.82)
const OUTLINE := Color(0.05, 0.06, 0.12, 0.9)
const DOT_R := 3.2                 # радиус точки бота/соперника, px
const OWN_R := 5.0                 # «радиус» треугольника своей машины, px

var cars: Array[Car] = []
var my_index := 0
var rivals := {}                   # слоты живых соперников (слот → true)
# Цвет кромок полотна: красный — ограждения; на трассе без стен (песчаная)
# кромка рисуется песочной, красные «стены» на карте врали бы.
var edge_color := EDGE_COLOR

# Ось и края трассы в «плоскости карты» (метры, уже повёрнуты под камеру).
var _axis := PackedVector2Array()
var _left := PackedVector2Array()
var _right := PackedVector2Array()
var _min := Vector2.ZERO
var _max := Vector2.ZERO
var _scale := 1.0
var _shift := Vector2.ZERO         # сдвиг, чтобы трасса села по центру панели
# Полотно, готовое к отрисовке одним вызовом (пересчитывается при resize).
var _road_pts := PackedVector2Array()
var _road_idx := PackedInt32Array()
var _road_col := PackedColorArray()


## Взять контур у трассы. cars — тот же массив, что у Main (по ссылке),
## так что дальше карта сама видит все машины.
func setup(track: TrackBuilder, cars_ref: Array[Car]) -> void:
	cars = cars_ref
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not track.has_walls:
		edge_color = Color(0.93, 0.85, 0.6, 0.7)
	elif track.kind == TrackBuilder.KIND_NEON:
		# Ночной город: кромки на карте в цвет неоновых трубок.
		edge_color = Color(0.25, 0.95, 1.0, 0.85)
	var s: Dictionary = track.plan_samples()
	var pts: PackedVector2Array = s["points"]
	var half: PackedFloat32Array = s["half"]
	var n := pts.size()
	if n < 3:
		return
	for i in n:
		var cur := pts[i]
		var nxt := pts[(i + 1) % n]
		var dir := (nxt - cur).normalized()
		# Перпендикуляр берём в МИРОВОМ плане, а не после поворота: сжатие
		# по вертикали неравномерно тянет углы, и «перпендикуляр» повёрнутой
		# оси перестал бы быть перпендикуляром полотна.
		var perp := Vector2(-dir.y, dir.x) * half[i]
		_axis.append(_to_map(cur))
		_left.append(_to_map(cur + perp))
		_right.append(_to_map(cur - perp))
	_min = _left[0]
	_max = _left[0]
	for p: Vector2 in _left + _right:
		_min = _min.min(p)
		_max = _max.max(p)
	resized.connect(_rebuild)
	_rebuild()


## Мир (X,Z) → плоскость карты: поворот на угол камеры + сжатие по вертикали.
static func _to_map(p: Vector2) -> Vector2:
	var a := deg_to_rad(YAW)
	return Vector2(p.x * cos(a) - p.y * sin(a),
			(p.x * sin(a) + p.y * cos(a)) * SQUISH)


## Метры карты → пиксели панели.
func _to_px(p: Vector2) -> Vector2:
	return (p - _min) * _scale + _shift


## Точка мира → пиксели панели (для машин и любых меток).
func world_to_px(world: Vector3) -> Vector2:
	return _to_px(_to_map(Vector2(world.x, world.z)))


## Подогнать трассу под размер панели и собрать полотно из квадов.
func _rebuild() -> void:
	# До первой раскладки размер панели нулевой — считать масштаб не по чему.
	# Придёт сигнал resized, пересоберёмся.
	if _axis.is_empty() or size.x < 8.0 or size.y < 8.0:
		return
	var span := _max - _min
	var box := size - Vector2(PAD, PAD) * 2.0
	_scale = minf(box.x / maxf(span.x, 0.001), box.y / maxf(span.y, 0.001))
	_shift = (size - span * _scale) * 0.5
	_road_pts = PackedVector2Array()
	_road_idx = PackedInt32Array()
	_road_col = PackedColorArray()
	var n := _axis.size()
	for i in n:
		_road_pts.append(_to_px(_left[i]))
		_road_pts.append(_to_px(_right[i]))
		_road_col.append(ROAD_COLOR)
		_road_col.append(ROAD_COLOR)
	for i in n:
		# Квад между сэмплами i и i+1 (последний замыкает круг) — двумя
		# треугольниками, одним вызовом на всё полотно.
		var a := i * 2
		var b := ((i + 1) % n) * 2
		_road_idx.append_array([a, a + 1, b + 1, a, b + 1, b])
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _road_idx.is_empty():
		return
	RenderingServer.canvas_item_add_triangle_array(
			get_canvas_item(), _road_idx, _road_pts, _road_col)
	# Кромки полотна по обеим сторонам (красные — где стоят ограждения).
	_draw_loop(_left, edge_color)
	_draw_loop(_right, edge_color)
	# Стартовая линия — поперёк полотна в нулевой точке круга.
	draw_line(_to_px(_left[0]), _to_px(_right[0]), START_COLOR, 2.0, true)

	# Своя машина рисуется ПОСЛЕДНЕЙ: на старте все стоят кучей, и точка
	# бота накрывала бы игрока — себя на карте было не найти.
	for i in cars.size():
		if i == my_index:
			continue
		var car := cars[i]
		if car == null or not is_instance_valid(car):
			continue
		var color := RIVAL_COLOR if rivals.has(i) else BOT_COLOR
		if not car.alive:
			color.a = 0.35
		var p := world_to_px(car.global_position)
		draw_circle(p, DOT_R + 1.4, OUTLINE)
		draw_circle(p, DOT_R, color)

	if my_index >= 0 and my_index < cars.size():
		var me := cars[my_index]
		if me != null and is_instance_valid(me):
			var color := OWN_COLOR
			if not me.alive:
				color.a = 0.35
			_draw_arrow(world_to_px(me.global_position),
					me.global_transform.basis.z * -1.0, color)


func _draw_loop(pts: PackedVector2Array, color: Color) -> void:
	var line := PackedVector2Array()
	for p: Vector2 in pts:
		line.append(_to_px(p))
	line.append(line[0])
	draw_polyline(line, color, 1.5, true)


## Своя машина — треугольник носом по ходу движения (направление тоже
## пересчитано в плоскость карты, иначе стрелка врала бы на 45°).
func _draw_arrow(at: Vector2, forward: Vector3, color: Color) -> void:
	var dir := _to_map(Vector2(forward.x, forward.z))
	if dir.length() < 0.001:
		dir = Vector2.UP
	dir = dir.normalized()
	var side := Vector2(-dir.y, dir.x)
	var tri := PackedVector2Array([
		at + dir * OWN_R * 1.5,
		at - dir * OWN_R * 0.9 + side * OWN_R * 0.9,
		at - dir * OWN_R * 0.9 - side * OWN_R * 0.9,
	])
	var wide := PackedVector2Array()
	for p: Vector2 in tri:
		wide.append(at + (p - at) * 1.35)
	draw_colored_polygon(wide, OUTLINE)
	draw_colored_polygon(tri, color)
