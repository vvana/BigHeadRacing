class_name ScrambleWave
extends Area3D
## Глушилка: звуковая волна вперёд. Попавшей машине на SCRAMBLE_TIME секунд
## МЕНЯЮТСЯ МЕСТАМИ лево и право (Car.apply_scramble) — уничтожения нет,
## есть пять секунд паники за рулём. Создаётся кодом из Car.use_weapon().
##
## Кольца волны ГОРИЗОНТАЛЬНЫ и расходятся ровно до радиуса поражения
## (жалоба 31.08: «должна пускать волны по горизонтали, чтобы было видно
## её радиус действия»). Волна ПРИЖИМАЕТСЯ К ПОЛОТНУ (луч вниз каждый
## кадр): раньше летела по прямой от точки выстрела, на перепаде высот
## уходила от дороги и проходила НАД машинами — «выстрелил в бота прямо
## передо мной, оружие пролетело сквозь него».

const SCRAMBLE_TIME := 5.0

## inert — «только картинка»: такую копию порождает КЛИЕНТ по событию с
## сервера (Main._spawn_weapon_visual). Попадания считает сервер — как у
## Projectile, иначе эффект вешался бы дважды.
var inert := false
var shooter: Car = null
## Трасса — для доворота вдоль полотна (_steer_along_track). Ставит
## создатель; не поставил — берётся у стрелявшего, без обоих волна летит
## по прямой (стенды в пустом мире).
var track: TrackBuilder = null
var direction := Vector3.FORWARD
## На сколько отматывать цели при проверке попадания — ровно как у снаряда
## (Projectile.lag): стрелявший целился по своему экрану.
var lag := 0.0
## Ступени глушилки (магазин, 08.09): stun_time — сколько держится сбитое
## управление (I: ×1.15), speed_mult — скорость волны (II: ×1.3).
var stun_time := SCRAMBLE_TIME
var speed_mult := 1.0

## Радиус поражения — он же радиус, до которого расходятся кольца: игрок
## видит ровно ту зону, в которой волна снимает управление. Той же
## причины (31.08) машины ловятся НЕ Area3D, а ручной проверкой по отрезку
## за кадр: сферу такого радиуса Area3D тёрла бы о полотно, а крохотная
## прежняя (0.9) промахивалась там, где кольца «прошли сквозь» машину.
const HIT_R := 2.6
## Полугабариты кузова для проверки попадания: кольцо, коснувшееся ЛЮБОЙ
## точки корпуса, должно оглушать. Прежние три пробы вдоль оси (±1.1 м,
## радиус 0.9) оставляли борт между пробами и углы бампера непокрытыми
## на 0.05-0.3 м — «круги коснулись моей машины, но не оглушили»
## (жалоба 01.09). Теперь меряется расстояние до прямоугольника кузова.
const BODY_HALF_L := 1.7
const BODY_HALF_W := 1.0
## Запас к HIT_R: шаг проб вдоль пути волны (0.25 м) плюс сглаживание
## визуального кузова — «коснулось на экране» обязано означать попадание.
const HIT_GRACE := 0.35

## Быстрее прежних 38: волна должна ДОГОНЯТЬ едущих. Машина на бусте идёт
## под 48 м/с — от неё волна отстанет (и пусть), но обычную (до ~34)
## достаёт уверенно.
const SPEED := 50.0
## Насколько волна висит над полотном (и над точкой спавна).
const HOVER := 0.55

var _life := 1.8
var _age := 0.0
var _first_check := true   # первый кадр: отрезок тянется от носа стрелявшего
var _rings: Array[MeshInstance3D] = []
var _ring_mats: Array[StandardMaterial3D] = []
var _track_off := -1.0   # своя отметка на оси трассы (непрерывность)
var _stunned := {}       # id уже оглушённых машин: каждую волна берёт раз


func _ready() -> void:
	# Area3D нужна только чтобы гаснуть об ограждения (слой 2): полотно
	# волна обходит прижимом, машины считает вручную (см. HIT_R).
	collision_layer = 0
	collision_mask = 0b010
	monitorable = false

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	col.shape = sphere
	add_child(col)

	_build_rings()

	# О борта волна НЕ гаснет (09.09, «круги, касаясь машины, не всегда
	# глушат»): на сервере она умирала о рельс, а копия у клиента (без
	# слежения) летела дальше, и её кольца «касались» машин, которых
	# сервер уже не проверял. Теперь обе одинаково ЗАЖИМАЮТСЯ в полотне
	# (_clamp_inside_walls) — как картинка марионетки у стены. С 11.09
	# волна не гаснет и о машины: только срок жизни (см. _physics_process).
	set_deferred("monitoring", false)


