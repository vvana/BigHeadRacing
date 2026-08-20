class_name Car
extends RigidBody3D
## Аркадная машина в духе Rock'n'Roll Racing — и игрок, и ИИ-соперник.
## Физика: RigidBody3D + 4 луча-«колеса» с пружинной подвеской.
## Настройка «как в RnRR»: резкий разгон, быстрый руль почти без потери
## на скорости, высокое сцепление (снос только с ручником), прыжок,
## упругие отскоки от стен и машин.
## Бой: снаряды вперёд (fire), мины назад (drop), HP, взрыв и возрождение.

@export_group("Движение")
@export var engine_power := 150.0       # разгон «в пол» ~2.3 с до сотни
@export var brake_power := 100.0
@export var max_speed := 34.0
@export var steer_speed := 3.4          # руль быстрый — аркада
@export var steer_speed_min := 2.6      # и на скорости почти не тупеет
@export var steer_full_speed := 10.0    # к этой скорости руль набирает полную силу
@export var air_steer_speed := 2.2      # рысканье в полёте (можно рулить в воздухе)

@export_group("Сцепление")
@export var grip := 14.0                # высокое: машина едет куда смотрит
@export var grip_handbrake := 2.0       # ручник — дрифт

@export_group("Подвеска")
@export var suspension_rest := 0.55     # длина покоя пружины, м
@export var suspension_strength := 90.0 # жёсткость пружины
@export var suspension_damping := 11.0  # демпфер

@export_group("Прочее")
# Взлётная скорость прыжка, м/с (фишка RnRR). 7.5 при прижиме в полёте
# (см. _physics_process) даёт высоту ~1.9 м — ниже ограждения (2.6):
# с ровного места стену не перепрыгнуть, только с трамплина.
@export var jump_impulse := 7.5
@export var max_track_angle_deg := 80.0 # предел разворота поперёк оси трассы
@export var wall_align_speed := 7.0     # скорость доворота вдоль ограждения, 1/с
@export var bump_spin := 0.25           # закрутка от нецентрального удара машиной
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
var race_over := false          # финиш: газа нет, машина плавно тормозит
var track: TrackBuilder = null  # ставит Main: маршрут ИИ и точки респавна
var ai_rubber := 1.0            # «резинка»: множитель тяги/скорости ИИ

var _grounded_wheels := 0
var _can_jump := true
var _wall_align_time := 0.0     # окно доворота после касания стены, с
var _bump_spin_time := 0.0      # окно после тарана: руль не глушит закрутку
var _jump_time := 0.0           # после прыжка клапан вертикали у стены отключён
var _air_time := 0.0            # сколько уже летим, с (для нарастания прижима)
var _ground_time := 0.0         # сколько уже едем по земле без отрыва, с
var _ground_normal := Vector3.UP  # средняя нормаль опоры под колёсами
var _yaw_cmd_sign := 0.0        # знак рысканья, которое сейчас просит руль
# «Недавняя» горизонтальная скорость: максимум с медленным затуханием
# (30 м/с²). Устойчива к одному кадру, где решатель уже съел скорость, —
# мгновенное значение в такой кадр затирало бы память уже потерянным.
var _recent_hspeed := 0.0
var _recent_hdir := Vector3.ZERO  # направление на пике скорости (для защиты)
var _land_protect := 0.0        # окно защиты скорости после приземления, с
var _touch_cars := {}           # машины в контакте на прошлом кадре (рикошет)
# Для капа боковых «пинков» о рёбра полотна на ровной езде:
var _prev_hvel := Vector3.ZERO  # горизонтальная скорость прошлого кадра
var _ext_push_time := 0.0       # окно после честного толчка (таран/взрыв)
var _wheel_pivots: Array[Node3D] = []
var _steer_visual := 0.0
var _ai_fire_cd := 2.0


func _ready() -> void:
	mass = 250.0  # тяжёлая — увереннее толкается и стабильнее на скорости
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.3, 0)  # низкий центр масс — меньше переворотов
	can_sleep = false
	# Стены — тонкий ConcavePolygonShape3D: без непрерывной коллизии
	# на скорости можно протуннелировать внутрь и застрять.
	continuous_cd = true
	# Материальная упругость ОТКЛЮЧЕНА: bounce работал не только между
	# машинами, но и о дорогу — кузов скакал на стыках полотна («подскоки»)
	# и отбрасывался при нырке носом. Рикошет машина-машина теперь вручную
	# в _bounce_off_cars().
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.0
	# Трение корпуса почти нулевое: сцепление с дорогой — отдельная аркадная
	# сила в _drive, а трение материала работает при ЧИРКАНИИ корпуса о
	# землю/стену (ворует скорость — жалоба «замедляется при приземлении»)
	# и МЕЖДУ МАШИНАМИ (корпуса в контакте цеплялись и ехали вместе —
	# жалоба «прилипают друг к другу»).
	physics_material_override.friction = 0.05
	# Нужно для get_colliding_bodies() в _wall_slide.
	contact_monitor = true
	max_contacts_reported = 8
	# Кузов сталкивается и с миром (слой 1), и с ограждениями (слой 2);
	# лучи подвески при этом видят только слой 1 — по стене не ездим.
	collision_mask = 0b11
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
			# Днище (короче корпуса). Было -0.28: при рабочем прогибе
			# подвески (~0.25) клиренс оставался ~13 см, и на любом
			# переносе веса днище чиркало по полотну, ловя внутренние
			# рёбра тримеша, — серийные «прыжки на ровном» с потерей
			# скорости. -0.12 даёт ~29 см: при обычной езде кузов НЕ
			# касается дороги вовсе (урок из WaterSlides: не давать телу
			# трогать фасеточный меш); упор от провала под дорогу
			# по-прежнему срабатывает раньше полного пробоя пружин.
			pts.append(Vector3(sx, -0.12, sz))
	shape.points = pts
	col.shape = shape
	add_child(col)


