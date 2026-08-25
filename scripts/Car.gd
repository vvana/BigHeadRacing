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
# Длительности эффектов оружия, с.
@export var ghost_time := 2.0           # «призрак» после уничтожения
@export var freeze_duration := 3.0      # замедление от ледышки
@export var boost_duration := 2.5      # ускорение
@export var slip_duration := 2.0        # занос от масляного пятна
@export var slip_grip := 0.3            # сцепление на масле (обычное 14)
@export var slip_thrust := 0.35         # доля тяги на масле — колёса буксуют

# Значок действующего эффекта над крышей.
const STATUS_ICON_SIZE := 1.7           # ширина значка, м
const STATUS_ICON_Y := 2.35             # высота над центром машины, м
const STATUS_ICON_PLAYER_Y := 3.25      # у игрока — выше маркера-стрелки

# Точки подвески в локальных координатах (x — вправо, z — назад).
const WHEEL_POINTS: Array[Vector3] = [
	Vector3(-0.85, 0.0, -1.3),  # перед-лево
	Vector3(0.85, 0.0, -1.3),   # перед-право
	Vector3(-0.85, 0.0, 1.3),   # зад-лево
	Vector3(0.85, 0.0, 1.3),    # зад-право
]

# Состояние боя/гонки.
var weapon := -1                # текущее оружие (Weapons.*), -1 — пусто
var alive := true
var controls_enabled := false   # включает менеджер гонки после отсчёта
var race_over := false          # финиш: газа нет, машина плавно тормозит
var track: TrackBuilder = null  # ставит Main: маршрут ИИ и точки респавна
var race: Node = null           # ставит Main: доступ к лидеру (авиаудар)
var ai_rubber := 1.0            # «резинка»: множитель тяги/скорости ИИ
# «Класс» ИИ: постоянный множитель темпа бота (< 1 — едет слабее игрока).
# Вкладывается в ai_rubber менеджером гонки (Main), сам по себе не читается.
var ai_skill := 1.0

# Эффекты оружия (таймеры, с).
var _ghost_time := 0.0          # после уничтожения: не трогает машины, мигает
var _freeze_time := 0.0         # замедление от ледышки (дебаф заразен)
var _boost_time := 0.0          # ускорение
var _slip_time := 0.0           # занос от масляного пятна
## Кто ведёт эту машину. LOCAL — как в одиночной игре (игрок за клавиатурой
## или бот). PUPPET — здесь её физику НЕ считают, а тянут к присланным
## снимкам: на клиенте это все чужие машины, на сервере — машины живых
## игроков (они КЛИЕНТ-АВТОРИТЕТНЫ: состояние присылает клиент владельца).
## OWNED — своя машина на клиенте: физика полностью локальная, сервер её
## НЕ подправляет вовсе. Раньше сервер считал её сам и «мягко подтягивал»
## клиентскую копию — на реальном канале серверное состояние отстаёт на
## пинг, подтяжка тянула машину назад каждый снимок, а при невязке больше
## 5 м телепортировала: те самые «рывки, играть невозможно».
enum NetRole { LOCAL, PUPPET, OWNED }
var net_role := NetRole.LOCAL
var net_fire := false           # сервер: клиент просил выстрел (гасится сразу)
## Эффекты оружия, пересылаемые сервером владельцу машины (Main._rx_fx):
## физику эффекта (толчок, разворот, телепорт) применяет клиент-владелец.
enum NetFx { DESTROY, BLAST, FREEZE, OIL, BOOST, SLOW }
var has_marker := false         # над машиной висит стрелка-указатель
# Последний снимок с сервера и его возраст. Марионетка тянется к нему,
# ЭКСТРАПОЛИРУЯ по присланной скорости, — см. _follow_snapshot.
var _snap_pos := Vector3.ZERO
var _snap_rot := Quaternion.IDENTITY
var _snap_vel := Vector3.ZERO
var _snap_age := 0.0
var _snap_seen := false
var _status_icon: Sprite3D = null  # значок действующего эффекта над крышей
var _status_kind := -1          # разовый значок (магнит): какой показываем
var _status_time := 0.0         # и сколько ему осталось
var _status_shown := -2         # что сейчас лежит в текстуре (-2 = ничего)
var _status_age := 0.0          # возраст показа: «выпрыгивание» и покачивание
var _ice_shell: MeshInstance3D  # визуал заморозки (голубая скорлупа)

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
# Защита от «депенетрации» марионетки (см. кап в _physics_process):
var _puppet_touch := false      # на прошлом кадре касались машины-марионетки
var _post_vel := Vector3.ZERO   # скорость в КОНЦЕ прошлого кадра (после правок)
var _blast_time := 0.0          # окно после взрыва: кап марионетки отключён
var _track_ang_abs := 0.0       # |угол носа к оси трассы|, ставит _clamp_heading
var _side_speed := 0.0          # боковой снос с последнего кадра езды (дым)
var _on_sand := false           # на песчаной трассе съехал с полотна на песок
var _smoke: Array[CPUParticles3D] = []  # дым из-под задних колёс (занос)
var _skid_active := false       # сильный занос: задние колёса чертят следы
var _skid_trails := {}          # пивот заднего колеса -> текущая SkidTrail
var _boost_flame: CPUParticles3D        # огонь из выхлопа при ускорении
var _boost_from_pad := false    # текущий буст — с плиты (см. apply_boost)
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
	# Машины живут на СВОЁМ слое 4: мир — слой 1, ограждения — слой 2.
	# Так «призрак» после уничтожения отключает только контакты с
	# машинами (лучи подвески видят слой 1 — по стене/машине не ездим),
	# а снаряды/мины/боксы ловят машины по маске 0b100.
	collision_layer = 0b100
	collision_mask = 0b111
	add_to_group("cars")
	_build_collision()
	# Форма корпуса нужна всегда (физика), а скорлупа льда, дым и значок
	# эффекта — только там, где есть экран. См. Main._set_car_model.
	if Net.is_server():
		return
	_build_ice_shell()
	_build_smoke()
	_build_boost_flame()
	_build_status_icon()
	# Фары — только на ночной городской трассе (track ставит Main ДО
	# add_child, как и для пыли на песке).
	if track != null and track.kind == TrackBuilder.KIND_NEON:
		_build_headlights()


## Значок действующего эффекта над крышей (магнит, ускорение). top_level
## ОБЯЗАТЕЛЕН: значок не должен наследовать поворот кузова — иначе при
## закрутке от масла и кувырке он ездит вокруг машины и уходит под землю.
## Позиция ставится каждый кадр в _tick_status_icon.
func _build_status_icon() -> void:
	_status_icon = Sprite3D.new()
	_status_icon.name = "StatusIcon"
	_status_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_icon.shaded = false
	_status_icon.double_sided = true
	_status_icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_status_icon.top_level = true
	_status_icon.visible = false
	add_child(_status_icon)


