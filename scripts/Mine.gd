class_name Mine
extends Area3D
## Мина (сбрасывается за корму, как slime/мины в RnRR). Взводится с задержкой,
## чтобы не подорвать хозяина, живёт ограниченное время.

var dropper: Car = null
var damage := 35.0

var _arm := 0.7
var _armed := false
var _life := 25.0
# Мина не парит: сброшенная в полёте (с трамплина, в прыжке) падает
# с ускорением свободного падения, пока не встанет на дорогу/землю.
var _grounded := false
var _fall_speed := 0.0


func _ready() -> void:
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.7
	col.shape = sphere
	add_child(col)

	var body_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.32
	cyl.bottom_radius = 0.38
	cyl.height = 0.16
	body_mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.17)
	body_mesh.material_override = mat
	add_child(body_mesh)

	var dot := MeshInstance3D.new()
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.07
	dot_mesh.height = 0.14
	dot.mesh = dot_mesh
	dot.position.y = 0.1
	var dot_mat := StandardMaterial3D.new()
	dot_mat.albedo_color = Color(1, 0.1, 0.1)
	dot_mat.emission_enabled = true
	dot_mat.emission = Color(1, 0.05, 0.05)
	dot_mat.emission_energy_multiplier = 2.0
	dot.material_override = dot_mat
	add_child(dot)

	body_entered.connect(_try_trigger)


func _physics_process(delta: float) -> void:
	if not _grounded:
		_fall(delta)
	if not _armed:
		_arm -= delta
		if _arm <= 0.0:
			_armed = true
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
		global_position.y = (hit.position as Vector3).y + 0.08
		_grounded = true


func _try_trigger(body: Node3D) -> void:
	if not _armed:
		return
	if body is Car and (body as Car).alive:
		(body as Car).take_damage(damage, Vector3.UP)
		FlashFx.spawn(get_parent(), global_position, 1.4, Color(1.0, 0.4, 0.1))
		queue_free()
