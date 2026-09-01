class_name SoccerBall
extends RigidBody3D
## Футбольный мяч: крупная упругая сфера, которую машины толкают корпусом.
## Слой 4 (как машины) — снаряды/зоны в футболе не живут, а вот машины по
## маске 0b111 честно сталкиваются с мячом решателем. Поверх физики —
## ручной «пинок» при контакте с машиной: комбинация материалов Годо
## (у машин bounce = 0) делала бы мяч вялым, а в аркаде мяч должен
## ощутимо улетать от удара.

const RADIUS := 1.1
const KICK_SPEED := 1.35      # доля скорости сближения, уходящая в пинок
const KICK_UP := 2.4          # подброс при сильном ударе, м/с
const KICK_COOLDOWN := 0.12   # окно тишины на машину, с (дребезг контакта)
const MAX_SPEED := 42.0       # мяч не быстрее машин с большим запасом

# Ведение мяча (просьба 01.09): «при врезании передом мяч примагничивается,
# чтобы перехватить — нужно ударить в машину, ведущую мяч; мяч отмагничивается
# и при повторном ударе передом снова примагничивается».
const GRAB_COS := 0.7         # конус «переда»: до ~45° от носа
const GRAB_DIST := 2.85       # якорь у носа: полукузов 1.6 + радиус + зазор
const NO_GRAB_TIME := 1.2     # экс-ведущему сразу липнуть нельзя, с
const FOLLOW_GAIN := 10.0     # жёсткость «магнита», 1/с
const FOLLOW_CAP := 24.0      # поправка магнита не быстрее, м/с
const DETACH_POP := 5.0       # пинок мячу при перехвате, м/с

var last_touch: Car = null    # кто коснулся последним (автор гола)
var carrier: Car = null       # кто ведёт мяч (примагничен к его носу)
var _kick_mute := {}          # Car -> время до следующего пинка
var _no_grab := {}            # Car -> время запрета повторного захвата

# Пара положений тела для гладкого рендера (как у Car): тело шагает 60 Гц,
# кадры рендера идут своим темпом — камера и метка держатся за visual_origin.
var _vis_prev := Vector3.ZERO
var _vis_cur := Vector3.ZERO
var _vis_on := false


func _ready() -> void:
	mass = 32.0
	collision_layer = 0b100
	collision_mask = 0b111
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 8
	linear_damp = 0.5       # мяч сам замедляется — не катится вечно
	angular_damp = 0.6
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.55   # упругий отскок от стен/земли
	physics_material_override.friction = 0.6  # и честное качение

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	add_child(shape)

	if not Net.is_server():
		_build_visual()


## Бело-чёрный «футбольный» мяч: белая сфера + чёрные пятна-пятиугольники,
## запечённые в текстуру кодом (внешних ассетов нет, как и всюду в проекте).
func _build_visual() -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = "BallMesh"
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _make_texture()
	mat.roughness = 0.5
	mesh.material_override = mat
	add_child(mesh)


func _make_texture() -> ImageTexture:
	var w := 256
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.94, 0.94, 0.92))
	# Пятна в шахматном порядке двух рядов — на сфере читается как
	# классический мяч; полюса не трогаем (там UV сжимается в точку).
	for row in 2:
		var v := 0.36 if row == 0 else 0.64
		for k in 6:
			var u := (float(k) + (0.5 if row == 1 else 0.0)) / 6.0
			_blot(img, u * w, v * h, 13.0)
	return ImageTexture.create_from_image(img)


func _blot(img: Image, cx: float, cy: float, r: float) -> void:
	for y in range(maxi(0, int(cy - r)), mini(img.get_height(), int(cy + r) + 1)):
		for x in range(int(cx - r), int(cx + r) + 1):
			if Vector2(x - cx, y - cy).length() <= r:
				# По горизонтали текстура замкнута (сфера) — пятно у кромки
				# продолжается с другой стороны.
				img.set_pixel(posmod(x, img.get_width()), y, Color(0.1, 0.1, 0.12))