## Фары для ночного города: два узких спота вперёд (-Z), чуть вниз, С
## тенями — иначе луч просвечивает сквозь ограждения и стены (споты
## узкие и короткие, тени для них дёшевы). Плюс светящиеся «лампы» на
## носу — саму фару видно и сбоку.
func _build_headlights() -> void:
	for sx: float in [-0.55, 0.55]:
		var beam := SpotLight3D.new()
		beam.position = Vector3(sx, 0.45, -1.35)
		beam.rotation_degrees = Vector3(-10, 0, 0)
		beam.spot_range = 22.0
		beam.spot_angle = 30.0
		beam.light_energy = 6.0
		beam.light_color = Color(1.0, 0.93, 0.75)
		beam.shadow_enabled = true
		add_child(beam)

		var lamp := MeshInstance3D.new()
		var lamp_mesh := BoxMesh.new()
		lamp_mesh.size = Vector3(0.22, 0.12, 0.06)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.95, 0.8)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.93, 0.7)
		mat.emission_energy_multiplier = 2.0
		lamp.mesh = lamp_mesh
		lamp.material_override = mat
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.position = Vector3(sx, 0.42, -1.42)
		add_child(lamp)


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


## Голубая полупрозрачная «скорлупа льда» — видна, пока действует
## заморозка (машина «синеет»).
func _build_ice_shell() -> void:
	_ice_shell = MeshInstance3D.new()
	_ice_shell.name = "IceShell"
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 1.1, 3.4)
	_ice_shell.mesh = box
	_ice_shell.position.y = 0.45
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.7, 1.0, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.55, 1.0)
	mat.emission_energy_multiplier = 0.7
	_ice_shell.material_override = mat
	_ice_shell.visible = false
	add_child(_ice_shell)


## Дым из-под задних колёс — виден при сильном заносе (ручник в повороте,
## масло). Два CPUParticles3D у задних колёс; включаются в _physics_process.
## Клуб — билборд с мультяшной текстурой облачка (Epic Toon FX, атлас
## 2×2: каждой частице достаётся случайный кадр — клубы разной формы).
## Случайный поворот и рост клуба со временем жизни.
func _build_smoke() -> void:
	var tex: Texture2D = load("res://assets/fx/smoke_cloud_2x2.png")
	# Клуб рождается небольшим, быстро набухает и слегка дорастает.
	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.4))
	growth.add_point(Vector2(0.35, 1.0))
	growth.add_point(Vector2(1.0, 1.2))
	# Эмиттеры — строго ЗА задними колёсами, внутри колеи (x ±0.55):
	# на краю корпуса (±0.85) крупные клубы торчали по бокам машины.
	# Шлейф короткий: жизнь 0.5 с и слабый разлёт.
	for sx: float in [-0.55, 0.55]:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.amount = 16
		p.lifetime = 0.5
		p.local_coords = false   # клубы остаются позади машины
		p.direction = Vector3.UP
		p.spread = 25.0
		p.gravity = Vector3(0.0, 1.2, 0.0)
		p.initial_velocity_min = 0.5
		p.initial_velocity_max = 1.2
		p.angle_min = 0.0        # случайный поворот билборда
		p.angle_max = 360.0
		p.scale_amount_min = 0.55
		p.scale_amount_max = 0.95
		p.scale_amount_curve = growth
		# Случайный кадр атласа 2×2 на всю жизнь частицы (анимация не
		# крутится — у частицы случайный anim_offset).
		p.anim_offset_min = 0.0
		p.anim_offset_max = 1.0
		var quad := QuadMesh.new()
		quad.size = Vector2(0.7, 0.7)
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.particles_anim_h_frames = 2
		mat.particles_anim_v_frames = 2
		mat.particles_anim_loop = false
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = tex
		quad.material = mat
		p.mesh = quad
		var grad := Gradient.new()
		# На песчаной трассе пыль песочная (track ставится Main ДО add_child,
		# так что в _ready он уже известен; без track — обычный серый дым).
		if track != null and track.kind == TrackBuilder.KIND_SAND:
			grad.set_color(0, Color(0.87, 0.74, 0.5, 0.8))
			grad.set_color(1, Color(0.84, 0.72, 0.5, 0.0))
		else:
			grad.set_color(0, Color(0.92, 0.92, 0.92, 0.75))
			grad.set_color(1, Color(0.85, 0.85, 0.85, 0.0))
		p.color_ramp = grad
		p.position = Vector3(sx, 0.12, 1.5)
		add_child(p)
		_smoke.append(p)


## Огонь из выхлопа — бьёт из кормы, пока действует ускорение (бонус BOOST
## или плита-ускоритель). Языки пламени — АНИМИРОВАННЫЕ кадры огня из
## Epic Toon FX (атлас 6×3: у частицы случайный стартовый кадр, дальше
## листается по жизни — пламя «пляшет»). Аддитивное смешивание оставлено:
## перекрывающиеся языки высветляются до жёлто-белого и «светятся».
func _build_boost_flame() -> void:
	var tex: Texture2D = load("res://assets/fx/fire_6x3.png")

	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.05))
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 30
	p.lifetime = 0.13   # короткий язык: длинный хвост тянулся за машиной шлейфом
	p.local_coords = false   # струя остаётся позади машины
	# Почти горизонтально назад (+Z): струя из выхлопной трубы, а не костёр
	# на бампере — подъём убран, скорость выше, конус узкий.
	p.direction = Vector3(0.0, 0.04, 1.0)
	p.spread = 3.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 7.0
	p.initial_velocity_max = 10.0
	p.scale_amount_min = 0.22
	p.scale_amount_max = 0.34
	p.scale_amount_curve = shrink
	# Случайный стартовый кадр атласа + прокрутка кадров по жизни частицы.
	p.anim_offset_min = 0.0
	p.anim_offset_max = 1.0
	p.anim_speed_min = 1.0
	p.anim_speed_max = 2.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD   # свечение огня
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.particles_anim_h_frames = 6
	mat.particles_anim_v_frames = 3
	mat.particles_anim_loop = true   # offset+speed листают атлас по кругу
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	quad.material = mat
	p.mesh = quad
	# Жизнь клуба: бело-жёлтое ядро у сопла → оранжевый → тёмно-красный
	# гаснущий кончик (при ADD тёмный цвет сам сходит на нет).
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.97, 0.75, 1.0))
	grad.set_color(1, Color(0.55, 0.08, 0.01, 0.0))
	grad.add_point(0.3, Color(1.0, 0.62, 0.12, 1.0))
	grad.add_point(0.65, Color(0.95, 0.3, 0.03, 0.6))
	p.color_ramp = grad
	# Ниже и ЗА бампером (кузов 3.2 м, корма на 1.6): при сопле на самом
	# бампере половина струи в изометрии ложилась на багажник — «зад горит».
	p.position = Vector3(0.0, 0.3, 1.85)
	add_child(p)
	_boost_flame = p


