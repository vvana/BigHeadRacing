class_name ScrambleWave
extends Area3D
## Глушилка: звуковая волна вперёд. Попавшей машине на SCRAMBLE_TIME секунд
## МЕНЯЮТСЯ МЕСТАМИ лево и право (Car.apply_scramble) — уничтожения нет,
## есть пять секунд паники за рулём. Создаётся кодом из Car.use_weapon().
##
## Летит медленнее ракеты и живёт дольше: волну должно быть видно, а
## уклониться от неё — реально.

const SCRAMBLE_TIME := 5.0

## inert — «только картинка»: такую копию порождает КЛИЕНТ по событию с
## сервера (Main._spawn_weapon_visual). Попадания считает сервер — как у
## Projectile, иначе эффект вешался бы дважды.
var inert := false
var shooter: Car = null
var direction := Vector3.FORWARD
## На сколько отматывать цели при проверке попадания — ровно как у снаряда
## (Projectile.lag): стрелявший целился по своему экрану.
var lag := 0.0

## Волна ШИРЕ снаряда: это конус звука, а не пуля.
const HIT_R := 2.6

var _speed := 38.0
var _life := 1.8
var _age := 0.0
var _rings: Array[MeshInstance3D] = []
var _ring_mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	# Ловит машины (слой 4), гаснет о мир и стены (1|2).
	collision_layer = 0
	collision_mask = 0b111
	monitorable = false

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.9
	col.shape = sphere
	add_child(col)

	_build_rings()

	if inert:
		set_deferred("monitoring", false)
	else:
		body_entered.connect(_on_body_entered)


## Три бирюзовых кольца поперёк полёта, расходящиеся одно за другим —
## «звук». Кольцо перпендикулярно движению: TorusMesh лежит в плоскости XZ,
## поворот на 90° вокруг X ставит его «лицом вперёд».
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
		ring.rotation.x = PI * 0.5
		add_child(ring)
		_rings.append(ring)
		_ring_mats.append(mat)
	_tick_rings(0.0)


## Кольца расходятся по кругу: каждое растёт от 0.4 до RING_MAX и тает,
## фазы сдвинуты на треть — волна «пульсирует», а не мигает целиком.
func _tick_rings(age: float) -> void:
	const RING_PERIOD := 0.42
	const RING_MAX := 3.4
	for i in _rings.size():
		var phase: float = fposmod(age / RING_PERIOD + float(i) / 3.0, 1.0)
		var s: float = lerpf(0.4, RING_MAX, phase)
		_rings[i].scale = Vector3(s, 1.0, s)
		_ring_mats[i].albedo_color.a = (1.0 - phase) * 0.85


func _physics_process(delta: float) -> void:
	_age += delta
	_tick_rings(_age)
	var prev := global_position
	global_position += direction * _speed * delta
	# Попадание по ОТМОТАННЫМ положениям — как у Projectile: проверяем не
	# точку, а отрезок за кадр, иначе задетых вскользь волна пропускает.
	if lag > 0.0 and not inert:
		for node in get_tree().get_nodes_in_group("cars"):
			var car := node as Car
			if car == null or car == shooter \
					or not car.alive or car.is_ghost():
				continue
			if _segment_gap(prev, global_position,
					car.past_position(lag)) < HIT_R:
				_hit_car(car)
				_boom()
				return
	_life -= delta
	if _life <= 0.0:
		queue_free()


## Расстояние от точки p до отрезка a-b.
func _segment_gap(a: Vector3, b: Vector3, p: Vector3) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 1e-6:
		return a.distance_to(p)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return (a + ab * t).distance_to(p)


func _on_body_entered(body: Node3D) -> void:
	if body == shooter:
		return
	var car := body as Car
	# Машины с отмоткой считаются вручную выше — иначе волна живого игрока
	# сработала бы ДВАЖДЫ. О мир и ограждения гаснет как прежде.
	if car != null:
		if lag > 0.0:
			return
		if car.alive and not car.is_ghost():
			_hit_car(car)
	_boom()


func _hit_car(car: Car) -> void:
	car.notify_hit_by(shooter, Weapons.SCRAMBLE)
	car.apply_scramble(SCRAMBLE_TIME)


func _boom() -> void:
	FlashFx.spawn(get_parent(), global_position, 1.4, Color(0.4, 0.95, 1.0))
	FxKit.ring(get_parent(), global_position, 3.0, Color(0.4, 0.95, 1.0))
	queue_free()
