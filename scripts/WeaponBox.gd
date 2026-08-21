class_name WeaponBox
extends Area3D
## Бокс с оружием на трассе: вращающийся золотой куб. Подбор даёт машине
## один СЛУЧАЙНЫЙ вид оружия (заменяя текущее — в руках только одно).
## Бокс НЕ ИСЧЕЗАЕТ: он общий для всех, и каждый проехавший через него
## забирает СВОЙ случайный бонус — первый не обделяет остальных.
## От повторной выдачи защищает личный для каждой машины откат
## (PER_CAR_COOLDOWN): body_entered срабатывает только на входе, но
## машина, стоящая на боксе, может дёргаться на подвеске и входить-
## выходить каждые пару кадров — без отката она фармила бы оружие.

const PER_CAR_COOLDOWN := 2.5

var _mesh: MeshInstance3D
# id машины → время (сек. с запуска), когда ей снова можно выдать бонус.
var _next_pickup := {}


func _ready() -> void:
	# Машины — на слое 4 (см. Car._ready), бокс ловит только их.
	collision_layer = 0
	collision_mask = 0b100
	monitorable = false

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.3, 1.3, 1.3)
	col.shape = box
	add_child(col)

	_mesh = MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(1.1, 1.1, 1.1)
	_mesh.mesh = cube
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.82, 0.15, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.65, 0.1)
	mat.emission_energy_multiplier = 1.4
	_mesh.material_override = mat
	add_child(_mesh)

	# На клиенте бокс — просто крутящийся куб: оружие выдаёт сервер и
	# присылает его в снимке. Иначе клиент выдал бы себе своё, случайное.
	if Net.is_client():
		set_deferred("monitoring", false)
	else:
		body_entered.connect(_on_body)


func _process(delta: float) -> void:
	_mesh.rotate_y(1.6 * delta)
	_mesh.rotation.x = 0.35 * sin(Time.get_ticks_msec() / 400.0)


func _on_body(body: Node3D) -> void:
	var car := body as Car
	if car == null or not car.alive or car.is_ghost():
		return
	var id := car.get_instance_id()
	var now := Time.get_ticks_msec() / 1000.0
	if _next_pickup.get(id, 0.0) > now:
		return
	_next_pickup[id] = now + PER_CAR_COOLDOWN
	car.weapon = Weapons.random_weapon()
	FlashFx.spawn(get_parent(), global_position, 0.9, Color(1.0, 0.9, 0.3))