func _physics_process(delta: float) -> void:
	_apply_suspension(delta)
	var on_ground := _grounded_wheels >= 2
	var hh := linear_velocity
	hh.y = 0.0
	# В окне защиты приземления память затухает еле-еле: иначе серия
	# кадров-«укусов» при скрежете корпуса сползает и память, и скорость.
	var decay := 5.0 if _land_protect > 0.0 else 30.0
	_recent_hspeed = maxf(0.0, _recent_hspeed - decay * delta)
	if hh.length() >= _recent_hspeed:
		_recent_hspeed = hh.length()
		# Направление запоминаем на пике — ДО удара: если удар развернёт
		# скорость, восстанавливать надо прежний курс, а не задний ход.
		if _recent_hspeed > 1.0:
			_recent_hdir = hh / _recent_hspeed
	if alive and controls_enabled:
		if is_player:
			_player_control(delta, on_ground)
		else:
			_ai_control(delta, on_ground)
	elif alive and race_over and on_ground:
		# После финиша машина плавно тормозит до полной остановки:
		# тормозной силой против хода, остаток скорости ниже 0.5 м/с
		# обнуляем (иначе на уклоне машина ползла бы вечно).
		var brake_h := linear_velocity
		brake_h.y = 0.0
		if brake_h.length() > 0.5:
			apply_central_force(
					-brake_h.normalized() * brake_power * mass * 0.1)
		else:
			linear_velocity.x = 0.0
			linear_velocity.z = 0.0
		angular_velocity.y = lerpf(angular_velocity.y, 0.0, 10.0 * delta)
	_jump_time = maxf(0.0, _jump_time - delta)
	_bump_spin_time = maxf(0.0, _bump_spin_time - delta)
	_protect_landing_speed(on_ground, delta)
	if alive:
		_bounce_off_cars()
	_air_time = 0.0 if on_ground else _air_time + delta
	_ground_time = _ground_time + delta if on_ground else 0.0
	if alive and not on_ground:
		# Прижим в полёте: тяжёлая машина быстро возвращается на асфальт —
		# чувство массы. Вниз сильнее, чем вверх, чтобы прыжок не задушить
		# (высота прыжка считается от «вверх»-ветки: g_up ≈ 14.8).
		# Сила НАРАСТАЕТ за 0.3 с полёта: микро-подлёты на стыках полотна
		# прижима не чувствуют — иначе он вбивал машину в асфальт на каждом
		# стыке, и серия ударов заметно съедала скорость.
		var ramp_t: float = clampf(_air_time / 0.3, 0.0, 1.0)
		var extra := (14.0 if linear_velocity.y < 0.0 else 5.0) * ramp_t
		apply_central_force(Vector3.DOWN * extra * mass)
	if alive and on_ground:
		# Отскок от земли РАЗРЕШЁН (аркадный подскок после жёсткой посадки),
		# но ограничен 3 м/с — депенетрация кузова иногда даёт дикие
		# выбросы. Главное, чтобы подскок был ПАРАЛЛЕЛЬНО земле — за это
		# отвечает выравнивание ниже и «нормаль-память» в полётной ветке.
		# Подъёмы/трамплины не страдают (там v·n ≈ 0), после прыжка —
		# клапан _jump_time.
		if _jump_time <= 0.0:
			var vn := linear_velocity.dot(_ground_normal)
			# Сразу после посадки разрешаем 3 м/с (аркадный отскок), а при
			# УСТОЯВШЕЙСЯ езде по ровному — только 1 м/с: днище, чиркая по
			# полотну, ловит внутренние рёбра треугольников коллизии, и
			# машина «подпрыгивала на ровном месте». На склонах и
			# трамплинах (нормаль наклонена) строгий клапан не применяем —
			# там vn законно растёт на переломах профиля.
			var allowed := 3.0
			if _ground_time > 0.35 and _ground_normal.y > 0.995:
				allowed = 0.6
				# Фантомный удар о ребро бьёт в угол днища и даёт
				# мгновенный ТАНГАЖ («подбрасывает перед на ровном»).
				# На установившейся ровной езде резких крена/тангажа
				# быть не может — жёстко ограничиваем. Наезд на трамплин
				# не задет: там нормаль опоры наклоняется, и ветка
				# выключается (порог 0.995 выше cos 9° = 0.988).
				var spin_h := angular_velocity
				spin_h.y = 0.0
				if spin_h.length() > 1.2:
					spin_h = spin_h.limit_length(1.2)
					angular_velocity = Vector3(
							spin_h.x, angular_velocity.y, spin_h.z)
				# Фантомный удар о ребро может дать и БОКОВОЙ пинок —
				# курс машины «внезапно меняет угол» на ровном месте.
				# Честная физика (грип 14, руль) меняет боковую скорость
				# максимум на ~0.3 м/с за кадр — режем всё, что выше 0.6.
				# Исключения: недавний честный толчок (таран, взрыв,
				# мина — _ext_push_time) и пристенок (там своё ведение
				# и свои капы).
				if _ext_push_time <= 0.0 and _wall_align_time <= 0.0 \
						and not _touching_wall():
					var h_flat := linear_velocity
					h_flat.y = 0.0
					if _prev_hvel.length() > 5.0 and h_flat.length() > 5.0:
						var prev_dir := _prev_hvel.normalized()
						var dv := h_flat - _prev_hvel
						var lat := dv - prev_dir * dv.dot(prev_dir)
						if lat.length() > 0.6:
							linear_velocity -= lat - lat.limit_length(0.6)
			if vn > allowed:
				linear_velocity -= _ground_normal * (vn - allowed)
		# Кузов активно выравнивается к плоскости дороги + сильное гашение
		# качки (закидывало нос при неравном сжатии пружин). Рысканье
		# не трогаем — руль работает.
		var up := global_transform.basis.y
		var spin := angular_velocity
		spin.y = 0.0
		apply_torque(
				(up.cross(_ground_normal) * 10.0 - spin * 4.0) * mass * 0.1)
	if alive:
		_wall_slide(delta)
		_clamp_heading(delta)
	_ext_push_time = maxf(0.0, _ext_push_time - delta)
	# Память для капа боковых пинков — в самом конце, после всех правок.
	_prev_hvel = linear_velocity
	_prev_hvel.y = 0.0


