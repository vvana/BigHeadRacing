class_name Projectile
extends Area3D
## Снаряд (плазма вперёд, как в RnRR): летит по прямой, бьёт первую
## машину или стену. Создаётся кодом из Car.shoot().

var shooter: Car = null
var direction := Vector3.FORWARD
var speed := 45.0
var damage := 30.0

var _life := 1.4


func _ready() -> void:
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.35
	col.shape = sphere
	add_child(col)

	var mesh := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.22
	ball.height = 0.44
	mesh.mesh = ball
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.05)
	mat.emission_energy_multiplier = 2.5
	mesh.material_override = mat
	add_child(mesh)

	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body == shooter:
		return
	if body is Car:
		(body as Car).take_damage(damage, direction)
	FlashFx.spawn(get_parent(), global_position, 0.9, Color(1.0, 0.7, 0.2))
	queue_free()