func _physics_process(delta: float) -> void:
	if net_role == NetRole.PUPPET:
		# Таймеры эффектов тикают и у марионетки: серверу нужен живой
		# «призрак» для снимков, а марионетке на клиенте — его мигание.
		_tick_effects(delta)
		# Сервер: выстрел живого игрока. Его машина здесь марионетка
		# (клиент-авторитетна), но оружие по-прежнему применяет сервер —
		# иначе снаряд бил бы по-разному на каждом экране.
		if net_fire:
			net_fire = false
			use_weapon()
		# Движение к снимку — здесь, в ФИЗИКЕ. Перенос в _process (ради
		# плавности на мониторах >60 Гц) ПРОБОВАН и ОТКАЧЕН: метрика
		# стенда в headless рухнула с 2.6% до 57% с 40 рывками назад —
		# на реальный рендер это не переносится один в один, но выпускать
		# путь, который собственный стенд не может проверить, нельзя.
		# Если жалобы на дрожание на высокогерцовых мониторах останутся —
		# правильное решение это встроенная интерполяция физики Godot 4.4+.
		_follow_snapshot(delta)
		return
	# Кап «депенетрации» от марионетки. Чужая машина по сети — замороженное
	# кинематическое тело, которое ТЕЛЕПОРТИРУЕТСЯ к снимкам; шагнув в наш
	# кузов (особенно на рывке канала), решатель выдавливает нас диким
	# разовым импульсом — тот самый «огромный импульс ускорения при ударе».
	# Всё, что физика добавила к скорости сверх конца нашего прошлого кадра,
	# ограничиваем 5 м/с. Честный рикошет машин добавляется НАШИМ импульсом
	# в _bounce_off_cars (кап его не трогает — тот идёт позже в этом же
	# кадре), а толчок взрыва защищён окном _blast_time.
	if _puppet_touch and _blast_time <= 0.0:
		var dv_solver := linear_velocity - _post_vel
		if dv_solver.length() > 5.0:
			linear_velocity = _post_vel + dv_solver.limit_length(5.0)
	_puppet_touch = false   # заново выставит _bounce_off_cars этим кадром
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
	# Песчаная трасса: за кромкой полотна — рыхлый песок. Тяга и потолок
	# скорости режутся в _drive, из-под колёс всегда идёт песчаная пыль.
	_on_sand = alive and on_ground and track != null \
			and track.kind == TrackBuilder.KIND_SAND \
			and track.distance_from_axis(global_position) \
			> track.half_width_at_pos(global_position)
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
	_tick_effects(delta)
	# Дым из-под задних колёс: только СИЛЬНОЕ боковое скольжение (ручник
	# в повороте на скорости, занос от масла) — лёгкое подруливание и
	# небольшие сносы дымить не должны.
	var smoking := alive and on_ground and (
			(absf(_side_speed) > 5.0 and hh.length() > 8.0)
			or (_slip_time > 0.0 and hh.length() > 3.0)
			or (_on_sand and hh.length() > 3.0))
	for p in _smoke:
		p.emitting = smoking
	# Следы шин на асфальте: пороги ВЫШЕ дымовых — дым идёт от любого
	# сильного скольжения, а резина чертит только по-настоящему злой
	# занос, иначе трасса зарастала полосами везде, где дымило. Рисуем
	# только на полотне классической трассы (на песке след резины не
	# рисуем, на траве за трассой — тоже). Сами ленты тянет
	# _animate_wheels: у него уже есть лучи к дороге под каждым колесом.
	_skid_active = alive and on_ground \
			and ((absf(_side_speed) > 6.5 and hh.length() > 11.0)
				or (_slip_time > 0.0 and hh.length() > 6.0)) \
			and (track == null or (track.kind != TrackBuilder.KIND_SAND
				and track.distance_from_axis(global_position)
					< TrackBuilder.TRACK_HALF_WIDTH + 0.3))
	_ext_push_time = maxf(0.0, _ext_push_time - delta)
	_blast_time = maxf(0.0, _blast_time - delta)
	# Память для капов — в самом конце, после всех правок скорости.
	_prev_hvel = linear_velocity
	_prev_hvel.y = 0.0
	_post_vel = linear_velocity


## Таймеры эффектов оружия: заморозка, ускорение, занос, «призрак».
func _tick_effects(delta: float) -> void:
	_freeze_time = maxf(0.0, _freeze_time - delta)
	_boost_time = maxf(0.0, _boost_time - delta)
	_slip_time = maxf(0.0, _slip_time - delta)
	if _ice_shell:
		_ice_shell.visible = _freeze_time > 0.0
	# Огонь ускорения. У марионетки по сети свой _boost_time не тикает —
	# признак буста приезжает в снимке значком эффекта (_status_kind).
	if _boost_flame:
		# С плиты — узкий короткий язык, от турбины — полный.
		var narrow := _boost_from_pad and _boost_time > 0.0
		_boost_flame.scale_amount_min = 0.14 if narrow else 0.22
		_boost_flame.scale_amount_max = 0.22 if narrow else 0.34
		_boost_flame.spread = 2.0 if narrow else 3.0
		_boost_flame.emitting = alive and (_boost_time > 0.0
				or (_status_time > 0.0 and _status_kind == Weapons.BOOST))
	if _ghost_time > 0.0:
		_ghost_time -= delta
		if _ghost_time <= 0.0:
			# «Призрак» кончился: контакты с машинами снова включены.
			collision_layer = 0b100
			collision_mask = 0b111
			visible = true


