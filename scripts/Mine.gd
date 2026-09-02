class_name Mine
extends Area3D
## Мина (сбрасывается за корму). При наезде ВЗРЫВАЕТСЯ: наехавшего и всех,
## кто оказался в эпицентре, УНИЧТОЖАЕТ (взрыв, появление на трассе и
## мигание неуязвимости — как от ракеты), а тех, кто подальше, только
## расталкивает: подбрасывает, закручивает и отшвыривает.
## Задержка взведения защищает ТОЛЬКО хозяина: для остальных мина
## боевая с первого кадра (жалоба 31.08: «машины проезжают сквозь мины
## не уничтожаясь» — соперник, ехавший вплотную за сбросившим, успевал
## проскочить за 0.7 c взведения). Живёт ограниченное время.

const BLAST_RADIUS := 10.0
# Ближе этого мина не толкает, а УНИЧТОЖАЕТ (31.08: «пусть мина взрывает
# авто»). 4 м — чуть больше корпуса (3.2 м): наехавший гибнет всегда,
# сосед по пятну — если стоял вплотную.
const LETHAL_RADIUS := 4.0
const BLAST_SPEED := 18.0   # горизонтальный импульс в эпицентре, м/с
const BLAST_SPIN := 3.2     # закрутка в эпицентре, рад/с
const BLAST_LIFT := 0.45    # доля подброса вверх от импульса

## inert — «только картинка»: такую копию порождает КЛИЕНТ по событию с
## сервера. Считает попадания и толчки сервер, его результат приезжает
## в снимках; работай копия по-настоящему, машину било бы дважды.
var inert := false
var dropper: Car = null

var _arm := 0.7   # окно неуязвимости ХОЗЯИНА (сброс за корму — не подрыв)
# Мина рвётся РОВНО ОДИН РАЗ. queue_free() отложен до конца кадра, а за
# этот кадр body_entered может прийти ещё от одной машины (и цикл
# взведения перебирает все тела разом) — без флага одна мина отрабатывала
# взрыв по нескольку раз: двойные записи в ленте, двойной счёт убийств и
# лишние узлы эффектов. С уничтожением в эпицентре это стало заметно.
var _blown := false
var _life := 25.0
# Мина не парит: сброшенная в полёте (с трамплина, в прыжке) падает
# с ускорением свободного падения, пока не встанет на дорогу/землю.
var _grounded := false
var _fall_speed := 0.0
# Мигание маячка: материал и накопленное время (детерминированно, без randf).
var _beacon_mat: StandardMaterial3D
var _blink_t := 0.0


func _ready() -> void:
	# Ловит только машины (слой 4).
	collision_layer = 0
	collision_mask = 0b100
	monitorable = false

	# Радиус срабатывания НЕ растёт вместе с корпусом: 0.9 доставал до
	# кормы сбросившей машины (2.4 м до центра, край «санок» ~1.5) — мина
	# рвалась под хозяином. Побольше — только видимый корпус.
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.7
	col.shape = sphere
	add_child(col)

	# Визуал (2026-09-02, «сделай мину более визуально заметной»): корпус
	# крупнее прежнего, вокруг — светящаяся жёлтая сигнальная полоса, по
	# кругу шипы (силуэт морской мины читается издалека), сверху — красный
	# маячок, МИГАЮЩИЙ в _physics_process. Всё детерминированное, без randf.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.13, 0.16)
	mat.metallic = 0.4
	mat.roughness = 0.45

	var body_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.72
	cyl.height = 0.3
	body_mesh.mesh = cyl
	body_mesh.position.y = 0.02
	body_mesh.material_override = mat
	add_child(body_mesh)

	# Сигнальная полоса — усечённый конус чуть шире корпуса, жёлтая эмиссия.
	var band := MeshInstance3D.new()
	var band_cyl := CylinderMesh.new()
	band_cyl.top_radius = 0.64
	band_cyl.bottom_radius = 0.74
	band_cyl.height = 0.12
	band.mesh = band_cyl
	band.position.y = 0.05
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = Color(1.0, 0.78, 0.08)
	band_mat.emission_enabled = true
	band_mat.emission = Color(1.0, 0.7, 0.05)
	band_mat.emission_energy_multiplier = 1.4
	band.material_override = band_mat
	add_child(band)

	# Шипы по кругу (6 шт., наклонены наружу).
	var spike_mesh := CylinderMesh.new()
	spike_mesh.top_radius = 0.0
	spike_mesh.bottom_radius = 0.07
	spike_mesh.height = 0.26
	for i in 6:
		var spike := MeshInstance3D.new()
		spike.mesh = spike_mesh
		var a := TAU * i / 6.0
		spike.position = Vector3(cos(a) * 0.62, 0.1, sin(a) * 0.62)
		# Наклон наружу: сперва крен -0.9 рад (к +X), потом рысканьем -a
		# разворачиваем этот крен в радиальное направление шипа.
		spike.rotation = Vector3(0.0, -a, -0.9)
		spike.material_override = mat
		add_child(spike)

	var dot := MeshInstance3D.new()
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.16
	dot_mesh.height = 0.32
	dot.mesh = dot_mesh
	dot.position.y = 0.26
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.albedo_color = Color(1, 0.1, 0.1)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1, 0.05, 0.05)
	_beacon_mat.emission_energy_multiplier = 2.0
	dot.material_override = _beacon_mat
	add_child(dot)

	if inert:
		set_deferred("monitoring", false)
	else:
		body_entered.connect(_try_trigger)