## Анимация колёс — в _process, а не _physics_process: кадр рисуется ПОСЛЕ
## решателя физики, и кламп колёс к полотну должен видеть уже конечное
## положение кузова (иначе на жёсткой посадке кузов доседал после клампа
## и колёса на кадр-два всё же ныряли под асфальт).
func _process(delta: float) -> void:
	_animate_wheels(delta)


## Приземление не должно замедлять: 0.25 с после касания не даём модулю
## горизонтальной скорости просесть ниже «недавней» (_recent_hspeed) —
## удар о землю и трение угла кузова съедали заметную часть.
## Направление не трогаем — руль работает.
func _protect_landing_speed(on_ground: bool, delta: float) -> void:
	# «Касание» шире, чем «2 колеса на земле»: при жёсткой посадке корпус
	# чиркает о дорогу раньше, чем встанут колёса, — эти кадры тоже защищаем.
	var contact := on_ground
	if not contact:
		for body in get_colliding_bodies():
			if body is StaticBody3D and not body.is_in_group("walls"):
				contact = true
				break
	if not contact:
		_land_protect = 0.25
		return
	if _land_protect <= 0.0 or not alive:
		return
	_land_protect -= delta
	var h := linear_velocity
	h.y = 0.0
	var s := h.length()
	if _recent_hspeed > 2.0 and s < _recent_hspeed:
		# Куда восстанавливать: если удар РАЗВЕРНУЛ скорость (нырок носом —
		# машину отталкивало и она уезжала задним ходом), берём запомненный
		# курс; если направление живо — текущее (руль работает).
		var dir := _recent_hdir
		if s > 0.5 and h.dot(_recent_hdir) > 0.0:
			dir = h / s
		var v := dir * _recent_hspeed
		linear_velocity.x = v.x
		linear_velocity.z = v.z


