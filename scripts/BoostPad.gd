class_name BoostPad
extends Area3D
## Ускоритель на полотне: наехал — получил ускорение (тот же эффект, что
## бонус BOOST: Car.apply_boost, ×1.45 к тяге и потолку скорости на
## boost_duration). Ставится в НАЧАЛАХ прямых участков — ускорение выгодно
## именно перед прямой (TrackBuilder._build_boost_pads).
## Плита не исчезает и работает для всех машин, включая ботов. От дребезга
## подвески (вход-выход каждые пару кадров) — личный откат на машину, как
## у WeaponBox. По сети срабатывает ТОЛЬКО сервер: эффект своей машине
## клиента приезжает через Car._forward_fx → Main._rx_fx (путь бонуса
## BOOST, машина клиент-авторитетна), у клиента плита — просто картинка.

const PER_CAR_COOLDOWN := 3.0

# id машины → время (сек. с запуска), когда ей снова можно дать буст.
var _next_boost := {}


func _ready() -> void:
	# Машины — на слое 4 (см. Car._ready), плита ловит только их.
	collision_layer = 0
	collision_mask = 0b100
	monitorable = false

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Плоская зона над плитой: ловит кузов проезжающей машины.
	box.size = Vector3(3.2, 0.9, 4.6)
	col.shape = box
	col.position.y = 0.35
	add_child(col)

	# Косметика не для сервера (headless-рендер сыпет «Parameter m is null»).
	# Сетевой слой — по пути, а не по имени автолоада: в стендах --script
	# автолоадов нет, и упоминание Net валило компиляцию TrackBuilder
	# (test_curve, check_axis_jump, dump_profile).
	var net: Node = get_node_or_null("/root/Net")
	if net == null or not net.is_server():
		_build_visual()

	if net != null and net.is_client():
		set_deferred("monitoring", false)
	else:
		body_entered.connect(_on_body)


## Бирюзовая светящаяся плита с белыми шевронами «вперёд» (-Z).
func _build_visual() -> void:
	var plate := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(3.0, 0.06, 4.2)
	plate.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.7, 0.88)
	mat.emission_enabled = true
	mat.emission = Color(0.05, 0.55, 0.8)
	mat.emission_energy_multiplier = 0.9
	plate.material_override = mat
	plate.position.y = 0.04
	add_child(plate)

	var chev_mat := StandardMaterial3D.new()
	chev_mat.albedo_color = Color(0.95, 1.0, 1.0)
	chev_mat.emission_enabled = true
	chev_mat.emission = Color(0.8, 0.95, 1.0)
	chev_mat.emission_energy_multiplier = 1.2
	# Два шеврона «ёлочкой» остриём по ходу движения (-Z).
	for i in 2:
		for sx: float in [-1.0, 1.0]:
			var stripe := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(1.15, 0.05, 0.32)
			stripe.mesh = sm
			stripe.material_override = chev_mat
			stripe.position = Vector3(sx * 0.5, 0.09, 0.85 - i * 1.6)
			stripe.rotation.y = sx * deg_to_rad(-34.0)
			add_child(stripe)


func _on_body(body: Node3D) -> void:
	# Без имени класса Car: стенды --script компилируют TrackBuilder без
	# автолоадов, а Car ссылается на Net — утиная типизация вместо каста.
	if not body.has_method("apply_boost"):
		return
	var car = body
	if not car.alive or car.is_ghost():
		return
	var id := car.get_instance_id()
	var now := Time.get_ticks_msec() / 1000.0
	if _next_boost.get(id, 0.0) > now:
		return
	_next_boost[id] = now + PER_CAR_COOLDOWN
	car.apply_boost(true)
	FlashFx.spawn(get_parent(), global_position + Vector3.UP * 0.4, 0.8,
			Color(0.3, 0.9, 1.0))