## Анимация колёс — в _process, а не _physics_process: кадр рисуется ПОСЛЕ
## решателя физики, и кламп колёс к полотну должен видеть уже конечное
## положение кузова (иначе на жёсткой посадке кузов доседал после клампа
## и колёса на кадр-два всё же ныряли под асфальт).
func _process(delta: float) -> void:
	# Марионетка тянется к снимкам с частотой РЕНДЕРА, а не физики:
	# движение видно глазом каждый кадр, независимо от частоты монитора.
	# Телу-марионетке (заморожена кинематически) это безопасно — физика
	# увидит её актуальный трансформ на ближайшем тике.
	_animate_wheels(delta)
	_tick_status_icon(delta)
	if _ghost_time > 0.0:
		# Три моргания за время призрака: полпериода погашен — полпериода
		# виден (последний отрезок всегда «виден» — не застрять невидимым).
		var elapsed := ghost_time - _ghost_time
		var phase := int(elapsed / (ghost_time / 6.0))
		visible = phase % 2 == 1 or phase >= 5


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
		if other.net_role == NetRole.PUPPET:
			_puppet_touch = true
		# Заморозка заразна: коснулся «синей» машины — перенял остаток
		# её дебафа (и дальше передаёшь сам).
		if other._freeze_time > 0.2 and _freeze_time <= 0.0:
			_freeze_time = other._freeze_time
			FxKit.snow_burst(get_parent(), global_position + Vector3.UP * 0.6)
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
		# Скорость соперника — через contact_velocity(): у марионетки
		# linear_velocity врёт (Godot считает её по сдвигу замороженного
		# трансформа и на рывке канала выдаёт десятки м/с). Плюс кап 20:
		# рикошет от любого мусора в данных не превысит толчка 8 м/с.
		var other_vel := other.contact_velocity()
		var closing := minf((other_vel - linear_velocity).dot(away), 20.0)
		if closing > 0.5:
			apply_central_impulse(away * closing * 0.4 * mass)
			# Искры в точке удара. Обе машины видят один и тот же контакт —
			# спавнит только одна из пары (меньший instance id), не обе.
			if closing > 2.0 and get_instance_id() < id:
				var mid := (global_position + other.global_position) * 0.5
				SparksFx.spawn(get_parent(), mid + Vector3.UP * 0.45, closing)
				# Крепкий таран — мультяшные звёзды из точки удара.
				if closing > 4.0:
					FxKit.stars_burst(get_parent(), mid + Vector3.UP * 0.8,
							mini(4 + int(closing * 0.4), 9))
		# Нецентральный удар ЗАКРУЧИВАЕТ: точка контакта — у соперника,
		# плечо — от центра к нему (не длиннее полукорпуса), момент =
		# плечо × относительная скорость соперника. Продольный таран мимо
		# центра «поддевает» корму/нос — машину доворачивает, как в RnRR.
		# Центральный импульс выше момента не даёт (проходит через центр).
		var rel := other_vel - linear_velocity
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
## Скорость машины для расчётов столкновений. У марионетки linear_velocity
## брать нельзя: Godot пересчитывает её по сдвигу замороженного трансформа
## (завышает вдвое, а на рывке канала — многократно), берём присланную.
func contact_velocity() -> Vector3:
	return _snap_vel if net_role == NetRole.PUPPET else linear_velocity


func reset_speed_memory() -> void:
	_recent_hspeed = 0.0
	_land_protect = 0.0
	# И память капа марионетки: после телепорта (взрыв, респавн) стакан
	# «скорость конца прошлого кадра» протух — кап мог бы «вернуть» до
	# 5 м/с только что обнулённой скорости.
	_post_vel = Vector3.ZERO
	_puppet_touch = false


func _player_control(delta: float, on_ground: bool) -> void:
	var throttle := Input.get_axis("brake", "accelerate")
	var steer := Input.get_axis("steer_right", "steer_left")
	var handbraking := Input.is_action_pressed("handbrake")
	var jumping := Input.is_action_just_pressed("jump")
	_drive(delta, on_ground, throttle, steer, handbraking, jumping)
	# Ехать своей машиной клиент считает сам (отклик руля без пинга), а
	# вот СТРЕЛЯТЬ — нет: оружие тратит сервер. Локальный выстрел породил
	# бы вторую ракету и списал бокс дважды. Клиент шлёт нажатие в
	# Main._client_tick.
	if net_role != NetRole.LOCAL:
		return
	if Input.is_action_just_pressed("fire") \
			or Input.is_action_just_pressed("drop"):
		use_weapon()


## Пришёл снимок этой машины: с сервера — для марионеток на клиенте,
## с клиента-владельца — для машины живого игрока на сервере.
func net_apply_snapshot(pos: Vector3, rot: Quaternion, vel: Vector3) -> void:
	# ДУБЛИКАТ не обнуляет возраст. Сервер ретранслирует последнее
	# присланное владельцем состояние своим тиком: если пакет владельца
	# не успел прийти между тиками, уходит копия прошлого. Сброс возраста
	# на копии останавливал экстраполяцию — марионетка шла «стоп-скачок»
	# (те самые рывки соперника). Пусть возраст растёт — экстраполяция
	# продолжит вести машину по скорости до свежего состояния.
	if _snap_seen and pos.is_equal_approx(_snap_pos) \
			and vel.is_equal_approx(_snap_vel):
		return
	_snap_pos = pos
	_snap_rot = rot
	_snap_vel = vel
	_snap_age = 0.0
	if not _snap_seen:
		_snap_seen = true
		global_position = pos
		global_transform.basis = Basis(rot)


## Марионетка: свою физику не считаем вовсе, тянемся к снимку. Снимки идут
## реже кадров, поэтому цель ЭКСТРАПОЛИРУЕТСЯ по присланной скорости —
## между пакетами машина продолжает ехать, а не ждёт следующего.
##
## ИСТОРИЯ ВОПРОСА (чтобы не переделывать это в третий раз). Жалобу на
## «дёрганое движение» я сперва списал на эту функцию и переписал её дважды:
## сначала на «едем от текущего места к последнему присланному», потом на
## учебный буфер снимков с отставанием. Обе версии оказались ХУЖЕ исходной.
## Замер «насколько пройденный за кадр путь сходится с присланной скоростью»
## (см. tools/test_net.gd): исходная экстраполяция 1.7%, «от текущего места»
## ~50%, буфер с отставанием 20.8%. Эталон одиночной игры — 0.3%.
## Так что здесь всё в порядке, и трогать это не надо. Дёргало из-за подтяжки
## СВОЕЙ машины к серверному состоянию — она удалена вовсе: своя машина
## теперь клиент-авторитетна (см. NetRole.OWNED).
##
## Большая невязка (респавн, телепорт после уничтожения) — не догоняем, а
## переставляем.
# Насколько далеко вперёд разрешено угадывать положение марионетки, пока
# нет свежего снимка. Подобрано ЗАМЕРАМИ НА ЖИВОМ СЕРВЕРЕ, двумя клиентами
# (метрика — «шаг против присланной скорости», см. tools/test_net.gd):
#   0.05 с → 42%   мало: в паузе между пакетами машина замирает и догоняет
#   0.12 с → 25%   лучше всего
#   0.22 с → 39%   много: уезжает вперёд и потом подолгу стоит
# Локалхост даёт 2-5% при любом значении — там пакеты идут ровно, и подобрать
# по нему было НЕЛЬЗЯ. Учебный буфер снимков с отставанием пробовал тоже:
# 60% на интернете и 21% на локалхосте, то есть хуже везде.
const MAX_EXTRAP := 0.12
func _follow_snapshot(delta: float) -> void:
	if not _snap_seen:
		return
	# Возраст снимка ОГРАНИЧЕН. Без ограничения запоздавший пакет уводил
	# цель далеко вперёд, а следующий снимок возвращал её назад — машину
	# дёргало. На одном клиенте по локалхосту этого не видно (пакеты идут
	# ровно), а на двух уже ловится: замер показывал 4 рывка назад за 419
	# кадров у второго игрока.
	_snap_age = minf(_snap_age + delta, MAX_EXTRAP)
	var target := _snap_pos + _snap_vel * _snap_age
	# Коэффициент подтяжки независим от частоты кадров: 0.35 на кадре
	# 60 Гц (движение теперь в _process, а там fps плавает и бывает 144+).
	var k := 1.0 - pow(0.65, delta * 60.0)
	if global_position.distance_to(target) > 8.0:
		global_position = target
	else:
		var next := global_position.lerp(target, k)
		# И вторая страховка: НАЗАД против собственного хода не едем вовсе.
		# Лучше замереть на кадр (этого глаз не ловит), чем откатиться —
		# откат читается как рывок.
		var step := next - global_position
		if _snap_vel.length() > 1.0 and step.dot(_snap_vel) < 0.0:
			next = global_position
		global_position = next
	var cur := global_transform.basis.get_rotation_quaternion()
	global_transform.basis = Basis(cur.slerp(_snap_rot, k))
	linear_velocity = _snap_vel


