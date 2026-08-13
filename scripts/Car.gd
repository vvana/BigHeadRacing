class_name Car
extends RigidBody3D
## Аркадная машина в духе Rock'n'Roll Racing — и игрок, и ИИ-соперник.
## Физика: RigidBody3D + 4 луча-«колеса» с пружинной подвеской.
## Настройка «как в RnRR»: резкий разгон, быстрый руль почти без потери
## на скорости, высокое сцепление (снос только с ручником), прыжок,
## упругие отскоки от стен и машин.
## Бой: снаряды вперёд (fire), мины назад (drop), HP, взрыв и возрождение.

@export_group("Движение")
@export var engine_power := 110.0       # разгон «в пол» ~2.5 с до сотни
@export var brake_power := 80.0
@export var max_speed := 26.0
@export var steer_speed := 3.4          # руль быстрый — аркада
@export var steer_speed_min := 2.2      # и на скорости почти не тупеет

@export_group("Сцепление")
@export var grip := 14.0                # высокое: машина едет куда смотрит
@export var grip_handbrake := 2.0       # ручник — дрифт

@export_group("Подвеска")
@export var suspension_rest := 0.55     # длина покоя пружины, м
@export var suspension_strength := 90.0 # жёсткость пружины
@export var suspension_damping := 11.0  # демпфер

@export_group("Прочее")
@export var jump_impulse := 6.0         # взлётная скорость прыжка, м/с (фишка RnRR)
@export var is_player := true

@export_group("Бой")
@export var max_hp := 100.0
@export var ammo_max := 6               # снарядов на круг
@export var mines_max := 3              # мин на круг

# Точки подвески в локальных координатах (x — вправо, z — назад).
const WHEEL_POINTS: Array[Vector3] = [
	Vector3(-0.85, 0.0, -1.3),  # перед-лево
	Vector3(0.85, 0.0, -1.3),   # перед-право
	Vector3(-0.85, 0.0, 1.3),   # зад-лево
	Vector3(0.85, 0.0, 1.3),    # зад-право
]

# Состояние боя/гонки.
var hp := 100.0
var ammo := 6
var mines := 3
var alive := true
var controls_enabled := false   # включает менеджер гонки после отсчёта
var track: TrackBuilder = null  # ставит Main: маршрут ИИ и точки респавна
var ai_rubber := 1.0            # «резинка»: множитель тяги/скорости ИИ

var _grounded_wheels := 0
var _can_jump := true
var _wheel_pivots: Array[Node3D] = []
var _steer_visual := 0.0
var _ai_fire_cd := 2.0


func _ready() -> void:
	mass = 120.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.3, 0)  # низкий центр масс — меньше переворотов
	can_sleep = false
	# Стены — тонкий ConcavePolygonShape3D: без непрерывной коллизии
	# на скорости можно протуннелировать внутрь и застрять.
	continuous_cd = true
	# Упругие столкновения (рикошет от стен и машин — дух RnRR).
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.4
	physics_material_override.friction = 0.5
	add_to_group("cars")
	hp = max_hp
	ammo = ammo_max
	mines = mines_max
	_build_collision()


## Форма корпуса — «санки»: плоское днище-упор (не даёт провалиться под
## дорогу при пробое подвески) со скошенными носом и кормой (чтобы не
## втыкаться в трамплины, а заезжать на них).
func _build_collision() -> void:
	var col := CollisionShape3D.new()
	col.name = "BodyShape"
	var shape := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for sx: float in [-0.85, 0.85]:
		for sz: float in [-1.5, 1.5]:
			pts.append(Vector3(sx, 0.70, sz))  # верхняя плита
			pts.append(Vector3(sx, 0.05, sz))  # нижняя кромка носа/кормы
		for sz: float in [-1.1, 1.1]:
			pts.append(Vector3(sx, -0.28, sz))  # днище (короче корпуса)
	shape.points = pts
	col.shape = shape
	add_child(col)


func _physics_process(delta: float) -> void:
	_apply_suspension(delta)
	var on_ground := _grounded_wheels >= 2
	if alive and controls_enabled:
		if is_player:
			_player_control(delta, on_ground)
		else:
			_ai_control(delta, on_ground)
	_animate_wheels(delta)


