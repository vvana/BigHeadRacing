class_name Airstrike
extends Node3D
## Авиаудар по лидеру гонки: на трассе ПЕРЕД первым появляются тени от
## ракет, через секунду в них падают ракеты — все машины, оказавшиеся
## на тенях, уничтожаются.

const SHADOW_DELAY := 1.0   # от появления тени до падения ракеты, с
const HIT_RADIUS := 3.2     # радиус поражения одной ракеты, м
const SHADOW_RADIUS := 0.9  # радиус метки-тени на асфальте, м
const FALL_HEIGHT := 40.0   # с какой высоты падают ракеты, м
const FALL_SIDE := 26.0     # горизонтальный отлёт точки старта, м
const AHEAD := [10.0, 16.0, 22.0, 28.0]  # тени вдоль оси перед лидером, м

## inert — «только картинка»: такую копию порождает КЛИЕНТ по событию с
## сервера. Считает попадания и толчки сервер, его результат приезжает
## в снимках; работай копия по-настоящему, машину било бы дважды.
var inert := false
var track: TrackBuilder = null
var target: Car = null
var attacker: Car = null   # кто вызвал удар — для ленты событий
## Готовые точки падения (инертная копия на клиенте, протокол 18): сервер
## прислал, где на самом деле рвануло, — сами ничего не выбираем.
var preset_spots := PackedVector3Array()
## Ступени авиаудара (магазин, 08.09; спецификация игрока 04.09):
## rockets — сколько ракет (I — две, II — три, III — четыре); lead — со II
## тени ложатся ПО ТРАЕКТОРИИ едущих впереди соперников с упреждением (а
## если впереди никого — по едущим сзади), см. _lead_spots; hit_mult —
## радиус воронки (I: ×1.15).
var rockets := 2
var lead := false
var hit_mult := 1.0

var _spots: Array[Vector3] = []
var _shadows: Array[MeshInstance3D] = []
var _rockets: Array[Node3D] = []
var _fall_offset := Vector3.ZERO  # старт ракеты относительно точки удара
var _timer := SHADOW_DELAY


func _ready() -> void:
	if target == null and preset_spots.is_empty():
		queue_free()
		return
	# Ракеты прилетают наклонно «из-за верхнего края экрана»: старт смещён
	# по горизонтали вдоль взгляда камеры (изокамера не вращается — чем
	# дальше точка по взгляду, тем выше она на экране) плюс высоко вверх.
	# Без камеры (headless-тесты) — фиксированное направление изокамеры.
	var screen_top := Vector3(-0.7071, 0.0, -0.7071)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var f := -cam.global_transform.basis.z
		f.y = 0.0
		if f.length_squared() > 1e-4:
			screen_top = f.normalized()
	_fall_offset = Vector3.UP * FALL_HEIGHT + screen_top * FALL_SIDE
	if not preset_spots.is_empty():
		for pos in preset_spots:
			_spots.append(pos)
			_shadows.append(_make_shadow(pos))
			_rockets.append(_make_rocket(pos))
		return
	# Без трассы (футбольная арена): тени ложатся по ХОДУ ДВИЖЕНИЯ цели —
	# от неё самой и вперёд, с разбросом вбок. Стоячую цель накрывает
	# ближняя тень (радиус поражения 3.2 м > первого отступа).
	if track == null:
		var dir := -target.global_transform.basis.z
		var v := target.linear_velocity
		v.y = 0.0
		if v.length() > 3.0:
			dir = v.normalized()
		dir.y = 0.0
		dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector3.FORWARD
		var side := dir.cross(Vector3.UP)
		for ahead: float in [2.0, 8.0, 14.0, 20.0].slice(0, clampi(rockets, 1, 4)):
			var pos := target.global_position + dir * ahead \
					+ side * randf_range(-3.0, 3.0)
			pos.y = target.global_position.y
			_spots.append(pos)
			_shadows.append(_make_shadow(pos))
			_rockets.append(_make_rocket(pos))
		return
	var curve: Curve3D = track._curve
	var length := curve.get_baked_length()
	# Отметка ЖЕРТВЫ (ведётся по непрерывности): у лидера, сошедшего с
	# полотна, ближайшей точкой оси бывает чужой виток — бомбы легли бы
	# в другом конце трассы.
	var off: float = target.track_offset
	var want := clampi(rockets, 1, AHEAD.size())
	# II/III ступени: сначала ракеты С УПРЕЖДЕНИЕМ по соперникам (впереди
	# по гонке, а если таких нет — позади); остаток — по лидеру, как обычно.
	if lead:
		_lead_spots(curve, length, want)
	for ahead: float in AHEAD:
		if _spots.size() >= want:
			break
		var o := fposmod(off + ahead, length)
		var pos := curve.sample_baked(o)
		var next := curve.sample_baked(fposmod(o + 1.0, length))
		var dir := next - pos
		dir.y = 0.0
		if dir.length_squared() < 1e-6:
			continue
		var right := dir.normalized().cross(Vector3.UP)
		# Сдвиг вбок — по фактической ширине в этой точке (полотно
		# переменной ширины), с отступом от кромки на радиус поражения.
		var spread: float = maxf(1.0, track.half_width_at_offset(o) - 3.0)
		pos += right * randf_range(-spread, spread)
		_spots.append(pos)
		_shadows.append(_make_shadow(pos))
		_rockets.append(_make_rocket(pos))