func _physics_process(delta: float) -> void:
	# Маячок МИГАЕТ (примерно 1.4 раза в секунду) — боевая мина должна
	# бросаться в глаза. Работает и у инертной копии на клиенте.
	_blink_t += delta
	if _beacon_mat:
		var pulse := 0.5 + 0.5 * sin(_blink_t * 9.0)
		_beacon_mat.emission_energy_multiplier = 1.2 + 6.5 * pulse
		_beacon_mat.albedo_color = Color(1.0, 0.08 + 0.5 * pulse, 0.08)
	if not _grounded:
		_fall(delta)
	# Инертная копия (клиент) не срабатывает вовсе: у неё выключен
	# monitoring, и get_overlapping_bodies() на нём ругается в лог каждый кадр.
	if not inert:
		_arm -= delta
		# Перепроверка КАЖДЫЙ тик, а не только body_entered: сигнал бьёт
		# лишь на ВХОДЕ в зону. Машина, заехавшая на мину «призраком»
		# (слой контактов выключен) или в окне взведения хозяина, после
		# снятия защиты стояла бы на мине безнаказанно — сигнал по ней
		# уже отстрелялся.
		for b in get_overlapping_bodies():
			_try_trigger(b)
	_life -= delta
	if _life <= 0.0:
		queue_free()


## Падение до опоры: луч вниз на шаг кадра ищет дорогу/землю (слой 1,
## стены — слой 2 — не опора). Нашёл — мина ложится на поверхность.
func _fall(delta: float) -> void:
	_fall_speed += 9.8 * delta
	var step := _fall_speed * delta
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.2,
		global_position + Vector3.DOWN * (step + 0.1))
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		global_position.y -= step
		if global_position.y < -60.0:  # улетела в пропасть за краем мира
			queue_free()
	else:
		global_position.y = (hit.position as Vector3).y + 0.13
		_grounded = true


func _try_trigger(body: Node3D) -> void:
	if _blown:
		return
	var trigger := body as Car
	if trigger == null or not trigger.alive or trigger.is_ghost():
		return
	# Свежесброшенная мина не трогает ТОЛЬКО хозяина; для остальных она
	# боевая сразу — раньше общая задержка 0.7 c пропускала соперника,
	# ехавшего впритык за сбросившим.
	if trigger == dropper and _arm > 0.0:
		return
	_blown = true
	# Взрыв: расталкивание всех машин в радиусе, сила тает с расстоянием.
	for node in get_tree().get_nodes_in_group("cars"):
		var car := node as Car
		if car == null or not car.alive or car.is_ghost():
			continue
		var away := car.global_position - global_position
		away.y = 0.0
		var dist := away.length()
		if dist > BLAST_RADIUS:
			continue
		var dir := away / dist if dist > 0.01 else Vector3.FORWARD
		# В эпицентре машина ГИБНЕТ (взрыв, появление на трассе, мигание) —
		# толкать её после этого нечего: destroy сам обнуляет скорость и
		# переставляет машину к месту появления. В ленту событий (и в счёт
		# убийств) идут только погибшие: раньше запись получал каждый, кого
		# просто качнуло взрывом за десять метров.
		if dist <= LETHAL_RADIUS:
			car.notify_hit_by(dropper, Weapons.MINE)
			car.destroy()
			continue
		# Дальше — прежнее расталкивание. Спад силы КВАДРАТИЧНЫЙ, а не
		# линейный: рядом с эпицентром взрыв держит почти полную мощь, и
		# только к кромке радиуса сходит на нет.
		var t := dist / BLAST_RADIUS
		var falloff := 1.0 - t * t
		var spin := BLAST_SPIN * falloff * (1.0 if randf() < 0.5 else -1.0)
		car.push_from_blast(dir, BLAST_SPEED * falloff, spin, BLAST_LIFT)
	# Клиенты о срабатывании не знают (их копия мины инертна) — шлём им
	# взрыв, иначе мина молча лежала бы на дороге, а машины разлетались
	# «сами по себе».
	var race := get_parent()
	if race != null and race.has_method("net_broadcast_mine_blast"):
		race.net_broadcast_mine_blast(global_position)
	FlashFx.spawn(get_parent(), global_position, 3.2, Color(1.0, 0.4, 0.1))
	FxKit.ring(get_parent(), global_position, 5.5, Color(1.0, 0.5, 0.12))
	FxKit.smoke_burst(get_parent(), global_position + Vector3.UP * 0.5, 14, 1.4)
	SparksFx.spawn(get_parent(), global_position + Vector3.UP * 0.3, 12.0)
	FxKit.fire_burst(get_parent(), global_position + Vector3.UP * 0.2)
	FxKit.scorch(get_parent(), global_position, 2.8)
	queue_free()
