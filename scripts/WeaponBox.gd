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

	# Крутящийся куб — косметика. Серверу он не нужен и вреден: headless-
	# рендер сыпет по мешам «Parameter m is null» в stderr, journald от
	# такого потока включает rate limit и глотает наши [net]-сообщения.
	if not Net.is_server():
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
		set_physics_process(true)


## СЕРВЕР: подбор машиной ЖИВОГО ИГРОКА проверяем сами, по сырым данным
## владельца (Car.true_position), а не по телу марионетки. Тело сервер
## ведёт СГЛАЖЕННО (_follow_snapshot — подтяжка с упреждением), и на
## поворотах оно идёт в стороне от настоящего пути; куб всего 1.3 м, и
## игрок «задевал куб, а бонус не давался» (жалоба 28.08). Area3D для
## ботов и оффлайна оставлена как была — там тело и есть правда.
## Меряем зазор от куба до ОТРЕЗКА кузова (как _bounce_off_cars): машина
## 3.2 x 1.7 м, поэтому полудлина 0.9 плюс полуширина куба и кузова.
func _physics_process(_delta: float) -> void:
	if Net.is_client() or not Net.is_online():
		return
	for node in get_tree().get_nodes_in_group("cars"):
		var car := node as Car
		if car == null or car.net_role != Car.NetRole.PUPPET:
			continue
		if not car.alive or car.is_ghost():
			continue
		var p := car.true_position()
		if absf(p.y - global_position.y) > 1.6:
			continue
		var f := car.true_forward() * 0.9
		var a := p - f
		var b := p + f
		var ab := b - a
		var len2 := ab.length_squared()
		var t := 0.0
		if len2 > 1e-6:
			t = clampf((global_position - a).dot(ab) / len2, 0.0, 1.0)
		var near := a + ab * t
		var gap := Vector2(near.x - global_position.x,
				near.z - global_position.z).length()
		if gap < 1.5:
			_give(car)


func _process(delta: float) -> void:
	if _mesh == null:
		return   # сервер: куба нет, крутить нечего
	_mesh.rotate_y(1.6 * delta)
	_mesh.rotation.x = 0.35 * sin(Time.get_ticks_msec() / 400.0)


func _on_body(body: Node3D) -> void:
	var car := body as Car
	if car == null or not car.alive or car.is_ghost():
		return
	# Машины живых игроков считает _physics_process по сырым данным — иначе
	# один проезд засчитался бы дважды (откат ниже это и так ловит, но
	# честнее не проверять одно и то же двумя способами).
	if car.net_role == Car.NetRole.PUPPET and Net.is_server():
		return
	_give(car)


## Выдать бонус, если этой машине уже можно (личный откат).
func _give(car: Car) -> void:
	var id := car.get_instance_id()
	var now := Time.get_ticks_msec() / 1000.0
	if _next_pickup.get(id, 0.0) > now:
		return
	_next_pickup[id] = now + PER_CAR_COOLDOWN
	# Шансы зависят от положения в гонке (последнему реже мина/масло,
	# отставшему чаще буст) — их знает менеджер гонки; без него (стенды,
	# где бокс стоит сам по себе) — равновероятно.
	if car.race != null and car.race.has_method("pickup_weapon_for"):
		car.weapon = car.race.pickup_weapon_for(car)
	else:
		car.weapon = Weapons.random_weapon()
	FlashFx.spawn(get_parent(), global_position, 0.9, Color(1.0, 0.9, 0.3))
	SparksFx.spawn(get_parent(), global_position, 5.0)
	FxKit.stars_burst(get_parent(), global_position + Vector3.UP * 0.4, 5)