## Рикошет машина-машина вручную: материальная упругость отключена (она
## заставляла кузов скакать и от дороги), поэтому в момент НОВОГО контакта
## с другой машиной даём разовый толчок от неё, пропорциональный скорости
## сближения — упругие столкновения в духе RnRR без подскоков о полотно.
func _bounce_off_cars() -> void:
	var now := {}
	for body in get_colliding_bodies():
		var other := body as Car
		if other == null or not other.alive:
			continue
		var id := other.get_instance_id()
		now[id] = true
		var away := global_position - other.global_position
		away.y = 0.0
		var dist := away.length()
		if dist < 0.01:
			continue
		away /= dist
		# Контакт с машиной — честный источник боковых сил: кап боковых
		# пинков (см. _physics_process) на это окно отключаем.
		_ext_push_time = 0.3
		# Пока корпуса соприкасаются — лёгкое расталкивание (7 м/с²):
		# без него прижатые машины «слипались» и ехали вместе. Активный
		# таран всё равно продавливает (движок даёт 15 м/с²).
		apply_central_force(away * 70.0 * mass * 0.1)
		if _touch_cars.has(id):
			continue
		var closing := (other.linear_velocity - linear_velocity).dot(away)
		if closing > 0.5:
			apply_central_impulse(away * closing * 0.4 * mass)
		# Нецентральный удар ЗАКРУЧИВАЕТ: точка контакта — у соперника,
		# плечо — от центра к нему (не длиннее полукорпуса), момент =
		# плечо × относительная скорость соперника. Продольный таран мимо
		# центра «поддевает» корму/нос — машину доворачивает, как в RnRR.
		# Центральный импульс выше момента не даёт (проходит через центр).
		var rel := other.linear_velocity - linear_velocity
		rel.y = 0.0
		var lever := -away * minf(dist * 0.5, 1.5)
		var spin := lever.cross(rel.limit_length(15.0)).y * bump_spin
		if absf(spin) > 0.15:
			# Итог клампится: серия контактов (удар — отскок — снова удар)
			# не должна раскручивать волчком.
			angular_velocity.y = clampf(angular_velocity.y + spin, -3.0, 3.0)
			# Без окна руление в _drive съело бы закрутку за пару кадров.
			_bump_spin_time = 0.6
	_touch_cars = now


## Сброс памяти скорости. Звать при телепорте/респавне: иначе защита
## приземления «вернёт» скорость, которой у машины уже нет.
func reset_speed_memory() -> void:
	_recent_hspeed = 0.0
	_land_protect = 0.0


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
	# Умное торможение: скорость сбрасывается ЗАРАНЕЕ перед крутым
	# поворотом или кромкой обрыва, а не когда уже вылетел за ограждение.
	var allowed := _ai_allowed_speed(curve, length, my_off)
	var speed := linear_velocity.length()
	if speed > allowed + 1.5:
		throttle = -1.0
	elif speed > allowed:
		throttle = 0.0
	_drive(delta, on_ground, throttle, steer, false, false)

	_ai_fire_cd -= delta
	if _ai_fire_cd <= 0.0:
		_ai_fire_cd = randf_range(1.6, 3.2)
		if _enemy_ahead():
			shoot()
		elif _enemy_behind() and randf() < 0.5:
			drop_mine()


## Сколько ИИ можно ехать прямо сейчас, чтобы вписаться во всё, что впереди.
## Идём по оси трассы сэмплами, два предела скорости:
## 1) Поворот В ПЛАНЕ: нос крутится максимум steer_speed_min рад/с, значит
##    при кривизне κ вписаться можно лишь на v = ω/κ (с запасом 0.8).
## 2) ГРЕБЕНЬ (выпуклый перелом профиля — вершина подъёма, кромка обрыва):
##    быстрее v²·κ_верт = g машина ВЗЛЕТАЕТ — а в полёте она не рулит по
##    трассе и выше кромки ограждения не ведётся: летит по прямой и падает
##    за трассой, если трасса в это время поворачивает. Держим скорость у
##    предела отрыва (×1.35 — лёгкий подскок можно, дальний полёт нельзя).
## Дальним точкам разрешается быть быстрее на тормозной путь: v² = v_т²+2ad.
func _ai_allowed_speed(curve: Curve3D, length: float, my_off: float) -> float:
	var allowed := max_speed * ai_rubber
	var step := 4.0
	var prev := _axis_dir(curve, length, my_off)
	for i in range(1, 16):
		var d := step * i
		var dir := _axis_dir(curve, length, my_off + d)
		var prev_h := Vector3(prev.x, 0.0, prev.z)
		var dir_h := Vector3(dir.x, 0.0, dir.z)
		if prev_h.length_squared() > 1e-6 and dir_h.length_squared() > 1e-6:
			var bend_h := prev_h.normalized().angle_to(dir_h.normalized())
			if bend_h > 0.02:
				var v_corner: float = clampf(
						0.8 * steer_speed_min * step / bend_h, 10.0, max_speed)
				allowed = minf(allowed,
						sqrt(v_corner * v_corner + 2.0 * 8.0 * d))
		var pitch_drop := asin(clampf(prev.y, -1.0, 1.0)) \
				- asin(clampf(dir.y, -1.0, 1.0))
		if pitch_drop > 0.03:
			var v_crest: float = clampf(
					1.35 * sqrt(9.8 * step / pitch_drop), 10.0, max_speed)
			allowed = minf(allowed, sqrt(v_crest * v_crest + 2.0 * 8.0 * d))
		prev = dir
	return allowed


