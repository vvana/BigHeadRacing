class_name OilSlick
extends Area3D
## Масляное пятно: тёмная клякса на дороге. Наехавшую машину ЗАНОСИТ
## всерьёз: случайная закрутка, почти нулевое сцепление и буксующие
## колёса (ни разогнаться, ни оттормозиться) на slip_duration.
## Хозяина не трогает первые 0.7 с, живёт ограниченное время.
##
## ФОРМА (просьба 09.09: «используй кляксу; если наехать на область
## кляксы — эффект действует»): срабатывает не круг, а ТЕЛО КАРТИНКИ.
## Маска MASK_N×MASK_N бит снята с assets/fx/oil_splat.png скриптом
## tools/make_oil_splat.py (клетка = 1, если картинка там непрозрачна;
## мелкая крошка брызг в маску не попадает). Area ловит машины во всём
## квадрате картинки, а попадание в чёрное проверяет covers() каждый
## физический кадр; эффект — на ВХОДЕ в чёрное (раньше — на входе в круг),
## сидящую в пятне машину повторно не бьёт. Картинка и маска в одной
## системе координат: поворот «случайный» задан всему узлу, не мешу.

## inert — «только картинка»: такую копию порождает КЛИЕНТ по событию с
## сервера. Считает попадания и толчки сервер, его результат приезжает
## в снимках; работай копия по-настоящему, машину било бы дважды.
var inert := false
var dropper: Car = null
## Ступени масла (магазин, 08.09): size_mult — пятно крупнее (I: ×1.15);
## slow_only — ниже II ступени пятно ТОЛЬКО ЗАМЕДЛЯЕТ (Car.apply_oil_slow),
## занос с закруткой — со II (спецификация игрока 04.09: «масло I —
## только замедляет; II — как сейчас»).
var size_mult := 1.0
var slow_only := false

## Сторона картинки, м (× size_mult). Тело кляксы занимает ~60 % стороны:
## радиус срабатывания по телу ≈ 1.8–2.2 м — как прежний круг 2.4 с учётом
## того, что теперь считается центр машины, а не её кузов.
const QUAD := 6.4
const MASK_N := 48
const MASK_HEX := "00000000000000000000000000000000000000000000000000100000200000330000600000194000780000084000f000001c3278e00000063ffce00000c7fffdc080000fffffc000004fffffe000042ffffff6100e1ffffff60413bffffff88f00fffffff03800fffffff1f819ffffffff801fffffffff021bffffffff8003ffffffff8101e7ffffffbf1b03ffffffc01e03ffffffc40607ffffffc4000fffffffe0000fffffff80001fffffff08003fffffff0c107ffffffe0c007ffffff80006fffffffc80011ffffff98004fffffff88011fffffff80001fffffdd800023ffffecc000e071ffdee0008001ff9730000000ffbb9c000000fb3d5e0000009b0d08000006c06080000005c060800000018200000000010000000000000000000"
static var _mask := PackedByteArray()

var _arm := 0.7
var _life := 15.0
var _inside := {}   # instance id машины → была ли в теле кляксы прошлым кадром


func _ready() -> void:
	if _mask.is_empty():
		_mask = MASK_HEX.hex_decode()
	collision_layer = 0
	collision_mask = 0b100  # только машины (слой 4)
	monitorable = false
	# Поворот — «случайный», но БЕЗ randf: не сдвигать поток случайных
	# чисел у стендов с seed (правило журнала). Крутим ВЕСЬ узел: так
	# картинка, зона Area и маска covers() совпадают без пересчёта.
	rotation.y = float(get_instance_id() % 6283) * 0.001

	var side := QUAD * size_mult
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(side, 0.6, side)
	col.shape = shape
	add_child(col)

	# Клякса (09.09, по референсу игрока): плотное тело, рваный край,
	# лучи брызг и капли. Текстура белая — красится в чёрный, металлик и
	# низкая шероховатость дают масляный блик.
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(side, side)
	quad.orientation = PlaneMesh.FACE_Y
	mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/fx/oil_splat.png")
	mat.albedo_color = Color(0.07, 0.05, 0.1, 0.94)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	mat.metallic = 0.6
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

	if inert:
		set_deferred("monitoring", false)


func _physics_process(delta: float) -> void:
	_arm = maxf(0.0, _arm - delta)
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if inert:
		return
	for body in get_overlapping_bodies():
		var car := body as Car
		if car == null:
			continue
		var id := car.get_instance_id()
		var hit := covers(car.global_position)
		if hit and not bool(_inside.get(id, false)):
			_on_body(car)
		_inside[id] = hit


## Накрывает ли ТЕЛО кляксы (маска картинки) точку мира. Квад FACE_Y:
## u растёт вдоль +x узла, v — вдоль +z (верх картинки смотрит в −z),
## см. стенд tools/test_oil_mask.gd — он сверяет это с самим мешем.
func covers(world_pos: Vector3) -> bool:
	var l := to_local(world_pos)
	var side := QUAD * size_mult
	var u := 0.5 + l.x / side
	var v := 0.5 + l.z / side
	if u < 0.0 or u >= 1.0 or v < 0.0 or v >= 1.0:
		return false
	var bit := int(v * MASK_N) * MASK_N + int(u * MASK_N)
	return ((_mask[bit >> 3] >> (7 - (bit & 7))) & 1) == 1


func _on_body(body: Node3D) -> void:
	var car := body as Car
	if car == null or not car.alive:
		return
	if car == dropper and _arm > 0.0:
		return
	# Щит (08.09): под щитом пятно не действует — ни заноса, ни замедления.
	if car.is_shielded():
		return
	if slow_only:
		# Ниже II ступени — только замедление, без закрутки.
		if car.oil_slow_left() <= 0.0:
			car.notify_hit_by(dropper, Weapons.OIL)
		car.apply_oil_slow()
		return
	# В ленту — только если занос реально начнётся (повторный наезд во
	# время заноса apply_oil_slip игнорирует, событие было бы ложным).
	if car._slip_time <= 0.0:
		car.notify_hit_by(dropper, Weapons.OIL)
	car.apply_oil_slip()