## Перевод машины в марионетку: своя физика выключается, позиция тянется
## к присланным снимкам. На клиенте это все чужие машины, на сервере —
## машины живых игроков (клиент-авторитетность).
## ВАЖНО: подтяжки СВОЕЙ машины клиента к серверному состоянию больше нет
## (был net_correct): серверная копия отстаёт на пинг, и любая подтяжка к
## ней — от lerp до шагов по 8 см — на реальном канале ощущалась рывками,
## а невязка больше 5 м давала телепорт. Теперь свою машину клиент считает
## сам и САМ шлёт её состояние серверу (Main._client_tick → _rx_pstate).
func net_make_puppet() -> void:
	net_role = NetRole.PUPPET
	is_player = false
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	for p in _smoke:
		p.emitting = false
	if _boost_flame:
		_boost_flame.emitting = false


## Обратно под бота (сервер: игрок вышел). Снимки владельца больше не
## придут — без сброса _snap_seen машина зависла бы марионеткой навсегда.
func net_make_local() -> void:
	net_role = NetRole.LOCAL
	is_player = false
	freeze = false
	_snap_seen = false
	net_fire = false


## Сервер: эффект оружия по машине живого игрока пересылается её клиенту —
## машина клиент-авторитетна, и физику эффекта (толчок, закрутку, телепорт)
## обязан применить владелец, иначе он его просто не почувствует.
## Локальную часть (таймеры «призрака»/заморозки для снимков) сервер всё
## равно ведёт у себя — поэтому вызывающий код после пересылки НЕ выходит.
func _forward_fx(kind: int, args: Array = []) -> void:
	if net_role == NetRole.PUPPET and race != null \
			and race.has_method("net_forward_fx"):
		race.net_forward_fx(self, kind, args)


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
	if _ai_fire_cd <= 0.0 and weapon >= 0:
		_ai_fire_cd = randf_range(1.6, 3.2)
		match weapon:
			Weapons.ROCKET, Weapons.LASER, Weapons.FREEZE:
				if _enemy_ahead():
					use_weapon()
			Weapons.MINE, Weapons.OIL:
				if _enemy_behind() and randf() < 0.6:
					use_weapon()
			Weapons.MAGNET:
				if _enemy_near(12.0):
					use_weapon()
			Weapons.AIRSTRIKE:
				use_weapon()
			Weapons.BOOST:
				if throttle > 0.5:
					use_weapon()


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
	# Эффекты оружия: заморозка режет предел скорости и тягу, буст — растит.
	var fx_mult := 1.0
	if _freeze_time > 0.0:
		fx_mult = 0.55
	elif _boost_time > 0.0:
		fx_mult = 1.45
	# Рыхлый песок за полотном (песчаная трасса): тяга и потолок скорости
	# заметно ниже — срезать по песку невыгодно, ограждений там нет.
	if _on_sand:
		fx_mult *= 0.55
	var eff_max := max_speed * ai_rubber * fx_mult

	if on_ground:
		# Тяга/тормоз. На масле колёса буксуют: и разогнаться, и оттормозиться
		# почти нельзя — машину просто несёт юзом, пока занос не кончится.
		if absf(speed) < eff_max or signf(throttle) != signf(speed):
			var power := engine_power if throttle > 0.0 else brake_power
			if _slip_time > 0.0:
				power *= slip_thrust
			apply_central_force(
					forward * throttle * power * ai_rubber * fx_mult * mass * 0.1)

		# Руль: почти не слабеет на скорости (RnRR-манёвренность).
		# После тарана (_bump_spin_time) руль слабый: жёсткий lerp съел бы
		# закрутку от удара за пару кадров, а машину должно довернуть.
		var yaw_rate := 2.5 if _bump_spin_time > 0.0 else 10.0
		if absf(speed) > 0.5:
			var speed_t: float = clampf(absf(speed) / max_speed, 0.0, 1.0)
			var turn_rate: float = lerpf(steer_speed, steer_speed_min, speed_t)
			# Скорость поворота коррелирует со скоростью машины: почти
			# стоя не развернёшься, полная сила руля — от steer_full_speed.
			# НО: если нос сильно поперёк трассы (после перпендикулярного
			# удара в отбойник машина почти стоит) — руль работает и на
			# малой скорости, иначе не развернуться, не разогнавшись в стену.
			var speed_factor := clampf(absf(speed) / steer_full_speed, 0.0, 1.0)
			if _track_ang_abs > deg_to_rad(35.0):
				speed_factor = maxf(speed_factor, 0.6)
			turn_rate *= speed_factor
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
		_side_speed = side_speed  # для дыма из-под колёс на заносе
		var current_grip := grip_handbrake if handbraking else grip
		# Масляное пятно: сцепления почти нет — машину несёт юзом.
		if _slip_time > 0.0:
			current_grip = slip_grip
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
		_side_speed = 0.0  # в полёте колёса не скользят — дыма нет
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
	# На трассе без ограждений (песчаная) вести не вдоль чего: съезд с
	# полотна легален, его наказывает сам песок (см. _on_sand).
	if track == null or not track.has_walls:
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
	# Полотно переменной ширины — грань ограждения берём в ТЕКУЩЕЙ точке
	# трассы, иначе в узких местах (шпилька) ведение включалось бы уже
	# внутри стены, а на широких — в нескольких метрах от неё.
	var wall_face := track.half_width_at_offset(off) \
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
		# Вся горизонтальная скорость — вдоль стены, но со штрафом:
		# ограждение направляет и ГАСИТ удар — 40% скорости сближения
		# при перехвате + слабый скрежет, пока есть контакт. Скользящий
		# удар почти не теряет (v_out мал), перпендикулярный — ощутимо.
		# Перепрыгнуть стену по-прежнему можно: выше кромки ведение
		# отключается (см. проверку высоты выше).
		var s := maxf(h.length(), _recent_hspeed)
		s -= 0.4 * maxf(v_out, 0.0)
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
	# Кап скорости ОТ стены теперь ВСЕГДА в пристенке: без руля прочь —
	# 1.2 м/с (скорости от стены взяться неоткуда, фантомные отбросы
	# решателя режем), с рулём прочь — 3.0 м/с (отойти от стены можно,
	# «выстрелить» — нет: раньше выпуск под 22° на полной памяти скорости
	# и отбросы депенетрации при нажатом руле не капались вовсе — машина
	# ОТЛЕТАЛА от ограждения). Подскок режем в том же окне.
	if touching or _wall_align_time > 0.0:
		var out_cap := 3.0 if steering_away else 1.2
		var h_now := linear_velocity
		h_now.y = 0.0
		var out_now := h_now.dot(n)
		if out_now < -out_cap:
			linear_velocity -= n * (out_now + out_cap)
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
	# Помощь развороту после перпендикулярного удара в отбойник: машина
	# почти стоит носом поперёк трассы, руль на нулевой скорости бессилен
	# (turn_rate ~ скорости) — раньше приходилось биться в стену ещё
	# несколько раз. Пока нос сильно поперёк (> 40°) и скорость мала,
	# корпус сам плавно доворачивается вдоль трассы.
	var h := linear_velocity
	h.y = 0.0
	if _grounded_wheels >= 2 and absf(ang) > deg_to_rad(35.0) \
			and h.length() < 8.0:
		var step := minf(2.4 * delta, absf(ang) - deg_to_rad(35.0))
		rotate(Vector3.UP, -signf(ang) * step)
		ang -= signf(ang) * step
	_track_ang_abs = absf(ang)
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