## Тени С УПРЕЖДЕНИЕМ (авиаудар II/III, спецификация игрока 04.09): по
## одной ракете на соперника, ВПЕРЕДИ атакующего по гонке (ближайшие
## первыми), а если впереди никого — по едущим сзади. Точка — на оси
## трассы там, где жертва окажется через SHADOW_DELAY при своей скорости,
## со сдвигом вбок на её нынешнее смещение от оси (ракета ложится на её
## колею, а не на середину дороги). Порядок «впереди/сзади» — по
## накопленному пути гонки (Main.progress_of), без менеджера — по отметке
## на оси.
func _lead_spots(curve: Curve3D, length: float, want: int) -> void:
	var ahead_cars: Array = []
	var behind_cars: Array = []
	var my_prog := _progress_of(attacker)
	for node in get_tree().get_nodes_in_group("cars"):
		var car := node as Car
		if car == null or car == attacker or not car.alive or car.is_ghost():
			continue
		var gap := _progress_of(car) - my_prog
		if gap > 0.0:
			ahead_cars.append([gap, car])
		else:
			behind_cars.append([-gap, car])
	var pool := ahead_cars if not ahead_cars.is_empty() else behind_cars
	pool.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry: Array in pool:
		if _spots.size() >= want:
			break
		var car: Car = entry[1]
		var here := curve.sample_baked(fposmod(car.track_offset, length))
		var tangent := curve.sample_baked(
				fposmod(car.track_offset + 1.0, length)) - here
		tangent.y = 0.0
		if tangent.length_squared() < 1e-6:
			continue
		tangent = tangent.normalized()
		var v := car.linear_velocity
		v.y = 0.0
		# Упреждение — по составляющей скорости вдоль трассы (задом или
		# поперёк едущего не «упреждаем» в никуда) плюс полкорпуса.
		var along: float = maxf(0.0, v.dot(tangent)) * SHADOW_DELAY + 1.5
		var o := fposmod(car.track_offset + along, length)
		var pos := curve.sample_baked(o)
		var next := curve.sample_baked(fposmod(o + 1.0, length))
		var dir := next - pos
		dir.y = 0.0
		if dir.length_squared() < 1e-6:
			continue
		var right := dir.normalized().cross(Vector3.UP)
		# Боковое смещение жертвы от оси — в ЕЁ точке, в осях её касательной.
		var side_now := (car.global_position - here).dot(
				tangent.cross(Vector3.UP))
		var limit: float = maxf(0.5, track.half_width_at_offset(o) - 1.0)
		pos += right * clampf(side_now, -limit, limit)
		_spots.append(pos)
		_shadows.append(_make_shadow(pos))
		_rockets.append(_make_rocket(pos))


func _progress_of(car: Car) -> float:
	if car == null:
		return 0.0
	if car.race != null and car.race.has_method("progress_of"):
		return car.race.progress_of(car)
	return car.track_offset