func _player_control(delta: float, on_ground: bool) -> void:
	var throttle := Input.get_axis("brake", "accelerate")
	var steer := Input.get_axis("steer_right", "steer_left")
	var handbraking := Input.is_action_pressed("handbrake")
	var jumping := Input.is_action_just_pressed("jump")
	_drive(delta, on_ground, throttle, steer, handbraking, jumping)
	if Input.is_action_just_pressed("fire"):
		shoot()
	if Input.is_action_just_pressed("drop"):
		drop_mine()


## ИИ: едет к точке на оси трассы впереди себя, стреляет по машине в прицеле,
## кидает мину под соперника сзади.
func _ai_control(delta: float, on_ground: bool) -> void:
	if track == null:
		return
	var curve: Curve3D = track._curve
	var length := curve.get_baked_length()
	var my_off := curve.get_closest_offset(global_position)
	var look := 6.0 + linear_velocity.length() * 0.45
	var target := curve.sample_baked(fposmod(my_off + look, length))

	var to_target := target - global_position
	to_target.y = 0.0
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	var angle := fwd.signed_angle_to(to_target, Vector3.UP)
	var steer := clampf(angle * 2.0, -1.0, 1.0)
	var throttle := 1.0 if absf(angle) < 0.9 else 0.45
	_drive(delta, on_ground, throttle, steer, false, false)

	_ai_fire_cd -= delta
	if _ai_fire_cd <= 0.0:
		_ai_fire_cd = randf_range(1.6, 3.2)
		if _enemy_ahead():
			shoot()
		elif _enemy_behind() and randf() < 0.5:
			drop_mine()


## Общая аркадная езда для игрока и ИИ.
func _drive(
	delta: float, on_ground: bool,
	throttle: float, steer: float, handbraking: bool, jumping: bool
) -> void:
	_steer_visual = lerpf(_steer_visual, steer * 0.45, 9.0 * delta)

	var forward := -global_transform.basis.z
	var speed := linear_velocity.dot(forward)
	var eff_max := max_speed * ai_rubber

	if on_ground:
		# Тяга/тормоз.
		if absf(speed) < eff_max or signf(throttle) != signf(speed):
			var power := engine_power if throttle > 0.0 else brake_power
			apply_central_force(
					forward * throttle * power * ai_rubber * mass * 0.1)

		# Руль: почти не слабеет на скорости (RnRR-манёвренность).
		if absf(speed) > 0.5:
			var speed_t: float = clampf(absf(speed) / max_speed, 0.0, 1.0)
			var turn_rate: float = lerpf(steer_speed, steer_speed_min, speed_t)
			# Задний ход — руль зеркалится, как в жизни.
			var direction := signf(speed)
			angular_velocity.y = lerpf(
				angular_velocity.y,
				steer * turn_rate * direction,
				10.0 * delta
			)

		# Гашение бокового сноса (аркадное сцепление).
		var right := global_transform.basis.x
		var side_speed := linear_velocity.dot(right)
		var current_grip := grip_handbrake if handbraking else grip
		apply_central_force(-right * side_speed * current_grip * mass * 0.1)

		# Прыжок — фирменная механика Rock'n'Roll Racing.
		if jumping and _can_jump:
			# Импульс разовый: mass * скорость (без 0.1 — это не сила за кадр).
			apply_central_impulse(Vector3.UP * jump_impulse * mass)
			_can_jump = false
			get_tree().create_timer(0.8).timeout.connect(
				func() -> void: _can_jump = true
			)
	else:
		# В воздухе активно выравниваем корпус к горизонту (и гасим кувырок),
		# чтобы приземляться на колёса, а не на крышу.
		var up := global_transform.basis.y
		var torque := up.cross(Vector3.UP) * 14.0 * mass * 0.1
		# Демпфируем вращение по крену/тангажу, рысканье не трогаем.
		var spin := angular_velocity
		spin.y = 0.0
		torque -= spin * 2.5 * mass * 0.1
		apply_torque(torque)


func _apply_suspension(_delta: float) -> void:
	_grounded_wheels = 0
	var space := get_world_3d().direct_space_state

	for point in WHEEL_POINTS:
		var start := global_transform * point
		var end := start + (-global_transform.basis.y) * suspension_rest

		var query := PhysicsRayQueryParameters3D.create(start, end)
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue

		_grounded_wheels += 1
		var hit_pos: Vector3 = hit["position"]
		var compression := 1.0 - start.distance_to(hit_pos) / suspension_rest

		# Пружина + демпфер вдоль оси корпуса вверх. Пружина прогрессивная:
		# при сильном сжатии (жёсткое приземление) жёсткость резко растёт,
		# чтобы подвеска не пробивалась «в пол».
		var up := global_transform.basis.y
		var point_velocity := linear_velocity + angular_velocity.cross(start - global_position)
		var progressive := 1.0 + 2.0 * compression * compression
		var spring_force := compression * suspension_strength * progressive
		var damp_force := -up.dot(point_velocity) * suspension_damping
		var force := up * (spring_force + damp_force) * mass * 0.1

		apply_force(force, start - global_position)