func is_ghost() -> bool:
	return _ghost_time > 0.0


## Сообщить менеджеру гонки «по этой машине применили оружие» — для ленты
## событий в HUD («Player 1 [иконка] → Player 2»). Зовут снаряды, мины,
## пятна и разовые эффекты (магнит, лазер, авиаудар). Самопопадания и
## машины вне гонки менеджер отсеет сам (report_weapon_hit).
func notify_hit_by(attacker: Car, kind: int) -> void:
	if race != null and race.has_method("report_weapon_hit"):
		race.report_weapon_hit(attacker, self, kind)


## Применить текущее оружие (у машины в руках всегда не больше одного;
## новое берётся из боксов на трассе). Оружие тратится при использовании.
func use_weapon() -> void:
	if not alive or weapon < 0:
		return
	var kind := weapon
	weapon = -1
	# По сети выстрел считает сервер, но клиенты должны его УВИДЕТЬ:
	# просим менеджера гонки разослать событие (вне сети — пустышка).
	if race != null and race.has_method("net_broadcast_weapon"):
		race.net_broadcast_weapon(self, kind)
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1e-6 else Vector3.FORWARD
	match kind:
		Weapons.MINE:
			var m := Mine.new()
			m.dropper = self
			get_parent().add_child(m)
			m.global_position = global_position \
					+ global_transform.basis.z * 2.4 + Vector3.UP * 0.1
		Weapons.ROCKET, Weapons.FREEZE:
			var p := Projectile.new()
			p.shooter = self
			p.direction = fwd
			p.freeze = kind == Weapons.FREEZE
			get_parent().add_child(p)
			p.global_position = global_position + fwd * 2.3 + Vector3.UP * 0.55
			FxKit.muzzle_flash(get_parent(), p.global_position,
					Color(0.6, 0.85, 1.0) if p.freeze else Color(1.0, 0.8, 0.35))
		Weapons.OIL:
			var oil := OilSlick.new()
			oil.dropper = self
			get_parent().add_child(oil)
			oil.global_position = global_position \
					+ global_transform.basis.z * 3.0 + Vector3.UP * 0.12
		Weapons.MAGNET:
			_use_magnet()
		Weapons.LASER:
			_use_laser(fwd)
		Weapons.AIRSTRIKE:
			_use_airstrike()
		Weapons.BOOST:
			apply_boost()
			FlashFx.spawn(get_parent(),
					global_position + Vector3.UP * 0.5, 1.2,
					Color(0.3, 0.9, 1.0))
			FxKit.ring(get_parent(), global_position, 2.2,
					Color(0.3, 0.9, 1.0))


## Магнит: все машины разово получают сильный импульс К этой машине —
## соперников «откидывает назад», к использовавшему. Рывок ЖЕСТОЧАЙШИЙ:
## вблизи он почти в max_speed, машину сдёргивает с траектории и
## разворачивает; далёких тянет слабее (спад с расстоянием, но не до
## нуля — магнит достаёт всю трассу). Подброса почти нет: магнит волочит
## по земле, а не подкидывает. Тем, кто ВПЕРЕДИ по гонке, магнит вдобавок
## режет скорость вдвое (осаживает); задних — только притягивает.
func _use_magnet() -> void:
	const MAGNET_PULL := 32.0     # импульс вблизи, м/с (почти max_speed)
	const MAGNET_FAR := 18.0      # к чему сходит на дальней дистанции
	const MAGNET_RANGE := 45.0    # дистанция, на которой спад завершён
	const MAGNET_SPIN := 3.6      # закрутка от рывка, рад/с
	const MAGNET_ICON_TIME := 1.5 # сколько над жертвой висит значок магнита
	FlashFx.spawn(get_parent(), global_position + Vector3.UP * 0.5, 3.2,
			Color(0.8, 0.3, 1.0))
	FxKit.ring(get_parent(), global_position, 5.0, Color(0.8, 0.3, 1.0))
	FxKit.lightning_burst(get_parent(), global_position + Vector3.UP * 0.8,
			Color(0.85, 0.4, 1.0), 7, 1.4)
	for node in get_tree().get_nodes_in_group("cars"):
		var other := node as Car
		if other == self or not other.alive or other.is_ghost():
			continue
		var dir := global_position - other.global_position
		dir.y = 0.0
		var dist := dir.length()
		if dist < 0.1:
			continue
		var t: float = clampf(dist / MAGNET_RANGE, 0.0, 1.0)
		var power: float = lerpf(MAGNET_PULL, MAGNET_FAR, t)
		var spin := MAGNET_SPIN * (1.0 - t) * (1.0 if randf() < 0.5 else -1.0)
		# Впередиедущих осаживаем ДО рывка: срежь скорость после — порезался
		# бы и сам импульс притяжения.
		if _rival_is_ahead(other):
			other.apply_speed_cut(0.5)
		other.push_from_blast(dir / dist, power, spin, 0.12)
		other.show_effect_icon(Weapons.MAGNET, MAGNET_ICON_TIME)
		other.notify_hit_by(self, Weapons.MAGNET)
		# Разряд над жертвой — видно, кого дёрнуло.
		FxKit.lightning_burst(get_parent(),
				other.global_position + Vector3.UP * 0.9,
				Color(0.85, 0.4, 1.0), 4, 0.9)


