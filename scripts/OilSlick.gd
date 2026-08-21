class_name OilSlick
extends Area3D
## Масляное пятно: тёмный блин на дороге. Наехавшую машину ЗАНОСИТ
## всерьёз: случайная закрутка, почти нулевое сцепление и буксующие
## колёса (ни разогнаться, ни оттормозиться) на slip_duration.
## Хозяина не трогает первые 0.7 с, живёт ограниченное время.

## inert — «только картинка»: такую копию порождает КЛИЕНТ по событию с
## сервера. Считает попадания и толчки сервер, его результат приезжает
## в снимках; работай копия по-настоящему, машину било бы дважды.
var inert := false
var dropper: Car = null

var _arm := 0.7
var _life := 15.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0b100  # только машины (слой 4)
	monitorable = false

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 2.4
	shape.height = 0.6
	col.shape = shape
	add_child(col)

	var mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 2.4
	disc.bottom_radius = 2.4
	disc.height = 0.04
	mesh.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.04, 0.08, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	mat.metallic = 0.6
	mesh.material_override = mat
	add_child(mesh)

	if inert:
		set_deferred("monitoring", false)
	else:
		body_entered.connect(_on_body)


func _physics_process(delta: float) -> void:
	_arm = maxf(0.0, _arm - delta)
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_body(body: Node3D) -> void:
	var car := body as Car
	if car == null or not car.alive:
		return
	if car == dropper and _arm > 0.0:
		return
	car.apply_oil_slip()