## Направление оси трассы (3D, с высотой) у отметки off.
func _axis_dir(curve: Curve3D, length: float, off: float) -> Vector3:
	var a := curve.sample_baked(fposmod(off, length))
	var b := curve.sample_baked(fposmod(off + 1.5, length))
	var d := b - a
	return d.normalized() if d.length_squared() > 1e-6 else Vector3.FORWARD


## Общая аркадная езда для игрока и ИИ.
func _drive(
	delta: float, on_ground: bool,
	throttle: float, steer: float, handbraking: bool, jumping: bool
) -> void:
	_steer_visual = lerpf(_steer_visual, steer * 0.45, 9.0 * delta)
	_yaw_cmd_sign = 0.0

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
		# После тарана (_bump_spin_time) руль слабый: жёсткий lerp съел бы
		# закрутку от удара за пару кадров, а машину должно довернуть.
		var yaw_rate := 2.5 if _bump_spin_time > 0.0 else 10.0
		if absf(speed) > 0.5:
			var speed_t: float = clampf(absf(speed) / max_speed, 0.0, 1.0)
			var turn_rate: float = lerpf(steer_speed, steer_speed_min, speed_t)
			# Скорость поворота коррелирует со скоростью машины: почти
			# стоя не развернёшься, полная сила руля — от steer_full_speed.
			turn_rate *= clampf(absf(speed) / steer_full_speed, 0.0, 1.0)
			# Задний ход — руль зеркалится, как в жизни.
			var direction := signf(speed)
			_yaw_cmd_sign = signf(steer) * direction
			angular_velocity.y = lerpf(
				angular_velocity.y,
				steer * turn_rate * direction,
				yaw_rate * delta
			)
		else:
			# Стоя руль не крутит, но случайную закрутку (от толчков,
			# приземлений на угол) гасим — сама разворачиваться не должна.
			angular_velocity.y = lerpf(angular_velocity.y, 0.0, yaw_rate * delta)

		# Гашение бокового сноса (аркадное сцепление).
		var right := global_transform.basis.x
		var side_speed := linear_velocity.dot(right)
		var current_grip := grip_handbrake if handbraking else grip
		apply_central_force(-right * side_speed * current_grip * mass * 0.1)

		# Прыжок — фирменная механика Rock'n'Roll Racing.
		if jumping and _can_jump:
			# Импульс разовый: mass * скорость (без 0.1 — это не сила за кадр).
			apply_central_impulse(Vector3.UP * jump_impulse * mass)
			_jump_time = 0.6
			_can_jump = false
			get_tree().create_timer(0.8).timeout.connect(
				func() -> void: _can_jump = true
			)
	else:
		# В полёте руль тоже работает: рысканье как на земле, но мягче.
		# Без руля цель — ноль: случайная закрутка на взлёте/приземлении
		# гасится, машина не разворачивается сама.
		var direction := 1.0 if speed >= 0.0 else -1.0
		if absf(steer) > 0.01:
			_yaw_cmd_sign = signf(steer) * direction
		angular_velocity.y = lerpf(
			angular_velocity.y,
			steer * air_steer_speed * direction,
			(2.0 if _bump_spin_time > 0.0 else 6.0) * delta
		)
		# В воздухе активно выравниваем корпус (и гасим кувырок), чтобы
		# приземляться на колёса. Первые полсекунды полёта цель — НОРМАЛЬ
		# последней опоры (подскок от земли идёт параллельно склону, нос
		# не задирается), дальше плавно переходим к горизонту (дальний
		# полёт — место посадки неизвестно).
		var target_up := _ground_normal.lerp(
				Vector3.UP, clampf(_air_time / 0.5, 0.0, 1.0)).normalized()
		var up := global_transform.basis.y
		var torque := up.cross(target_up) * 14.0 * mass * 0.1
		# Демпфируем вращение по крену/тангажу, рысканье не трогаем.
		var spin := angular_velocity
		spin.y = 0.0
		torque -= spin * 2.5 * mass * 0.1
		apply_torque(torque)