## Три бирюзовых кольца, ЛЕЖАЩИХ ГОРИЗОНТАЛЬНО (TorusMesh и так лежит в
## плоскости XZ) и расходящихся одно за другим до радиуса поражения —
## видно и «звук», и зону действия.
func _build_rings() -> void:
	for i in 3:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.55
		torus.outer_radius = 0.75
		ring.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.95, 1.0, 0.9)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.9, 1.0)
		mat.emission_energy_multiplier = 5.0
		ring.material_override = mat
		add_child(ring)
		_rings.append(ring)
		_ring_mats.append(mat)
	_tick_rings(0.0)


## Кольца расходятся по кругу: каждое растёт от 0.4 до радиуса поражения
## и тает, фазы сдвинуты на треть — волна «пульсирует», а не мигает целиком.
func _tick_rings(age: float) -> void:
	const RING_PERIOD := 0.42
	var ring_max := HIT_R / 0.75  # внешний радиус тора 0.75 -> ровно HIT_R
	for i in _rings.size():
		var phase: float = fposmod(age / RING_PERIOD + float(i) / 3.0, 1.0)
		var s: float = lerpf(0.4, ring_max, phase)
		_rings[i].scale = Vector3(s, 1.0, s)
		_ring_mats[i].albedo_color.a = (1.0 - phase) * 0.85


func _physics_process(delta: float) -> void:
	_age += delta
	_tick_rings(_age)
	_steer_along_track(delta)
	var prev := global_position
	# Первый кадр: отрезок дотягивается до носа стрелявшего (волна рождается
	# в 2.3 м перед машиной) — цель вплотную к бамперу иначе не проверялась.
	if _first_check:
		_first_check = false
		prev -= direction * 2.3
	global_position += direction * SPEED * speed_mult * delta
	_clamp_inside_walls()
	_hug_ground()
	# Машины считаем ВРУЧНУЮ отрезком за кадр и радиусом колец HIT_R —
	# и с отмоткой (живой игрок, протокол 13), и без (боты, оффлайн).
	# Кузов — ПРЯМОУГОЛЬНИК (BODY_HALF_L × BODY_HALF_W в осях машины):
	# прежние три пробы вдоль оси не покрывали борт между пробами и углы —
	# кольцо, коснувшееся их, «проходило сквозь» (жалоба 01.09). И глушатся
	# ВСЕ машины, задетые кольцами в этот кадр, а не первая по списку:
	# раньше волна в куче машин гасла об соседа, а второго — визуально
	# накрытого теми же кольцами — не трогала.
	# ВОЛНА ГАСНЕТ ТОЛЬКО ОТ ВРЕМЕНИ (просьба игрока 11.09). Раньше она
	# умирала об первую же задетую машину, а её КОПИЯ на экранах летела
	# дальше и «касалась» тех, кого сервер уже не проверял, — это и видно
	# было как «круги коснулись, а не оглушило». Теперь и настоящая волна,
	# и копия живут свой срок (_life), а кольца глушат ВСЕХ, кого накрыли
	# по дороге. Каждую машину — ОДИН РАЗ (_stunned): волна быстрее машин,
	# но цель на бусте остаётся в кольцах несколько кадров, и без памяти
	# эффект продлевался бы, пока волна рядом.
	# Копия у клиента (inert) попаданий не считает вовсе: оглушение вешает
	# сервер, а вспышку на жертве он присылает отдельно (Main._rx_wave_fx).
	if not inert:
		for node in get_tree().get_nodes_in_group("cars"):
			var car := node as Car
			if car == null or car == shooter \
					or not car.alive or car.is_ghost() \
					or _stunned.has(car.get_instance_id()):
				continue
			# Цель — и ТЕКУЩАЯ (что жертва видит у себя), и ОТМОТАННАЯ (что
			# видел стрелявший): коснулось на любом из экранов — оглушает (09.09).
			var fwd := car.true_forward()
			var hit := _touches_body(prev, global_position, car.global_position, fwd)
			if not hit and lag > 0.0:
				hit = _touches_body(prev, global_position,
						car.past_position(Car.aim_lag(lag, car)), fwd)
			if hit:
				_stunned[car.get_instance_id()] = true
				_hit_car(car)
	_life -= delta
	if _life <= 0.0:
		# Срок вышел — волна тает там, где её застало время.
		_fade()
		queue_free()