# ---------- Бой ----------

func shoot() -> void:
	if not alive or ammo <= 0:
		return
	ammo -= 1
	var dir := -global_transform.basis.z
	var p := Projectile.new()
	p.shooter = self
	p.direction = dir
	get_parent().add_child(p)
	p.global_position = global_position + dir * 2.3 + Vector3.UP * 0.55


func drop_mine() -> void:
	if not alive or mines <= 0:
		return
	mines -= 1
	var m := Mine.new()
	m.dropper = self
	get_parent().add_child(m)
	m.global_position = global_position \
			+ global_transform.basis.z * 2.4 + Vector3.UP * 0.1


func take_damage(amount: float, dir: Vector3) -> void:
	if not alive:
		return
	hp -= amount
	# Толчок от попадания — машину шатает, как в RnRR.
	apply_central_impulse((dir.normalized() + Vector3.UP * 0.4) * mass * 1.5)
	if hp <= 0.0:
		_explode()


## Подрыв: машину подбрасывает и крутит, управление отключается на пару
## секунд, потом она сама встаёт на трассу. Машина всё время видима —
## исчезновение выглядело как баг.
func _explode() -> void:
	alive = false
	hp = 0.0
	FlashFx.spawn(get_parent(), global_position, 2.4, Color(1.0, 0.45, 0.1))
	# Подброс и закрутка — эффектно и сразу понятно, что тебя подорвали.
	apply_central_impulse(Vector3.UP * 5.5 * mass)
	apply_torque_impulse(Vector3(
		randf_range(-1.0, 1.0), randf_range(-0.6, 0.6), randf_range(-1.0, 1.0)
	) * mass * 2.0)

	await get_tree().create_timer(1.6).timeout
	if not is_inside_tree():
		return
	if track:
		global_transform = track.respawn_transform(global_position)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	hp = max_hp
	alive = true


## Пополнение боезапаса (менеджер гонки зовёт на каждом новом круге).
func refill_ammo() -> void:
	ammo = ammo_max
	mines = mines_max


func _enemy_ahead() -> bool:
	var fwd := -global_transform.basis.z
	for node in get_tree().get_nodes_in_group("cars"):
		var other := node as Car
		if other == self or not other.alive:
			continue
		var to := other.global_position - global_position
		if to.length() < 22.0 and fwd.angle_to(to) < 0.22:
			return true
	return false


func _enemy_behind() -> bool:
	var back := global_transform.basis.z
	for node in get_tree().get_nodes_in_group("cars"):
		var other := node as Car
		if other == self or not other.alive:
			continue
		var to := other.global_position - global_position
		if to.length() < 10.0 and back.angle_to(to) < 0.6:
			return true
	return false


# ---------- Визуал ----------

## Регистрирует пивоты колёс модели (создаёт CarModelLibrary.build).
## Вызывать после добавления визуальной модели в машину.
func collect_wheels(model: Node) -> void:
	_wheel_pivots.clear()
	for child in model.get_children():
		if child is Node3D and child.has_meta("wheel_radius"):
			_wheel_pivots.append(child)


## Вращение колёс по скорости качения и поворот передних по рулю.
func _animate_wheels(delta: float) -> void:
	if _wheel_pivots.is_empty():
		return
	var forward := -global_transform.basis.z
	var speed := linear_velocity.dot(forward)
	for pivot in _wheel_pivots:
		var radius: float = pivot.get_meta("wheel_radius")
		var sign_: float = pivot.get_meta("spin_sign")
		pivot.rotation.x += sign_ * (speed / maxf(radius, 0.05)) * delta
		if pivot.get_meta("is_front"):
			pivot.rotation.y = _steer_visual


## Есть ли под машиной земля вплотную. Луч идёт строго вниз по миру
## (не по оси кузова) — поэтому работает и когда машина на крыше,
## где лучи подвески смотрят в небо.
func is_near_ground(max_dist := 1.4) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + Vector3.DOWN * max_dist)
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()


## Текущая скорость в км/ч — для HUD.
func speed_kmh() -> float:
	return linear_velocity.length() * 3.6