## У ограждения машина не тормозится и не отскакивает, а НАПРАВЛЯЕТСЯ
## вдоль стены без потери скорости: в полосе ~1.4 м до стены вся
## горизонтальная скорость перенаправляется вдоль касательной трассы
## с сохранением модуля. Именно ДО контакта: решатель столкновений
## успевает съесть нормальную составляющую раньше нашего кадра, и
## отредактированная задним числом скорость уже была бы потеряна.
## Всё направленно: движение и руление ОТ стены свободные. Доворот
## держится ещё 0.35 с после схода — закрутку от касания углом гасим.
func _wall_slide(delta: float) -> void:
	if track == null:
		return
	var curve: Curve3D = track._curve
	var length := curve.get_baked_length()
	var off := curve.get_closest_offset(global_position)
	var axis_pos := curve.sample_baked(off)
	var tangent := curve.sample_baked(fposmod(off + 0.5, length)) - axis_pos
	tangent.y = 0.0
	# Наружу — от оси трассы к стене (работает для обоих бортов).
	var n := global_position - axis_pos
	n.y = 0.0
	var dist := n.length()
	if tangent.length_squared() < 1e-6 or dist < 0.01:
		return
	tangent = tangent.normalized()
	n /= dist

	# Выше кромки ограждения ведение выключено — стену можно перелетать.
	# Ниже кромки оно работает ВСЕГДА, в том числе в полёте и сразу после
	# прыжка: раньше тут стоял таймер прыжка, и задев стену в полёте,
	# машина втыкалась в неё как в невидимую — контакт без перехвата
	# мгновенно съедал скорость.
	if global_position.y - 0.3 > axis_pos.y + TrackBuilder.WALL_HEIGHT:
		_wall_align_time = 0.0
		return

	var h := linear_velocity
	h.y = 0.0
	var v_out := h.dot(n)
	var touching := _touching_wall()
	# Просит ли руль прямо сейчас рысканье ПРОЧЬ от стены.
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		return
	fwd = fwd.normalized()
	var into_sign := signf(fwd.signed_angle_to(n, Vector3.UP))
	var steering_away := _yaw_cmd_sign != 0.0 and _yaw_cmd_sign == -into_sign
	# Зона ведения — динамическая: по вылету кузова В СТОРОНУ стены
	# (нос 1.5 м + борт 0.85 м, проекции на нормаль). Упреждение — ровно
	# ОДИН кадр сближения: перехватить надо до решателя (иначе он съест
	# скорость), но не раньше — машина должна ВИЗУАЛЬНО КАСАТЬСЯ
	# ограждения, когда подруливает вдоль него, а не отталкиваться от
	# невидимой стенки в полуметре.
	var reach := 0.0
	var fwd_h := -global_transform.basis.z
	fwd_h.y = 0.0
	var right_h := global_transform.basis.x
	right_h.y = 0.0
	if fwd_h.length_squared() > 1e-6:
		reach += 1.5 * absf(fwd_h.normalized().dot(n))
	if right_h.length_squared() > 1e-6:
		reach += 0.85 * absf(right_h.normalized().dot(n))
	var wall_face := TrackBuilder.TRACK_HALF_WIDTH \
			- TrackBuilder.WALL_THICKNESS * 0.5
	var guiding := touching or (
			v_out > 0.05 and dist + reach + v_out * delta * 1.2 > wall_face)
	if guiding:
		_wall_align_time = 0.35
	if _wall_align_time <= 0.0:
		return
	_wall_align_time -= delta

	# Перенаправляем на «рельс» только при СБЛИЖЕНИИ со стеной. Если
	# скорость уже от стены/вдоль — НЕ трогаем вовсе: раньше здесь
	# направление бралось из мгновенной скорости (которую решатель мог
	# только что развернуть ударом о ребро), а величина накачивалась из
	# памяти до полной — машину «выстреливало» в случайную сторону
	# («внезапно меняет направление»). Фантомные броски гасят капы ниже.
	if guiding and (v_out > 0.0 or h.length() < 0.1):
		# Вся горизонтальная скорость — вдоль стены, но с лёгким штрафом:
		# ограждение направляет и ЧУТЬ притормаживает — четверть скорости
		# сближения при перехвате + слабый скрежет, пока есть контакт.
		# Перепрыгнуть стену по-прежнему можно: выше кромки ведение
		# отключается (см. проверку высоты выше).
		var s := maxf(h.length(), _recent_hspeed)
		s -= 0.25 * maxf(v_out, 0.0)
		if touching:
			s -= 2.5 * delta
		s = maxf(s, 0.0)
		# Память скорости срезаем вслед — иначе она вернёт штраф обратно.
		_recent_hspeed = minf(_recent_hspeed, s)
		# Знак «вдоль»: мгновенная продольная скорость может быть ~0 или
		# искажена ударом — при слабом сигнале берём память направления,
		# затем нос (он ограничен ±80° к оси и назад не смотрит).
		var along := h.dot(tangent)
		if absf(along) < 2.0 and _recent_hdir != Vector3.ZERO:
			along = _recent_hdir.dot(tangent) * maxf(_recent_hspeed, 1.0)
		if absf(along) < 0.5:
			along = fwd.dot(tangent)
		var dir := tangent * (1.0 if along >= 0.0 else -1.0)
		if steering_away:
			# Руль просит прочь от стены — выпускаем ПОД УГЛОМ от
			# ограждения, а не строго вдоль. Иначе не оторваться:
			# кривизна трассы каждый кадр даёт новое сближение, ведение
			# снова ставит скорость «на рельс» и стирает всё, что руль
			# наработал, а довернуть нос мешает корма, упёртая в стену.
			var esc := dir.rotated(Vector3.UP, deg_to_rad(22.0))
			if esc.dot(n) > 0.0:
				esc = dir.rotated(Vector3.UP, -deg_to_rad(22.0))
			dir = esc
		linear_velocity = dir * s + Vector3.UP * linear_velocity.y
	# Стена — тримеш из сотен сегментов, и кузов-коробка, скользя вдоль,
	# иногда цепляет ВНУТРЕННЕЕ ребро стыка — решатель швыряет машину к
	# оси («еду вдоль ограждения и будто на что-то наезжаю») или вверх.
	# Пока машина в пристенке и руль НЕ просит прочь, скорости ОТ стены
	# взяться неоткуда — ограничиваем её 1.2 м/с (плавный отход за счёт
	# кривизны трассы остаётся). Подскок режем в том же окне.
	if not steering_away and (touching or _wall_align_time > 0.0):
		var h_now := linear_velocity
		h_now.y = 0.0
		var out_now := h_now.dot(n)
		if out_now < -1.2:
			linear_velocity -= n * (out_now + 1.2)
	if _jump_time <= 0.0 and (touching or _wall_align_time > 0.0):
		# Клапан подскока: депенетрация вклиненного угла/ребра не должна
		# закидывать кузов на стену (после прыжка отключён).
		linear_velocity.y = minf(linear_velocity.y, 1.0)
		# И не должна крутить кузов: удар о ребро сегмента у стены даёт
		# мгновенный крен/тангаж — режем жёстко (мягкое гашение торкой
		# ниже не успевает за разовым импульсом).
		var wall_spin := angular_velocity
		wall_spin.y = 0.0
		if wall_spin.length() > 1.5:
			wall_spin = wall_spin.limit_length(1.5)
			angular_velocity = Vector3(
					wall_spin.x, angular_velocity.y, wall_spin.z)
	if touching:
		# Царапание стены не должно опрокидывать: держим корпус к
		# горизонту и гасим крен/тангаж (как в полёте).
		var up := global_transform.basis.y
		var spin := angular_velocity
		spin.y = 0.0
		apply_torque((up.cross(Vector3.UP) * 14.0 - spin * 2.5) * mass * 0.1)

	# Если руль прямо сейчас просит рысканье ПРОЧЬ от стены — не мешаем:
	# ни доворота, ни гашения (иначе у стены нельзя отрулить).
	if steering_away:
		return
	# Иначе — доворот вдоль стены и полное гашение рысканья: без руля
	# любое вращение здесь — закрутка от удара углом, а не руление.
	var ang := fwd.signed_angle_to(tangent, Vector3.UP)
	rotate(Vector3.UP, ang * minf(1.0, wall_align_speed * delta))
	angular_velocity.y = 0.0


