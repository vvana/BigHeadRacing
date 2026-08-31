class_name Projectile
extends Area3D
## Летящий вперёд снаряд, два вида:
## - ракета (freeze=false): УНИЧТОЖАЕТ машину, в которую врезалась;
## - ледышка (freeze=true): попавшая машина синеет и едет медленнее
##   (дебаф заразен при контактах — см. Car.apply_freeze).
## Создаётся кодом из Car.use_weapon().

## inert — «только картинка»: такую копию порождает КЛИЕНТ по событию с
## сервера. Считает попадания и толчки сервер, его результат приезжает
## в снимках; работай копия по-настоящему, машину било бы дважды.
var inert := false
var shooter: Car = null
var direction := Vector3.FORWARD
var freeze := false
## На сколько секунд ОТМАТЫВАТЬ цели при проверке попадания. Ставится
## сервером для снаряда ЖИВОГО ИГРОКА: тот целился по своему экрану, где
## соперники нарисованы с отставанием буфера (Car.net_buf_delay) плюс
## полёт пакета. Сервер же видит их «сейчас», и на скорости 30 м/с
## расхождение — метры: игрок вёл ракету точно в машину, а она пролетала
## насквозь (жалоба 28.08 «оружие пролетает сквозь даже ботов»). Лазер
## получил такую отмотку раньше (Car._use_laser), снаряды — нет.
## 0 — цели берутся «как есть» (боты, оффлайн, инертные копии).
var lag := 0.0

## Полукорпус для проверки по отмотанным положениям: машина ~3.2 x 1.7 м,
## снаряд радиусом 0.5. Та же величина, что у коридора лазера.
const HIT_R := 1.6

var _speed := 55.0
var _life := 2.2


func _ready() -> void:
	# Ловит машины (слой 4), гаснет о мир и стены (1|2).
	collision_layer = 0
	collision_mask = 0b111
	monitorable = false

	if freeze:
		_speed = 42.0
		_life = 2.0

	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	col.shape = sphere
	add_child(col)

	# Снаряд заметно крупнее прежнего (0.26): мелкую «пульку» на скорости
	# 55 м/с было плохо видно, просьба игрока — «пульки побольше».
	var mesh := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.42
	ball.height = 0.84
	mesh.mesh = ball
	var mat := StandardMaterial3D.new()
	if freeze:
		mat.albedo_color = Color(0.55, 0.8, 1.0)
		mat.emission = Color(0.35, 0.65, 1.0)
	else:
		mat.albedo_color = Color(1.0, 0.45, 0.1)
		mat.emission = Color(1.0, 0.35, 0.05)
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 2.5
	mesh.material_override = mat
	add_child(mesh)
	_build_trail()

	if inert:
		set_deferred("monitoring", false)
	else:
		body_entered.connect(_on_body_entered)


## Шлейф за снарядом: у ракеты — огненное свечение (glow из Epic Toon FX,
## аддитивно), у ледышки — россыпь снежинок. Клубы остаются позади
## (local_coords = false) и быстро тают.
func _build_trail() -> void:
	var p := CPUParticles3D.new()
	p.amount = 20
	p.lifetime = 0.18  # короче: при 0.3 огненный след тянулся на ~13 м
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.0
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 1.0))
	fade.add_point(Vector2(1.0, 0.15))
	p.scale_amount_curve = fade
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var grad := Gradient.new()
	if freeze:
		quad.size = Vector2(0.3, 0.3)
		mat.albedo_texture = load("res://assets/fx/snowflake.png")
		grad.set_color(0, Color(0.85, 0.95, 1.0, 1.0))
		grad.set_color(1, Color(0.55, 0.8, 1.0, 0.0))
	else:
		quad.size = Vector2(0.6, 0.6)
		mat.albedo_texture = load("res://assets/fx/glow1.png")
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		grad.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
		grad.set_color(1, Color(0.9, 0.25, 0.03, 0.0))
	quad.material = mat
	p.mesh = quad
	p.color_ramp = grad
	add_child(p)
	p.emitting = true


func _physics_process(delta: float) -> void:
	var prev := global_position
	global_position += direction * _speed * delta
	# Попадание по ОТМОТАННЫМ положениям — для снаряда живого игрока.
	# Проверяем не точку, а отрезок за кадр: на 55 м/с снаряд проходит
	# 0.92 м, и проверка «где он сейчас» пропускала бы задетые вскользь.
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
	# Машины с отмоткой считаются вручную выше — иначе снаряд живого игрока
	# сработал бы ДВАЖДЫ: по отмотанному положению и по нынешнему.
	# О мир и ограждения (они не Car) снаряд гаснет как прежде.
	if car != null:
		if lag > 0.0:
			return
		if car.alive and not car.is_ghost():
			_hit_car(car)
	_boom()


func _hit_car(car: Car) -> void:
	car.notify_hit_by(shooter, Weapons.FREEZE if freeze else Weapons.ROCKET)
	if freeze:
		car.apply_freeze(3.0)
	else:
		car.destroy()


func _boom() -> void:
	var color := Color(0.5, 0.8, 1.0) if freeze else Color(1.0, 0.7, 0.2)
	FlashFx.spawn(get_parent(), global_position, 0.9, color)
	if freeze:
		FxKit.snow_burst(get_parent(), global_position)
	else:
		SparksFx.spawn(get_parent(), global_position, 6.0)
	queue_free()