## Метка падения: плотная тёмная тень + яркое красное кольцо-прицел
## (пульсирует вместе с тенью — хорошо видно на асфальте издалека).
func _make_shadow(pos: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = SHADOW_RADIUS * hit_mult
	disc.bottom_radius = SHADOW_RADIUS * hit_mult
	disc.height = 0.05
	mesh.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.01, 0.01, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = SHADOW_RADIUS * hit_mult
	torus.outer_radius = SHADOW_RADIUS * hit_mult * 1.3
	ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.15, 0.1, 0.9)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.2, 0.1)
	ring_mat.emission_energy_multiplier = 2.0
	ring.material_override = ring_mat
	ring.position.y = 0.04
	mesh.add_child(ring)
	add_child(mesh)
	mesh.global_position = pos + Vector3.UP * 0.1
	return mesh


## Видимая ракета: серый корпус, красный нос-конус, стабилизаторы и
## оранжевое «пламя» в хвосте. Начало координат — остриё: при нулевом
## смещении нос касается точки падения. Корпус наклонён вдоль траектории
## (летит носом вперёд по вектору падения).
func _make_rocket(pos: Vector3) -> Node3D:
	var rocket := Node3D.new()
	add_child(rocket)
	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = Color(0.8, 0.15, 0.1)
	var nose := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.16
	cone.bottom_radius = 0.0
	cone.height = 0.4
	nose.mesh = cone
	nose.position.y = 0.2
	nose.material_override = nose_mat
	rocket.add_child(nose)
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.16
	cyl.height = 1.1
	body.mesh = cyl
	body.position.y = 0.95
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.42, 0.44, 0.47)
	body.material_override = body_mat
	rocket.add_child(body)
	for i in 4:
		var a := i * PI / 2.0
		var fin := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.04, 0.35, 0.28)
		fin.mesh = box
		fin.material_override = nose_mat
		fin.position = Vector3(cos(a) * 0.2, 1.35, sin(a) * 0.2)
		fin.rotation.y = -a
		rocket.add_child(fin)
	var flame := MeshInstance3D.new()
	var fs := SphereMesh.new()
	fs.radius = 0.14
	fs.height = 0.28
	flame.mesh = fs
	flame.position.y = 1.55
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.6, 0.15)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.55, 0.1)
	fmat.emission_energy_multiplier = 3.0
	flame.material_override = fmat
	rocket.add_child(flame)
	# Нос (локальный -Y) — вдоль вектора падения, старт — в точке отлёта.
	rocket.quaternion = Quaternion(Vector3.DOWN, -_fall_offset.normalized())
	rocket.global_position = pos + _fall_offset
	return rocket


func _physics_process(delta: float) -> void:
	_timer -= delta
	# Тень «пульсирует», пока ракета летит.
	var pulse := 0.8 + 0.2 * sin(_timer * 25.0)
	for s in _shadows:
		s.scale = Vector3(pulse, 1.0, pulse)
	# Ракеты летят с ускорением по наклонной (квадратично по остатку
	# таймера): в момент таймера 0 нос — в точке удара.
	var t: float = clampf(_timer / SHADOW_DELAY, 0.0, 1.0)
	for i in _rockets.size():
		_rockets[i].global_position = _spots[i] + _fall_offset * t * t
	if _timer > 0.0:
		return
	# Падение: взрыв в каждой точке, все машины в радиусе уничтожаются.
	for pos in _spots:
		FlashFx.spawn(get_parent(), pos + Vector3.UP * 0.6, 2.6,
				Color(1.0, 0.45, 0.1))
		FxKit.ring(get_parent(), pos, 3.0, Color(1.0, 0.55, 0.15))
		FxKit.smoke_burst(get_parent(), pos + Vector3.UP * 0.5, 10, 1.1)
		FxKit.fire_burst(get_parent(), pos + Vector3.UP * 0.2, 10)
		FxKit.scorch(get_parent(), pos, 2.2)
		for node in get_tree().get_nodes_in_group("cars"):
			var car := node as Car
			if car == null or not car.alive or car.is_ghost():
				continue
			var d := car.global_position - pos
			d.y = 0.0
			if d.length() <= HIT_RADIUS * hit_mult:
				if inert:
					continue
				# Щит (08.09): ракета сверху разбивается о сферу.
				if car.is_shielded():
					car.shield_block_fx()
					continue
				car.notify_hit_by(attacker, Weapons.AIRSTRIKE)
				car.destroy()
	queue_free()