## Волна КАТИТСЯ ПО ТРАССЕ, а не летит по прямой: курс плавно доворачивает
## к касательной трассы (в ту сторону, куда стреляли). Дорога изгибается —
## прямая волна на дуге уходила с полотна вбок и мазала по боту, который
## «прямо передо мной» просто потому, что он ехал по дуге (стенд, фаза
## «едущий бот»: промах 3.1 м на 20 метрах дистанции). Начальный прицел
## уважается: первые метры доворот почти не успевает вмешаться.
func _steer_along_track(delta: float) -> void:
	if track == null and shooter != null and is_instance_valid(shooter):
		track = shooter.track
	if track == null:
		return
	var curve: Curve3D = track._curve
	var length := curve.get_baked_length()
	if length <= 0.0:
		return
	# Отметка на оси — с непрерывностью, как у машин (см. TrackBuilder);
	# первая — глобальным поиском: волна рождается на полотне, он не соврёт.
	if _track_off < 0.0:
		_track_off = curve.get_closest_offset(global_position)
	_track_off = track.closest_offset_near(global_position, _track_off)
	var here := curve.sample_baked(fposmod(_track_off, length))
	var tangent := curve.sample_baked(fposmod(_track_off + 1.5, length)) - here
	tangent.y = 0.0
	if tangent.length_squared() < 1e-6:
		return
	tangent = tangent.normalized()
	if direction.dot(tangent) < 0.0:
		tangent = -tangent   # стреляли против хода разметки — волне туда же
	direction = direction.lerp(tangent, minf(4.0 * delta, 1.0)).normalized()


## Не выпускать волну за ограждение: боковое смещение от оси не больше
## полуширины минус стенка и запас (как Car._clamp_view_inside_walls).
func _clamp_inside_walls() -> void:
	if track == null or not track.has_walls or track._curve == null or _track_off < 0.0:
		return
	var length: float = track._curve.get_baked_length()
	if length <= 0.0:
		return
	var off := fposmod(_track_off, length)
	var axis: Vector3 = track._curve.sample_baked(off)
	var right: Vector3 = track.right_at_offset(off)
	right.y = 0.0
	if right.length_squared() < 1e-6:
		return
	right = right.normalized()
	var rel := global_position - axis
	rel.y = 0.0
	var side := rel.dot(right)
	var limit: float = track.half_width_at_offset(off) - TrackBuilder.WALL_THICKNESS * 0.5 - 0.6
	if limit > 0.0 and absf(side) > limit:
		global_position -= right * (side - signf(side) * limit)


## Прижим к полотну: луч вниз, высота = земля + HOVER. Волна взбирается на
## горки и спускается с них вместе с дорогой — там же, где машины. Земли
## под волной нет (улетела за кромку песчаной трассы, в пропасть) — летит
## как летела и умрёт по таймеру жизни.
func _hug_ground() -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
			global_position + Vector3.UP * 2.0,
			global_position + Vector3.DOWN * 4.0, 0b001)
	var hit := space.intersect_ray(q)
	if hit:
		global_position.y = hit.position.y + HOVER


## Коснулись ли кольца кузова за этот кадр: путь волны (отрезок a-b)
## пробуется с шагом 0.25 м, каждая проба переводится в оси кузова и
## меряется до ближайшей точки прямоугольника BODY_HALF_L × BODY_HALF_W.
## Попадание — дистанция меньше радиуса колец (с запасом HIT_GRACE).
func _touches_body(a: Vector3, b: Vector3, center: Vector3,
		fwd: Vector3) -> bool:
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var steps := maxi(1, int(ceilf(a.distance_to(b) / 0.25)))
	for s in steps + 1:
		var p := a.lerp(b, float(s) / float(steps))
		var rel := p - center
		# По высоте — отдельный допуск (подскок, уклон), дистанция — в плане.
		if absf(rel.y) > 2.0:
			continue
		rel.y = 0.0
		var w := clampf(rel.dot(right), -BODY_HALF_W, BODY_HALF_W)
		var l := clampf(rel.dot(fwd), -BODY_HALF_L, BODY_HALF_L)
		if (rel - (right * w + fwd * l)).length() < HIT_R + HIT_GRACE:
			return true
	return false


func _hit_car(car: Car) -> void:
	# Щит (08.09): о сферу волна больше не гаснет — она вообще ни обо что
	# не гаснет, кроме своего срока, — но управление под щитом цело.
	if car.is_shielded():
		car.shield_block_fx()
		return
	car.notify_hit_by(shooter, Weapons.SCRAMBLE)
	car.apply_scramble(stun_time)
	_hit_fx(car.global_position)


## Волна прошла свой путь и растаяла — мягкая вспышка на месте.
func _fade() -> void:
	FlashFx.spawn(get_parent(), global_position, 0.9, Color(0.4, 0.95, 1.0))


## Вспышка НА ЖЕРТВЕ: волна летит дальше, и без этой отметки попадание
## было бы незаметно — раньше его показывал взрыв самой волны. Сервер
## повторяет ту же вспышку на экранах клиентов (Main._rx_wave_fx).
func _hit_fx(at: Vector3) -> void:
	FlashFx.spawn(get_parent(), at, 1.2, Color(0.4, 0.95, 1.0))
	FxKit.ring(get_parent(), at, HIT_R * 0.6, Color(0.4, 0.95, 1.0))
	if not inert and shooter != null and is_instance_valid(shooter) \
			and shooter.race != null \
			and shooter.race.has_method("net_broadcast_wave_hit"):
		shooter.race.net_broadcast_wave_hit(at)