func _touching_wall() -> bool:
	for body in get_colliding_bodies():
		if body.is_in_group("walls"):
			return true
	return false


## Не даёт кузову развернуться больше max_track_angle_deg поперёк направления
## трассы в ближайшей точке (как в RnRR — задом наперёд не поедешь).
## Лишний угол снимается сразу, а рысканье урезается предиктивно: клампы
## выполняются ДО интеграции физики, и без предикции машина каждый кадр
## проскакивала бы за предел и дёргалась на границе.
func _clamp_heading(delta: float) -> void:
	if track == null:
		return
	var curve: Curve3D = track._curve
	var length := curve.get_baked_length()
	var off := curve.get_closest_offset(global_position)
	var tangent := curve.sample_baked(fposmod(off + 0.5, length)) \
			- curve.sample_baked(off)
	tangent.y = 0.0
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if tangent.length_squared() < 1e-6 or fwd.length_squared() < 1e-6:
		return
	var ang := tangent.signed_angle_to(fwd, Vector3.UP)
	var limit := deg_to_rad(max_track_angle_deg)
	if absf(ang) > limit:
		rotate(Vector3.UP, -(ang - signf(ang) * limit))
		ang = signf(ang) * limit
	# Положительное рысканье крутит нос туда же, куда растёт ang.
	var next := ang + angular_velocity.y * delta
	if absf(next) > limit:
		angular_velocity.y = (signf(next) * limit - ang) / delta