func _physics_process(delta: float) -> void:
	# Гладкий рендер (см. Car._track_visual): телепорт не интерполируем.
	_vis_prev = _vis_cur if _vis_on else global_position
	_vis_cur = global_position
	if _vis_prev.distance_to(_vis_cur) > 4.0:
		_vis_prev = _vis_cur
	_vis_on = true

	for c: Car in _kick_mute.keys():
		_kick_mute[c] -= delta
		if _kick_mute[c] <= 0.0:
			_kick_mute.erase(c)
	for c: Car in _no_grab.keys():
		_no_grab[c] -= delta
		if _no_grab[c] <= 0.0:
			_no_grab.erase(c)

	if carrier != null:
		_drive_carried()
	else:
		# Ручной пинок от машины: решатель уже развёл тела, но упругости от
		# машин нет (у их материала bounce 0) — добавляем свою, по скорости
		# сближения. Удар ПЕРЕДОМ вместо пинка примагничивает мяч (ведение).
		for body in get_colliding_bodies():
			var car := body as Car
			if car == null or _kick_mute.has(car):
				continue
			if _try_grab(car):
				break
			_kick_mute[car] = KICK_COOLDOWN
			last_touch = car
			var away := global_position - car.global_position
			away.y = 0.0
			if away.length_squared() < 1e-4:
				continue
			away = away.normalized()
			var closing := maxf(0.0,
					(car.linear_velocity - linear_velocity).dot(away))
			if closing < 0.5:
				continue
			var kick := away * closing * KICK_SPEED
			if closing > 8.0:
				kick.y = KICK_UP * clampf((closing - 8.0) / 14.0, 0.0, 1.0)
			apply_central_impulse(kick * mass)

	if linear_velocity.length() > MAX_SPEED:
		linear_velocity = linear_velocity.limit_length(MAX_SPEED)


## Мяч в конусе перед носом машины — примагнитить (начать ведение).
## Экс-ведущему в окне NO_GRAB_TIME липнуть нельзя: перехвативший должен
## успеть увести мяч, иначе ведение возвращалось бы тем же касанием.
func _try_grab(car: Car) -> bool:
	if _no_grab.has(car) or not car.alive or car.is_ghost():
		return false
	var fw := -car.global_transform.basis.z
	fw.y = 0.0
	var to_ball := global_position - car.global_position
	to_ball.y = 0.0
	if fw.length_squared() < 1e-6 or to_ball.length_squared() < 1e-4:
		return false
	if fw.normalized().dot(to_ball.normalized()) < GRAB_COS:
		return false
	carrier = car
	last_touch = car
	FlashFx.spawn(get_parent(), global_position, 0.5, Color(0.55, 0.9, 1.0))
	return true


## Ведение: мяч держится у носа ведущего. Магнит — СЕРВОСКОРОСТЬЮ, а не
## телепортом: решатель продолжает честно отталкивать мяч от бортов и штанг.
## Перехват: любой удар другой машины ПО ВЕДУЩЕМУ отлипляет мяч.
func _drive_carried() -> void:
	if carrier == null or not is_instance_valid(carrier) \
			or not carrier.alive or carrier.is_ghost():
		_release()
		return
	for body in carrier.get_colliding_bodies():
		var hitter := body as Car
		if hitter != null and hitter != carrier:
			var pop := global_position - hitter.global_position
			pop.y = 0.0
			_release()
			if pop.length_squared() > 1e-4:
				linear_velocity += pop.normalized() * DETACH_POP
			return
	var fwd := -carrier.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		return
	fwd = fwd.normalized()
	var anchor := carrier.global_position + fwd * GRAB_DIST
	anchor.y = maxf(RADIUS, carrier.global_position.y)
	# Магнит сорвался (мяч зажало у борта, ведущего отбросило далеко) —
	# отпускаем: тянуть мяч сквозь препятствия было бы читерством.
	if anchor.distance_to(global_position) > 6.0:
		_release()
		return
	last_touch = carrier
	var correction := (anchor - global_position) * FOLLOW_GAIN
	linear_velocity = carrier.linear_velocity + correction.limit_length(FOLLOW_CAP)


## Отлипание: экс-ведущий помечается в _no_grab — «при повторном ударе
## передом снова примагничивается», но не тем же самым касанием.
func _release() -> void:
	if carrier != null and is_instance_valid(carrier):
		_no_grab[carrier] = NO_GRAB_TIME
	carrier = null


## Где мяч ВИДЕН в этом кадре рендера (интерполяция между шагами физики).
func visual_origin() -> Vector3:
	if not _vis_on:
		return global_position
	return _vis_prev.lerp(_vis_cur, Engine.get_physics_interpolation_fraction())


## Телепорт на точку (кикофф): скорости и память визуала обнуляются.
func reset_to(pos: Vector3) -> void:
	global_position = pos
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_vis_on = false
	last_touch = null
	carrier = null
	_no_grab.clear()