## «Соперник впереди?» для магнита — по прогрессу ГОНКИ (накопленный путь
## вдоль оси, как считает места Main), а не по геометрии: на петлях трассы
## машина «перед носом» может по заезду быть позади. Вне заезда (стенды
## без Main) — фолбэк по геометрии, перед носом = впереди.
func _rival_is_ahead(other: Car) -> bool:
	if race != null and race.has_method("progress_of"):
		return race.progress_of(other) > race.progress_of(self)
	var fwd := -global_transform.basis.z
	return fwd.dot(other.global_position - global_position) > 0.0


## Лазер: один луч вперёд, уничтожает ВСЕ машины на пути.
func _use_laser(fwd: Vector3) -> void:
	const RANGE := 70.0
	const HALF_WIDTH := 1.6
	var from := global_position + Vector3.UP * 0.5
	LaserFx.spawn(get_parent(), from, fwd, RANGE)
	for node in get_tree().get_nodes_in_group("cars"):
		var other := node as Car
		if other == self or not other.alive or other.is_ghost():
			continue
		var to := other.global_position - global_position
		to.y = 0.0
		var along := to.dot(fwd)
		if along < 0.0 or along > RANGE:
			continue
		var side := (to - fwd * along).length()
		if side <= HALF_WIDTH:
			other.notify_hit_by(self, Weapons.LASER)
			# Разряд на жертве — луч «прошивает» её электричеством.
			FxKit.lightning_burst(get_parent(),
					other.global_position + Vector3.UP * 0.7,
					Color(1.0, 0.5, 0.4), 6, 1.2)
			other.destroy()


## Авиаудар: цель — ЛИДЕР гонки (спрашиваем у менеджера Main; без него —
## тесты/стенды — бьём по себе).
func _use_airstrike() -> void:
	var target: Car = self
	if race != null and race.has_method("leader_car"):
		target = race.leader_car()
	var strike := Airstrike.new()
	strike.track = track
	strike.target = target
	strike.attacker = self
	get_parent().add_child(strike)


## Уничтожение (ракета/лазер/авиаудар): вспышка, машина тут же появляется
## на трассе с нулевой скоростью и на ghost_time становится «призраком» —
## мигает, не взаимодействует с другими машинами, но может ехать и
## набирать скорость. Потом всё как раньше.
func destroy() -> void:
	if not alive or is_ghost():
		return
	_forward_fx(NetFx.DESTROY)
	FlashFx.spawn(get_parent(), global_position, 2.4, Color(1.0, 0.45, 0.1))
	FxKit.ring(get_parent(), global_position, 3.4, Color(1.0, 0.55, 0.15))
	FxKit.smoke_burst(get_parent(), global_position + Vector3.UP * 0.4, 12, 1.2)
	SparksFx.spawn(get_parent(), global_position + Vector3.UP * 0.5, 10.0)
	FxKit.fire_burst(get_parent(), global_position + Vector3.UP * 0.3)
	FxKit.scorch(get_parent(), global_position)
	if track:
		global_transform = track.respawn_transform(global_position)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reset_speed_memory()
	_freeze_time = 0.0
	_slip_time = 0.0
	_boost_time = 0.0
	_ghost_time = ghost_time
	# Призрак не сталкивается с машинами (слой 4 убран с обеих сторон);
	# дорога (1) и стены (2) остаются.
	collision_layer = 0
	collision_mask = 0b011


## Значок эффекта над машиной: что показывать и как он живёт.
## Два источника: РАЗОВЫЕ эффекты (магнит — его applier зовёт
## show_effect_icon) и ДЛЯЩИЕСЯ (ускорение — читаем прямо _boost_time,
## а не заводим свой таймер: destroy() обнуляет буст, и отдельный таймер
## оставил бы значок висеть над машиной, которую уже отбросило).
## Магнит важнее буста: «по тебе только что применили» — новость.
func _tick_status_icon(delta: float) -> void:
	if _status_icon == null:
		return
	_status_time = maxf(0.0, _status_time - delta)
	var kind := -1
	var left := 0.0
	if alive:
		if _status_time > 0.0:
			kind = _status_kind
			left = _status_time
		elif _boost_time > 0.0 and not _boost_from_pad:
			kind = Weapons.BOOST
			left = _boost_time
	if kind < 0:
		_status_icon.visible = false
		_status_shown = -2
		return
	if kind != _status_shown:
		_status_shown = kind
		_status_age = 0.0
		var tex := Weapons.icon(kind)
		_status_icon.texture = tex
		if tex != null:
			_status_icon.pixel_size = STATUS_ICON_SIZE / float(tex.get_width())
	_status_age += delta
	_status_icon.visible = true
	# Где висит стрелка-указатель (Main, высота 2.4 + конус 0.6), значок
	# поднимаем над ней. Смотрим на ФАКТ маркера, а не на is_player: по
	# сети маркеры есть у обоих живых игроков, а is_player там только у
	# своей машины.
	var height := STATUS_ICON_PLAYER_Y if has_marker else STATUS_ICON_Y
	_status_icon.global_position = global_position 			+ Vector3.UP * (height + 0.09 * sin(_status_age * 4.5))
	# «Выпрыгивание» при появлении и затухание в последние 0.3 с.
	var pop: float = clampf(_status_age / 0.16, 0.0, 1.0)
	_status_icon.scale = Vector3.ONE * (1.0 + 0.6 * (1.0 - pop))
	_status_icon.modulate.a = clampf(left / 0.3, 0.0, 1.0)


## Показать над машиной значок РАЗОВОГО эффекта (магнит). Длящиеся
## эффекты значок берёт сам, см. _tick_status_icon.
func show_effect_icon(kind: int, duration: float) -> void:
	if not alive:
		return
	_status_kind = kind
	_status_time = maxf(_status_time, duration)


## Ускорение (бонус BOOST). Вынесено из use_weapon ради сети: на сервере
## машина живого игрока — марионетка, тягу считает клиент-владелец, и без
## пересылки буст не действовал бы вовсе.
## from_pad: буст с плиты-ускорителя — плиты срабатывают каждые несколько
## секунд, поэтому без таблички над машиной и с узким языком огня
## (полная помпа со значком — только у турбины-бонуса).
func apply_boost(from_pad := false) -> void:
	if not alive:
		return
	_forward_fx(NetFx.BOOST, [from_pad])
	_boost_from_pad = from_pad
	_boost_time = boost_duration