func _apply_suspension(_delta: float) -> void:
	_grounded_wheels = 0
	var normal_sum := Vector3.ZERO
	var space := get_world_3d().direct_space_state

	for point in WHEEL_POINTS:
		var start := global_transform * point
		var end := start + (-global_transform.basis.y) * suspension_rest

		var query := PhysicsRayQueryParameters3D.create(start, end)
		query.collision_mask = 1  # стены (слой 2) — не опора для колёс
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue

		_grounded_wheels += 1
		normal_sum += hit["normal"]
		var hit_pos: Vector3 = hit["position"]
		var compression := 1.0 - start.distance_to(hit_pos) / suspension_rest

		# Пружина + демпфер вдоль оси корпуса вверх. Пружина прогрессивная:
		# при сильном сжатии (жёсткое приземление) жёсткость резко растёт,
		# чтобы подвеска не пробивалась «в пол». Член c⁶ — жёсткий «упор»
		# у дна хода: в ложбинах профиля на скорости прожатие доходило до
		# 0.97-0.99, кузов проседал до касания днищем полотна (машина
		# скребла и притормаживала), а визуальные колёса уходили под
		# асфальт до 40 см. У прожатия покоя (~0.25) добавка ничтожна —
		# обычная езда не меняется.
		var up := global_transform.basis.y
		var point_velocity := linear_velocity + angular_velocity.cross(start - global_position)
		var c2 := compression * compression
		var progressive := 1.0 + 2.0 * c2 + 12.0 * c2 * c2 * c2
		var spring_force := compression * suspension_strength * progressive
		var damp_force := -up.dot(point_velocity) * suspension_damping
		var force := up * (spring_force + damp_force) * mass * 0.1

		apply_force(force, start - global_position)

	_ground_normal = normal_sum.normalized() \
			if normal_sum.length_squared() > 1e-4 else Vector3.UP


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
	# Толчок от попадания — машину шатает, как в RnRR. Кап боковых
	# пинков на это окно отключаем — толчок честный.
	_ext_push_time = 0.3
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
	reset_speed_memory()
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
			child.set_meta("rest_pos", (child as Node3D).position)
			child.set_meta("lift", 0.0)
			_wheel_pivots.append(child)


## Вращение колёс по скорости качения и поворот передних по рулю.
## Плюс кламп к полотну: кузов — жёсткое тело, при прожатии подвески он
## опускается, и колёса (запечённые в модель) уходили бы под асфальт.
## Каждый кадр луч вниз от ступицы ищет дорогу: если низ колеса оказался
## бы под ней — пивот приподнимается ровно на глубину утопания (вверх
## мгновенно, вниз плавно, чтобы колесо не дёргалось на стыках).
func _animate_wheels(delta: float) -> void:
	if _wheel_pivots.is_empty():
		return
	var forward := -global_transform.basis.z
	var speed := linear_velocity.dot(forward)
	var space := get_world_3d().direct_space_state
	# Из луча исключаем все машины: кузов соперника рядом — не дорога,
	# иначе колесо «вспрыгивало» на него.
	var car_rids: Array[RID] = []
	for node in get_tree().get_nodes_in_group("cars"):
		car_rids.append((node as RigidBody3D).get_rid())
	for pivot in _wheel_pivots:
		var radius: float = pivot.get_meta("wheel_radius")
		var sign_: float = pivot.get_meta("spin_sign")
		pivot.rotation.x += sign_ * (speed / maxf(radius, 0.05)) * delta
		if pivot.get_meta("is_front"):
			pivot.rotation.y = _steer_visual
		pivot.position = pivot.get_meta("rest_pos")
		var hub: Vector3 = pivot.global_position
		var query := PhysicsRayQueryParameters3D.create(
				hub + Vector3.UP * 1.0, hub + Vector3.DOWN * 2.0)
		query.collision_mask = 1  # стены — не дорога
		query.exclude = car_rids
		var hit := space.intersect_ray(query)
		var pen := 0.0
		if not hit.is_empty():
			pen = (hit["position"] as Vector3).y - (hub.y - radius)
		# Упреждение на пару шагов решателя: точка колеса сближается с
		# опорой ещё ПОСЛЕ нашего замера. Считаем по НОРМАЛИ опоры, а не
		# только по vy: при посадке носом колесо ныряет быстрее центра
		# (тангаж), а при заезде на наклон (трамплин) поверхность
		# «набегает» под колесо горизонтально (v·sin наклона). Перелёт
		# (колесо на пару см выше дороги один кадр) незаметен, недолёт —
		# виден.
		if not hit.is_empty():
			var point_v := linear_velocity \
					+ angular_velocity.cross(hub - global_position)
			var approach := -point_v.dot(hit["normal"])
			pen += maxf(0.0, approach) * delta * 2.0
		var target := clampf(pen, 0.0, 0.6)
		var lift: float = pivot.get_meta("lift")
		lift = target if target > lift else lerpf(lift, target, 12.0 * delta)
		pivot.set_meta("lift", lift)
		if lift > 0.001:
			pivot.global_position = hub + Vector3.UP * lift


## Есть ли под машиной земля вплотную. Луч идёт строго вниз по миру
## (не по оси кузова) — поэтому работает и когда машина на крыше,
## где лучи подвески смотрят в небо.
func is_near_ground(max_dist := 1.4) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position, global_position + Vector3.DOWN * max_dist)
	query.collision_mask = 1  # стены — не «земля»
	query.exclude = [get_rid()]
	return not space.intersect_ray(query).is_empty()


## Текущая скорость в км/ч — для HUD.
func speed_kmh() -> float:
	return linear_velocity.length() * 3.6
