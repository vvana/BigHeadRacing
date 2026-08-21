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
	sphere.radius = 0.4
	col.shape = sphere
	add_child(col)

	var mesh := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.26
	ball.height = 0.52
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

	if inert:
		set_deferred("monitoring", false)
	else:
		body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += direction * _speed * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body == shooter:
		return
	var car := body as Car
	if car != null and car.alive and not car.is_ghost():
		if freeze:
			car.apply_freeze(3.0)
		else:
			car.destroy()
	var color := Color(0.5, 0.8, 1.0) if freeze else Color(1.0, 0.7, 0.2)
	FlashFx.spawn(get_parent(), global_position, 0.9, color)
	queue_free()