## Разовый срез скорости (магнит осаживает впередиедущих). По сети машина
## живого игрока клиент-авторитетна — эффект пересылается владельцу
## (NetFx.SLOW), иначе он его не почувствует. Память скорости
## (_recent_hspeed) срезается вслед — иначе защита приземления или ведение
## у стены вернули бы срезанное обратно.
func apply_speed_cut(factor: float) -> void:
	if not alive:
		return
	_forward_fx(NetFx.SLOW, [factor])
	linear_velocity.x *= factor
	linear_velocity.z *= factor
	_recent_hspeed *= factor


## Заморозка: машина «синеет» и едет медленнее. Дебаф ЗАРАЗЕН — при
## контакте машин передаётся остаток времени (см. _bounce_off_cars).
func apply_freeze(duration: float) -> void:
	if not alive:
		return
	_forward_fx(NetFx.FREEZE, [duration])
	_freeze_time = maxf(_freeze_time, duration)
	FxKit.snow_burst(get_parent(), global_position + Vector3.UP * 0.6)


## Масляное пятно: занос — закрутка + почти нулевое сцепление (slip_grip)
## + буксующие колёса (slip_thrust) на slip_duration. Окно
## _bump_spin_time не даёт рулю мгновенно съесть закрутку, окно
## _ext_push_time — капу боковых пинков её срезать. Повторный наезд на
## пятно во время заноса ничего не продлевает — занос и так тяжёлый.
## Сторона закрутки случайная только НА СВОБОДНОМ ПОЛОТНЕ: у ограждения
## машину разворачивает в разрешённую сторону — носом ОТ стены (см.
## _spin_away_from_wall). Иначе занос втыкал нос в отбойник, где
## _clamp_heading и ведение у стены его тут же и съедали: эффектного
## вращения не выходило, выходил тычок в стену.
func apply_oil_slip() -> void:
	if not alive or _slip_time > 0.0:
		return
	_forward_fx(NetFx.OIL)
	_slip_time = slip_duration
	_bump_spin_time = slip_duration
	_ext_push_time = slip_duration
	var side := _spin_away_from_wall()
	if side == 0.0:
		side = 1.0 if randf() < 0.5 else -1.0
	var spin := randf_range(3.2, 4.4) * side
	angular_velocity.y = clampf(angular_velocity.y + spin, -4.5, 4.5)


## Разрешённая сторона закрутки у ограждения: 0.0 — стена далеко, крути
## куда угодно; иначе знак рысканья, который уводит нос ОТ стены.
## Стена «близко» — если кузов со своим вылетом в её сторону уже в
## SPIN_WALL_MARGIN от грани отбойника (полотно переменной ширины, грань
## берём в ТЕКУЩЕЙ точке трассы — как в _wall_slide).
func _spin_away_from_wall() -> float:
	const SPIN_WALL_MARGIN := 3.0
	if track == null or not track.has_walls:
		return 0.0
	var curve: Curve3D = track._curve
	var off := curve.get_closest_offset(global_position)
	var axis_pos := curve.sample_baked(off)
	# Наружу — от оси трассы к ближнему борту (работает для обоих).
	var n := global_position - axis_pos
	n.y = 0.0
	var dist := n.length()
	if dist < 0.01:
		return 0.0
	n /= dist
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		return 0.0
	fwd = fwd.normalized()
	var wall_face: float = track.half_width_at_offset(off) 			- TrackBuilder.WALL_THICKNESS * 0.5
	if dist + SPIN_WALL_MARGIN < wall_face:
		return 0.0
	# Знак рысканья «в стену» — тот же, что у _wall_slide (into_sign);
	# разрешённая сторона противоположна.
	return -signf(fwd.signed_angle_to(n, Vector3.UP))


## Разовый толчок от взрыва мины/магнита: горизонтальный импульс, подброс
## и закрутка. На окно толчка снимаются ВСЕ страховки, которые иначе
## съели бы удар за пару кадров:
##  - кап боковых пинков (_ext_push_time) — толчок честный, не «фантом»;
##  - клапан отскока от земли (_jump_time) — иначе на ровном полотне
##    вертикальная скорость режется до 0.6 м/с и подброса не видно;
##  - жёсткий lerp рысканья (_bump_spin_time) — иначе руль гасит
##    закрутку в тот же кадр, и разворота от взрыва не будет.
func push_from_blast(dir: Vector3, power: float, spin := 0.0,
		lift := 0.35) -> void:
	if not alive:
		return
	_forward_fx(NetFx.BLAST, [dir, power, spin, lift])
	_ext_push_time = maxf(_ext_push_time, 0.7)
	_blast_time = maxf(_blast_time, 0.4)  # кап марионетки толчок не съедает
	apply_central_impulse((dir + Vector3.UP * lift).normalized()
			* power * mass)
	if lift > 0.05:
		_jump_time = maxf(_jump_time, 0.4)
	if absf(spin) > 0.01:
		_bump_spin_time = maxf(_bump_spin_time, 0.8)
		angular_velocity.y = clampf(angular_velocity.y + spin, -4.0, 4.0)


func _enemy_near(radius: float) -> bool:
	for node in get_tree().get_nodes_in_group("cars"):
		var other := node as Car
		if other == self or not other.alive:
			continue
		if (other.global_position - global_position).length() < radius:
			return true
	return false


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
		# След шины: в сильном заносе задние колёса чертят ленту по точке
		# касания с дорогой (луч уже есть). Кончился занос/контакт — лента
		# закрывается и дальше тает сама.
		if not pivot.get_meta("is_front"):
			if _skid_active and not hit.is_empty():
				var trail: SkidTrail = _skid_trails.get(pivot)
				if trail == null:
					trail = SkidTrail.start(get_parent())
					_skid_trails[pivot] = trail
				if not trail.add_point(hit["position"], hit["normal"]):
					# Лента набрала лимит или точка ускакала (телепорт):
					# закрываем, новую начнёт следующий кадр.
					trail.finish()
					_skid_trails.erase(pivot)
			else:
				_end_skid(pivot)
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
		# Подъём ограничен долей РАДИУСА колеса: при жёсткой посадке pen с
		# упреждением доходил до десятков сантиметров, пивот взлетал и колесо
		# вылезало НАД кузовом («колёса поверх машины»). Выше 60% радиуса
		# колесо гарантированно торчит из арки — дальше пусть лучше на
		# кадр-два нырнёт в асфальт (обычное утопание ≤ 11 см и так меньше).
		var target := clampf(pen, 0.0, radius * 0.6)
		var lift: float = pivot.get_meta("lift")
		lift = target if target > lift else lerpf(lift, target, 12.0 * delta)
		pivot.set_meta("lift", lift)
		if lift > 0.001:
			pivot.global_position = hub + Vector3.UP * lift


## Закрыть текущую ленту следа колеса (если была): дальше она лежит,
## тает и удаляется сама.
func _end_skid(pivot: Node3D) -> void:
	var trail: SkidTrail = _skid_trails.get(pivot)
	if trail != null:
		trail.finish()
		_skid_trails.erase(pivot)


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
