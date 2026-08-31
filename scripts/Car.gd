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
var soccer_brain: Node = null   # футбол (Soccer.gd): ведёт ботов вместо трассы
var ai_rubber := 1.0            # «резинка»: множитель тяги/скорости ИИ
# «Класс» ИИ: постоянный множитель темпа бота (< 1 — едет слабее игрока).
# Вкладывается в ai_rubber менеджером гонки (Main), сам по себе не читается.
var ai_skill := 1.0

# Эффекты оружия (таймеры, с).
var _ghost_time := 0.0          # после уничтожения: не трогает машины, мигает
# Сколько «призрак» уже длится. Отдельно от _ghost_time, потому что фазу
# мигания по остатку считать НЕЛЬЗЯ: марионетке остаток подливают по 0.3 c
# каждым снимком (Main._rx_state), и «прошло = ghost_time − остаток» давало
# вечное 1.7 из 2.0 — последнюю фазу, то есть «всегда видна». Из-за этого
# уничтоженный соперник не мигал вовсе и выглядел как ни в чём не бывало
# едущий (жалоба 31.08).
var _ghost_age := 0.0
var _freeze_time := 0.0         # замедление от ледышки (дебаф заразен)
var _boost_time := 0.0          # ускорение
var _slip_time := 0.0           # занос от масляного пятна
var _scramble_time := 0.0       # глушилка: лево и право поменяны местами
# «Усталость» от магнита: каждый рывок в окне _magnet_worn_time режет силу
# следующего (жалоба 31.08: «несколько машин применили — выкидывает с
# трассы с огромной силой»). Окно истекло — счёт с нуля.
var _magnet_worn := 0.0
var _magnet_worn_time := 0.0
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
enum NetFx { DESTROY, BLAST, FREEZE, OIL, BOOST, SLOW, SHOVE, SCRAMBLE }
var has_marker := false         # над машиной висит стрелка-указатель
## Отметка машины на оси трассы, м. Считается с оглядкой на предыдущую
## (TrackBuilder.closest_offset_near): улетевшая за ограждение машина
## оказывается ближе к ЧУЖОМУ витку кольца, и «ближайшая точка вообще»
## отправляла её респавн, прогресс, прицел ИИ и кламп курса на другой конец
## трассы. Обновляется раз за кадр физики (sync_track_offset), после
## телепортов сбрасывается (reset_track_offset).
var track_offset := 0.0
# В каком кадре физики отметка уже посчитана; −1 — ещё ни разу.
var _offset_frame := -1
# Последний снимок с сервера и его возраст. Марионетка тянется к нему,
# ЭКСТРАПОЛИРУЯ по присланной скорости, — см. _follow_snapshot.
var _snap_pos := Vector3.ZERO
var _snap_rot := Quaternion.IDENTITY
var _snap_vel := Vector3.ZERO
var _snap_age := 0.0
var _snap_seen := false
var _snap_stamp := -1.0   # тик ЧАСОВ АВТОРА состояния (сервер/владелец)
# Мои недавние ЛОКАЛЬНЫЕ рикошеты о марионеток: instance id -> ticks_msec.
# Приехавший следом толчок-событие (_rx_fx SHOVE) о том же контакте
# отбрасывается — иначе при тёрке бок-о-бок машину било бы дважды (свой
# рикошет + событие соперника).
var _touch_mute := {}
# История позиций на СЕРВЕРЕ (~0.7 c, кадр физики): по ней лазер игрока
# отматывает цели назад — стрелявший целится в картину, отстающую на
# буфер воспроизведения (~0.35 c) и полёт пакета, и без отмотки «попал на
# экране — сервер промахнулся». Заполняется только на сервере.
var _pos_hist: Array[Vector3] = []
## Сервер: на сколько ОТСТАЁТ картинка у владельца этой машины (его
## Car.net_buf_delay + полёт пакета). Присылается в состоянии владельца
## (протокол 13). По этой величине сервер отматывает цели, когда владелец
## стреляет: он целился в то, что видел. Раньше стояла догадка 0.4 c для
## лазера, а снаряды не отматывались вовсе.
var net_client_lag := 0.0
# Буфер снимков КЛИЕНТСКОЙ марионетки (см. _follow_buffered): каждый снимок
# получает время на СИНТЕТИЧЕСКОЙ шкале (+1/60 к прошлому) — пачка,
# слипшаяся в канале, раскладывается обратно в ритм отправки сервера.
var _buf: Array[Dictionary] = []
var _buf_t := 0.0        # время последнего снимка на этой шкале
var _play_t := -1.0      # часы воспроизведения (<0 — ещё не начаты)
var _play_vel := Vector3.ZERO  # скорость ВОСПРОИЗВОДИМОГО куска записи
# Темп воспроизведения: 1.0 — как записано; <1 — время РАСТЯНУТО (запас
# буфера кончается, растягиваем вместо замирания), >1 — догоняем пачку.
var _play_rate := 1.0
# Визуальная интерполяция марионетки: тело шагает с частотой ФИЗИКИ (60 Гц),
# и на реальном рендере (fps плавает, вертикалка, просадки) марионетки
# видимо дёргались — даже при идеальном потоке снимков. Модель (CarModel)
# отвязывается от тела (top_level) и каждый кадр рендера ставится МЕЖДУ
# двумя последними положениями тела по Engine.get_physics_interpolation_
# fraction() — классическая интерполяция фиксированного шага. Физика,
# оружие и снимки по-прежнему видят тело; глаз видит модель.
var _vis_prev := Transform3D.IDENTITY   # тело на предыдущем кадре физики
var _vis_cur := Transform3D.IDENTITY    # тело на текущем кадре физики
var _vis_base := Transform3D.IDENTITY   # локальная центровка модели (build)
var _vis_on := false                    # пара _vis_prev/_vis_cur валидна
var _status_icon: Sprite3D = null  # значок действующего эффекта над крышей
var _status_kind := -1          # разовый значок (магнит): какой показываем
var _status_time := 0.0         # и сколько ему осталось
var _status_shown := -2         # что сейчас лежит в текстуре (-2 = ничего)
var _status_age := 0.0          # возраст показа: «выпрыгивание» и покачивание
var _ice_shell: MeshInstance3D  # визуал заморозки (голубая скорлупа)
# Фары ночного города. Держатель top_level — как модель, стрелка и значок:
# ставится по ВИДИМОМУ положению машины (см. _process). Списки — по паре
# [левая, правая], нужны для посадки на нос конкретной модели.
var _headlights: Node3D = null
var _beams: Array[SpotLight3D] = []
var _lamps: Array[MeshInstance3D] = []

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
##
## Всё это живёт в держателе Headlights с top_level. Детьми ТЕЛА фары
## держать нельзя: тело шагает с частотой физики (60 Гц), а видимая
## машина каждый кадр рендера ставится МЕЖДУ двумя его положениями
## (см. _process), — фары отставали от собственного кузова на шаг тела
## (на 25 м/с это ~0.4 м) и болтались на нём. Держатель каждый кадр
## встаёт ровно туда же, куда модель, — свет прибит к машине намертво.
## (Та же история, что со стрелкой и значком эффекта 26.08.)
##
## Стартовые смещения — грубые: настоящее место фарам ищет
## fit_headlights по носу конкретной модели (её ставят уже после _ready).
func _build_headlights() -> void:
	_headlights = Node3D.new()
	_headlights.name = "Headlights"
	_headlights.top_level = true
	add_child(_headlights)
	_headlights.global_transform = global_transform
	for sx: float in [-0.45, 0.45]:
		var beam := SpotLight3D.new()
		beam.name = "HeadlightBeam"
		beam.position = Vector3(sx, 0.1, -1.66)
		beam.rotation_degrees = Vector3(-10, 0, 0)
		beam.spot_range = 22.0
		beam.spot_angle = 30.0
		beam.light_energy = 6.0
		beam.light_color = Color(1.0, 0.93, 0.75)
		beam.shadow_enabled = true
		_headlights.add_child(beam)
		_beams.append(beam)

		var lamp := MeshInstance3D.new()
		lamp.name = "HeadlightLamp"
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
		lamp.position = Vector3(sx, 0.1, -1.56)
		_headlights.add_child(lamp)
		_lamps.append(lamp)


## Сажает фары на НОС конкретной модели. Машин в паках 41, и они очень
## разные: высота кузова гуляет от 0.57 м (wildthing) до 1.88 м
## (redbaron), ширина носа — от 0.28 до 0.88 м. Одно смещение на всех
## (было x=±0.55, y=0.42) подходило только средней: у низких лампы
## висели ВЫШЕ крыши, у узких — по бокам в воздухе.
##
## Вызывать после того, как модель добавлена в машину (см.
## Main._set_car_model): в _ready модели ещё нет.
func fit_headlights(model: Node3D) -> void:
	if _headlights == null or _lamps.size() < 2 or model == null:
		return
	# Положение модели В ОСЯХ МАШИНЫ считаем через глобальные: model.transform
	# годится, только пока модель не стала top_level (это делает _process), а
	# у top_level-узла в transform лежит уже МИРОВОЕ положение — соблазн взять
	# его напрямую уводит фары на другой конец трассы.
	var a := headlight_anchor(model,
			global_transform.affine_inverse() * model.global_transform)
	if a.is_empty():
		return
	var x: float = a["x"]
	var y: float = a["y"]
	var z: float = a["z"]
	var w: float = a["w"]
	for i in 2:
		var sx: float = -x if i == 0 else x
		var mesh := _lamps[i].mesh as BoxMesh
		mesh.size = Vector3(w, w * 0.5, 0.08)
		# Лампа сидит в кузове по самую «стекляшку»: наружу 2 см, остальные
		# 6 утоплены. Совсем впритык её съедает скошенный капот, а вылези
		# она целиком — читается как наклейка перед машиной. Спот — на 6 см
		# ПЕРЕД кромкой: у спотов включены тени, и капот резал бы луч.
		_lamps[i].position = Vector3(sx, y, z + 0.02)
		_beams[i].position = Vector3(sx, y, z - 0.06)


## Куда садить ПРАВУЮ фару модели: {x, y, z кромки, w — ширина лампы} в
## осях машины; пустой словарь — не получилось (пустая модель).
## model_xf — положение модели в осях машины.
##
## Меряем вершины модели БЕЗ КОЛЁС. Порядок важен: сначала высота фары по
## носу, потом ширина носа НА ЭТОЙ ВЫСОТЕ и только потом кромка возле
## самой лампы. Мерить ширину по всему носу нельзя — он почти всегда
## сужается кверху и к передку, и лампы уезжали наружу, в воздух
## (видно на wildthing/sharky).
##
## Отдельной функцией — чтобы отладочный дамп (tools/DbgCarBox.tscn)
## считал ровно то же самое, что игра.
static func headlight_anchor(model: Node3D, model_xf: Transform3D) -> Dictionary:
	var pts := model_points(model, model_xf)
	if pts.size() < 8:
		return {}
	var tip_z := pts[0].z
	for p in pts:
		tip_z = minf(tip_z, p.z)
	# Нос — передние 30 см кузова (все машины пака приведены к длине 3.2 м).
	var y_min := 1e9
	var y_max := -1e9
	for p in pts:
		if p.z > tip_z + 0.30:
			continue
		y_min = minf(y_min, p.y)
		y_max = maxf(y_max, p.y)
	if y_min > y_max:
		return {}
	# Чуть выше середины носа: у грузовика фара окажется высоко, у
	# «плоской» машины низко — доля работает на обеих.
	var lamp_y := y_min + (y_max - y_min) * 0.55
	# Полуширина носа на высоте фары.
	var half := 0.0
	for p in pts:
		if p.z > tip_z + 0.30 or absf(p.y - lamp_y) > 0.14:
			continue
		half = maxf(half, absf(p.x))
	if half < 0.12:
		return {}
	# Лампа целиком внутри этой полуширины: центр на 0.60, половина
	# ширины 0.275 — край на 0.875 полуширины, до борта ещё есть запас.
	var lamp_x := half * 0.60
	var lamp_w := minf(half * 0.55, 0.26)
	# Кромка кузова у ВНЕШНЕГО края лампы, а не в середине носа: нос
	# скруглён, к краям поверхность уходит назад, и по середине лампа
	# садилась на 5-10 см впереди борта — висела в воздухе (wildthing).
	# Если у самого края вершин не нашлось (модель низкополигональная) —
	# расширяем окно и в крайнем случае берём кончик носа.
	var front_z := tip_z
	for tol: float in [0.06, 0.12, 0.24]:
		var z := _front_z(pts, lamp_x + lamp_w * 0.5, tol,
				lamp_y, maxf(lamp_w * 0.3, 0.06))
		if z < 1e8:
			front_z = z
			break
	return {"x": lamp_x, "y": lamp_y, "z": front_z, "w": lamp_w}


## Самая передняя вершина в окошке вокруг точки (|x| = x_at, y = y_at).
## 1e9 — в окошке пусто.
static func _front_z(pts: PackedVector3Array, x_at: float, x_tol: float,
		y_at: float, y_tol: float) -> float:
	var z := 1e9
	for p in pts:
		if absf(absf(p.x) - x_at) > x_tol or absf(p.y - y_at) > y_tol:
			continue
		z = minf(z, p.z)
	return z


## Вершины модели в осях МАШИНЫ, без колёс (колесо в пивоте с мета
## wheel_radius — его целиком пропускаем, иначе «нос» ловит переднее
## колесо и лампы уезжают вниз и вбок).
static func model_points(model: Node3D, model_xf: Transform3D
		) -> PackedVector3Array:
	var out := PackedVector3Array()
	var stack: Array = [[model, model_xf]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node3D = item[0]
		var xf: Transform3D = item[1]
		if node.has_meta("wheel_radius"):
			continue
		var mi := node as MeshInstance3D
		if mi != null and mi.mesh != null:
			for v in mi.mesh.get_faces():
				out.append(xf * v)
		for child in node.get_children():
			if child is Node3D:
				stack.append([child, xf * (child as Node3D).transform])
	return out


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


## Подвинуть отметку на оси вслед за машиной. Раз за кадр физики: её просит
## и Main (ему нужен прогресс), и сама машина (ведение у стены, кламп курса,
## линия ИИ), а на «прыжке» поиск не бесплатный.
func sync_track_offset() -> void:
	if track == null:
		return
	# Ни одной отметки ещё не было (машину только что создали и поставили) —
	# сравнивать с прошлой нечего, берём её как после телепорта.
	if _offset_frame < 0:
		reset_track_offset()
		return
	var frame := Engine.get_physics_frames()
	if frame == _offset_frame:
		return
	_offset_frame = frame
	track_offset = track.closest_offset_near(global_position, track_offset)


## Запомнить положение тела этого кадра физики (см. _process: между ним и
## предыдущим и ставится картинка). Телепорт — сдвиг больше 4 м за тик —
## НЕ интерполируем: машина должна мигнуть на новое место, а не проехать
## призраком пол-трассы (респавн, догон дальнего снимка, «призрак»).
func _track_visual() -> void:
	_vis_prev = _vis_cur if _vis_on else global_transform
	_vis_cur = global_transform
	if _vis_prev.origin.distance_to(_vis_cur.origin) > 4.0:
		_vis_prev = _vis_cur
	_vis_on = true


## Где машина ВИДНА в этом кадре рендера (интерполированное положение тела).
## За телом тянутся не только модель, но и стрелка-указатель, значок эффекта
## и камера: если оставить их на теле, они поедут ступеньками 60 Гц, и
## машина будет «плыть» относительно собственной стрелки.
func visual_origin() -> Vector3:
	if not _vis_on:
		return global_position
	return _vis_prev.origin.lerp(
			_vis_cur.origin, Engine.get_physics_interpolation_fraction())


## После ТЕЛЕПОРТА (спавн, респавн, первый снимок марионетки) непрерывности
## нет — отметку берём глобальным поиском: машина в этот момент стоит на
## полотне, и он не ошибётся.
func reset_track_offset() -> void:
	if track == null:
		return
	track_offset = track._curve.get_closest_offset(global_position)
	_offset_frame = Engine.get_physics_frames()


func _physics_process(delta: float) -> void:
	if race != null and race.has_method("_wd_mark"):
		race._wd_mark("машина")
	sync_track_offset()
	# История позиций для отмотки лазера (см. past_position). До ранних
	# выходов: пишется и марионеткам, и ботам. 44 кадра ≈ 0.7 c.
	if Net.is_server():
		_pos_hist.push_back(global_position)
		if _pos_hist.size() > 44:
			_pos_hist.pop_front()
	# Пара положений тела для визуальной интерполяции (см. _process). Ведём
	# её для ВСЕХ машин, а не только для марионеток: тело шагает 60 раз в
	# секунду, а кадры рендера идут своим темпом, и на равных частотах эти
	# два ритма плывут друг относительно друга — то за кадр рендера пройдёт
	# два шага физики, то ни одного. Глаз читает это как дрожание ВСЕГО
	# кадра; своя машина стоит в центре и потому кажется ровной, а вот
	# соперники и трасса «дёргаются» — ровно та жалоба, что осталась после
	# кэша моделей и потока снимков 60/с.
	_track_visual()
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
	# Касание марионетки смотрим ПО ТЕКУЩЕМУ списку контактов, а не по
	# флагу с прошлого кадра (_puppet_touch): флаг взводился на кадр ПОЗЖЕ
	# удара, и самый первый — самый дикий — импульс от прыгнувшей в нас
	# марионетки проходил мимо капа. Ровно это игрок и ловил: «при рывке
	# врезаются в меня — огромный импульс, вылетаю за трассу».
	if _blast_time <= 0.0:
		var puppet_now := false
		for body in get_colliding_bodies():
			var oc := body as Car
			if oc != null and oc.net_role == NetRole.PUPPET:
				puppet_now = true
				break
		if puppet_now or _puppet_touch:
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
			and track.distance_from_axis_at(global_position, track_offset) \
			> track.half_width_at_offset(track_offset)
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
				and track.distance_from_axis_at(global_position, track_offset)
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
	# Таймер значка эффекта живёт ЗДЕСЬ, а не в _tick_status_icon: на
	# выделенном сервере спрайта-значка нет, _tick_status_icon выходит сразу,
	# и таймер там не гас бы никогда — а именно по нему сервер пакует значок
	# в снимок (status_icon_kind).
	_status_time = maxf(0.0, _status_time - delta)
	_boost_time = maxf(0.0, _boost_time - delta)
	_slip_time = maxf(0.0, _slip_time - delta)
	_scramble_time = maxf(0.0, _scramble_time - delta)
	_magnet_worn_time = maxf(0.0, _magnet_worn_time - delta)
	if _magnet_worn_time <= 0.0:
		_magnet_worn = 0.0
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
		_ghost_age += delta
		_ghost_time -= delta
		if _ghost_time <= 0.0:
			_end_ghost()


## Анимация колёс — в _process, а не _physics_process: кадр рисуется ПОСЛЕ
## решателя физики, и кламп колёс к полотну должен видеть уже конечное
## положение кузова (иначе на жёсткой посадке кузов доседал после клампа
## и колёса на кадр-два всё же ныряли под асфальт).
func _process(delta: float) -> void:
	# Тело шагает в физике (60 Гц), а МОДЕЛЬ каждый кадр рендера встаёт
	# между двумя последними положениями тела — движение гладкое на любом
	# fps (см. комментарий у _vis_prev). Раньше так вели только марионеток,
	# и это было полдела: камера и своя машина по-прежнему ходили
	# ступеньками, а на ступеньке дрожит ВЕСЬ кадр — соперники вместе с ним.
	# Пара положений ещё не набрана (первый кадр, только что был телепорт) —
	# ставим картинку прямо на тело, иначе она на кадр зависла бы на старом
	# месте: она top_level и сама за телом не едет.
	var xf := global_transform
	if _vis_on:
		xf = _vis_prev.interpolate_with(
				_vis_cur, Engine.get_physics_interpolation_fraction())
	var model := get_node_or_null("CarModel") as Node3D
	if model != null:
		if not model.top_level:
			_vis_base = model.transform
			model.top_level = true
		model.global_transform = xf * _vis_base
	# Фары — в то же самое место: висели бы на теле, отставали бы от
	# собственного кузова на шаг физики (см. _build_headlights).
	if _headlights != null:
		_headlights.global_transform = xf
	_animate_wheels(delta)
	_tick_status_icon(delta)
	if _ghost_time > 0.0:
		# Три моргания за время призрака: полпериода погашен — полпериода
		# виден (последний отрезок всегда «виден» — не застрять невидимым).
		# Считаем по ПРОЖИТОМУ времени (_ghost_age), а не по остатку: у
		# марионетки остаток подливается снимками и «прожитое» из него не
		# выводится (см. _ghost_age).
		var phase := int(_ghost_age / (ghost_time / 6.0))
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
	var partners: Array[Car] = []
	for body in get_colliding_bodies():
		var other := body as Car
		if other != null:
			partners.append(other)
	# Марионетки с 27.08 снова твёрдые (см. net_make_puppet), но их «касание»
	# ДОПОЛНИТЕЛЬНО меряем капсулами вдоль кузова: замороженное тело
	# телепортируется к снимкам, и solver-контакт на рывке канала может
	# мигнуть мимо кадра. Машина ~3.2×1.7 м → отрезок ±0.9 м по курсу,
	# контакт при сближении осей ближе 1.7 м; дубль солверного контакта
	# отсеет now[id]. Толчок дальше идёт общим кодом — рикошет один для всех.
	if not is_ghost():
		for node in get_tree().get_nodes_in_group("cars"):
			var other := node as Car
			if other == null or other == self \
					or other.net_role != NetRole.PUPPET:
				continue
			if absf(other.global_position.y - global_position.y) > 1.3:
				continue
			if _capsule_gap(other) < 1.7:
				partners.append(other)
	for other in partners:
		if other == null or not other.alive or other.is_ghost():
			continue
		var id := other.get_instance_id()
		if now.has(id):
			continue
		now[id] = true
		if other.net_role == NetRole.PUPPET:
			_puppet_touch = true
			# НЕПРОНИЦАЕМОСТЬ марионетки — вручную (решатель эту пару не
			# видит, см. net_make_puppet: его «твёрдая» версия вешала
			# GodotPhysics на 300+ мс). Перекрытие капсул выдавливает НАШУ
			# машину наружу ПОЗИЦИОННО, скорость не трогаем вовсе — толчок
			# и закрутку даёт общий рикошет ниже, и стенд PuppetPush следит,
			# чтобы жертва не разгонялась дичее 12 м/с. Шаг выдавливания
			# держит темп сближения (иначе полный ход 34 м/с протуннеливал
			# бы кузов между кадрами — TestPuppetSolid ловил проезд на 12 м
			# за центр соперника), но не меньше 0.25 м/кадр.
			var overlap := 1.7 - _capsule_gap(other)
			if overlap > 0.0:
				var away_o := global_position - other.global_position
				away_o.y = 0.0
				if away_o.length() > 0.01:
					away_o = away_o.normalized()
					var toward := -(linear_velocity
							- other.contact_velocity()).dot(away_o)
					var step_out := maxf(0.25, toward / 60.0)
					global_position += away_o * minf(overlap, step_out)
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
			if other.net_role == NetRole.PUPPET:
				# Помечаем контакт: если соперник пришлёт толчок-событие об
				# этом же касании, apply_net_shove его отбросит как дубль.
				_touch_mute[id] = float(Time.get_ticks_msec())
				# А машину ЖИВОГО ИГРОКА моя половина рикошета не сдвинет —
				# она клиент-авторитетна. Отправляем ЕМУ толчок через сервер:
				# все величины — с его стороны той же формулы (dir от меня к
				# нему, темп сближения симметричен, закрутка — его плечо).
				if net_role == NetRole.OWNED and race != null \
						and race.has_method("net_report_shove"):
					var rel_v := (linear_velocity - other_vel).limit_length(15.0)
					var lever_v := away * minf(dist * 0.5, 1.5)
					var spin_v := lever_v.cross(rel_v).y * bump_spin
					race.net_report_shove(other, -away, closing, spin_v)
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


## На сколько отматывать цели при выстреле ЭТОЙ машины. Не ноль только на
## сервере и только для машины живого игрока: он целился по своему экрану,
## где соперники отстают на его буфер (net_client_lag приходит в состоянии
## владельца, протокол 13). Боты и оффлайн стреляют по текущему миру — их
## картина и есть правда.
func net_shot_lag() -> float:
	if not (Net.is_server() and net_role == NetRole.PUPPET):
		return 0.0
	# Пока владелец не доложил своё отставание — скромная догадка вместо
	# прежних 0.4: перекомпенсация бьёт по тем, в кого стреляют.
	return net_client_lag if net_client_lag > 0.0 else 0.12


## Где машина была age секунд назад (по серверной истории _pos_hist).
## Нет истории — текущая позиция.
func past_position(age: float) -> Vector3:
	if _pos_hist.is_empty():
		return global_position
	var back := clampi(int(round(age * 60.0)), 0, _pos_hist.size() - 1)
	return _pos_hist[_pos_hist.size() - 1 - back]


## Толчок от машины ЖИВОГО ИГРОКА, доставленный сервером (_rx_fx SHOVE).
## Свой рикошет соперник о мою марионетку считает у себя, но МОЮ машину
## подвинуть не может — она клиент-авторитетна: без события таран игрока
## игроком «не сдвигал и не поддевал» (жалоба 28.08). dir — куда толкать
## (от агрессора ко мне), closing — темп сближения (как в рикошете),
## spin — закрутка. Все величины считает агрессор ПО СВОЕЙ картине —
## именно её он и видел в момент удара.
func apply_net_shove(attacker: Car, dir: Vector3, closing: float,
		spin: float) -> void:
	if not alive or is_ghost():
		return
	# Этот контакт я уже отработал сам (тёрка бок-о-бок видна на обоих
	# экранах): событие — дубль, пропускаем.
	if attacker != null:
		var t: float = _touch_mute.get(attacker.get_instance_id(), -1.0e12)
		if Time.get_ticks_msec() - t < 400.0:
			return
	dir.y = 0.0
	if not dir.is_finite() or dir.length() < 0.5:
		return
	dir = dir.normalized()
	# Каппы те же, что у собственного рикошета: сближение ≤ 20 (толчок
	# ≤ 8 м/с), закрутка в пределах ±3.
	_ext_push_time = 0.3
	apply_central_impulse(dir * clampf(closing, 0.0, 20.0) * 0.4 * mass)
	if absf(spin) > 0.15:
		angular_velocity.y = clampf(
				angular_velocity.y + clampf(spin, -3.0, 3.0), -3.0, 3.0)
		_bump_spin_time = 0.6


## Зазор между осевыми отрезками двух кузовов в плане (капсулы): 0 —
## отрезки пересекаются. Отрезок = позиция ± курс×0.9 (полукузов без
## бамперов, радиус капсулы добирает остальное).
func _capsule_gap(other: Car) -> float:
	var fa := -global_transform.basis.z
	fa.y = 0.0
	fa = fa.normalized() * 0.9 if fa.length_squared() > 1e-6 else Vector3.ZERO
	var fb := -other.global_transform.basis.z
	fb.y = 0.0
	fb = fb.normalized() * 0.9 if fb.length_squared() > 1e-6 else Vector3.ZERO
	var pa := global_position
	var pb := other.global_position
	pa.y = 0.0
	pb.y = 0.0
	# Ближайшие точки двух отрезков — перебором по 5 точкам каждого:
	# для аркадного «коснулись/нет» точности хватает, а кода на порядок
	# меньше, чем у точного сегмент-сегмент решения.
	var best := 1e9
	for i in 5:
		var qa := pa + fa * (i * 0.5 - 1.0)
		for j in 5:
			best = minf(best, qa.distance_to(pb + fb * (j * 0.5 - 1.0)))
	return best


## Сброс памяти скорости. Звать при телепорте/респавне: иначе защита
## приземления «вернёт» скорость, которой у машины уже нет.
## Скорость машины для расчётов столкновений. У марионетки linear_velocity
## брать нельзя: Godot пересчитывает её по сдвигу замороженного трансформа
## (завышает вдвое, а на рывке канала — многократно), берём присланную.
func contact_velocity() -> Vector3:
	if net_role != NetRole.PUPPET:
		return linear_velocity
	# У клиентской марионетки — скорость воспроизводимого КУСКА ЗАПИСИ с
	# поправкой на ТЕМП (при недоборе буфера время растягивается, и на
	# экране машина едет медленнее записи); у серверной — последний снимок.
	return _play_vel * _play_rate \
			if Net.is_client() and _play_t >= 0.0 else _snap_vel


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
## stamp — номер тика ЧАСОВ АВТОРА состояния (для бота — сервер, для машины
## живого игрока — её владелец; сервер ретранслирует метку владельца как
## есть). По меткам клиентский буфер строит шкалу воспроизведения: у потока
## машины игрока состояния то пропускаются в ретрансляции (два пакета
## владельца между тиками сервера), то дублируются — счёт «+1/60 на снимок»
## для него врал, и соперник-игрок дёргался даже на локалхосте (13.5%
## против 3.5-6% у ботов). stamp < 0 — вызов без метки (стенды, старый
## путь): дубликаты ловятся по равенству позиций, шкала — счётом.
func net_apply_snapshot(pos: Vector3, rot: Quaternion, vel: Vector3,
		stamp := -1.0) -> void:
	# ДУБЛИКАТ (та же метка / состояние не изменилось) не обнуляет
	# возраст: сброс возраста на копии останавливал экстраполяцию —
	# марионетка шла «стоп-скачок». Пусть возраст растёт.
	# ВАЖНО: дубликат — только РАВНАЯ метка. Метка МЕНЬШЕ прошлой — это не
	# «старый пакет» (канал ordered, внутри одного автора метки не убывают),
	# а СМЕНА АВТОРА состояния: у сервера и владельца свои счётчики тиков.
	# 27.08 здесь стояло `stamp <= _snap_stamp`, и ветка «метка прыгнула
	# назад — буфер в печку» ниже была недостижима: часы VDS (работает
	# часами) много больше часов свежезапущенного клиента, ПЕРВЫЙ снимок
	# слота метится часами сервера (владелец ещё не прислал ни одного
	# состояния — см. Main._pack_state), и ВСЕ последующие состояния живого
	# игрока отбрасывались тут как дубликаты — «друг у друга стоим на месте».
	# На локалхосте не ловилось: сервер стартует на секунды раньше клиента,
	# разрыв часов крошечный, и владелец «догонял» метку сервера за секунды.
	if stamp >= 0.0:
		if _snap_seen and stamp == _snap_stamp:
			return
	elif _snap_seen and pos.is_equal_approx(_snap_pos) \
			and vel.is_equal_approx(_snap_vel):
		return
	_snap_pos = pos
	_snap_rot = rot
	_snap_vel = vel
	_snap_age = 0.0
	# Клиентская марионетка ведётся по БУФЕРУ (сервер — по экстраполяции,
	# ему отставание вредно: по позициям марионеток бьёт оружие).
	if Net.is_client():
		var t: float
		if stamp >= 0.0:
			# Честная шкала по часам автора. Метка прыгнула назад ИЛИ далеко
			# вперёд — у слота сменился автор (бот <-> игрок: у сервера и у
			# владельца свои счётчики тиков) либо дыра больше двух секунд,
			# которую всё равно не сгладить. Запись с чужой шкалой — в печку,
			# иначе пара «старое время -> новое» растягивалась на минуты и
			# машина ползла (пойман хвост 203% в замере при выходе водителя).
			if _snap_stamp >= 0.0 and (stamp < _snap_stamp
					or stamp - _snap_stamp > 120.0):
				_buf.clear()
				_play_t = -1.0
			t = stamp / 60.0
		else:
			# Без метки — счёт «+1/60» с перепривязкой, если плеер обогнал
			# запись (пауза дубликатов, дыра аплинка): без неё буфер жил в
			# вечном недоборе, темп расползался на 0.6-1.4 — те самые рывки.
			t = maxf(_buf_t + 1.0 / 60.0, _play_t + 0.001)
		_buf_t = t
		_buf.append({"pos": pos, "rot": rot, "vel": vel, "t": t})
		if _buf.size() > 90:   # полторы секунды истории за глаза
			_buf.pop_front()
	_snap_stamp = stamp
	if not _snap_seen:
		_snap_seen = true
		global_position = pos
		global_transform.basis = Basis(rot)
		# Первый снимок — телепорт куда угодно (машина могла уехать полкруга,
		# пока мы её не видели): непрерывность отметки тут ни при чём.
		reset_track_offset()


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
#
# 27.08 ПЕРЕСМОТРЕНО с 0.12 до 0.40. Те замеры делались, когда сервер сам
# вставал на 0.3-0.4 с (зависание решателя, вылечено в net_make_puppet), и
# «уезжает вперёд, потом стоит» было про догон после ЕГО фризов. Канал до
# VDS ведёт себя иначе: пакеты не теряются (поток 59.8/с из 60), а приходят
# ПАЧКАМИ — за 16 с замера 11 дыр по 100-400 мс (см. печать `[gap]` в
# Main._rx_state). На коротком капе марионетка в каждую дыру замирала и
# догоняла — это и есть «боты дёргаются». Замер картинки на живом рендере
# (tools/DbgVisualJitter, доля кадров, где картинка проехала меньше пятой
# части положенного):
#   0.12 с → 13.4% дрожания, 8-10 замираний на 600 кадров
#   0.40 с →  7.8% дрожания, 0-3 замирания      ← берём
#   0.70 с →  8.7% дрожания, 1-2 замирания (не лучше, а рассинхрон вдвое)
# Рывков назад при 0.40 стенд не ловит: от них защищает правило «против
# своего хода не едем» ниже.
const MAX_EXTRAP := 0.40
# Упреждение цели по скорости из снимка — компенсация хвоста усиленного
# сглаживания (tau ~ 83 мс, см. k ниже). Подобрано замером DbgVisualJitter:
# 0.06 (полная компенсация) раскачивало картинку обратно до 9.8% — скачки
# СКОРОСТИ в снимках упреждение умножает; 0.03 держит 7.2% при вдвое
# меньшем запаздывании, чем без компенсации вовсе.
const LEAD := 0.03
func _follow_snapshot(delta: float) -> void:
	if not _snap_seen:
		return
	# Клиент рисует марионетку ПО ЗАПИСИ (см. _follow_buffered), экстраполяция
	# ниже остаётся серверу и страховкой на пустой буфер.
	if Net.is_client() and not _buf.is_empty():
		_follow_buffered(delta)
		return
	# Возраст снимка ОГРАНИЧЕН. Без ограничения запоздавший пакет уводил
	# цель далеко вперёд, а следующий снимок возвращал её назад — машину
	# дёргало. На одном клиенте по локалхосту этого не видно (пакеты идут
	# ровно), а на двух уже ловится: замер показывал 4 рывка назад за 419
	# кадров у второго игрока.
	_snap_age = minf(_snap_age + delta, MAX_EXTRAP)
	# LEAD компенсирует отставание сглаживания: подтяжка с постоянной
	# времени ~5 кадров держала бы марионетку на vel*tau (до 2 м) позади
	# истинного места — целимся на столько же ВПЕРЁД по присланной скорости.
	var target := _snap_pos + _snap_vel * (_snap_age + LEAD)
	# Коэффициент подтяжки независим от частоты кадров. 27.08 сглаживание
	# усилено 0.35 -> 0.2 на кадре 60 Гц (основание 0.65 -> 0.80): жалоба
	# «боты по сети дёргаются» осталась при ровном потоке 60/с, и замер
	# КАРТИНКИ (tools/DbgVisualJitter, живой рендер) показал, что дрожание
	# идёт от неровности шагов самого тела — 10.5%% при 0.65 против 6.8%%
	# при 0.80; дальше (0.88) выигрыш копеечный, а хвост запаздывания растёт.
	var k := 1.0 - pow(0.80, delta * 60.0)
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


# Насколько позади свежайшего снимка идёт воспроизведение. Это плата за
# честность: дыры канала короче этой величины заполняются НАСТОЯЩИМИ
# снимками (интерполяция между соседними), а не гаданием по скорости —
# гадание на повороте врёт вбок, и приехавшая пачка дёргала машину
# («боты движутся с рывками» после всех прочих правок).
# Подбор по замерам DbgVisualJitter против ЖИВОГО VDS (дрожание картинки /
# замираний на 600 кадров, 4-7 прогонов на вариант):
#   только экстраполяция 0.40:  5-13% / 1-16   (гадание + рывки коррекции)
#   буфер 0.20:                 7-14% / 3-11   (дыры канала 350-420 мс
#                                              длиннее отставания)
#   буфер 0.35:                2.6-7.4% / 0-1  ← берём
# Плата: соперник на экране позади себя настоящего на ~0.35 с (до 7 м на
# полном ходу). Для аркады с клиент-авторитетными машинами это честно:
# толчки на экране считаются от ВИДИМЫХ положений (contact_velocity), а
# оружие и подборы боксов и так решает сервер по своей картине.
#
# 28.08 СТАЛО АДАПТИВНЫМ. Разбор жалобы «друг у меня чуть позади» показал,
# что 0.35 — это ХУДШИЙ СЛУЧАЙ канала, применявшийся ВСЕГДА, в том числе
# когда канал чист. Замеры (клиент печатает «ПРИРОДА ДЫР»):
#   VDS шлёт 60.0 тиков/с и ОТПРАВЛЯЕТ их ровно (tcpdump на eth0: интервалы
#     13.7/20.7 мс, дыр по 100-300 мс на выходе НЕТ ВОВСЕ);
#   до клиента доходит 54-59 из 60, с провалами до 330 мс;
#   зонд главного цикла сервера (порог 50 мс) не сработал ни разу.
# То есть рвёт ПОСЛЕДНЯЯ МИЛЯ, а не игра и не сервер — прежний вывод
# «сервер фризит» (26.08) и «так себя ведёт канал, буфер должен покрывать
# худшее» (27.08) верны лишь наполовину: покрывать надо СТОЛЬКО, СКОЛЬКО
# рвёт ПРЯМО СЕЙЧАС. Стандарт индустрии — адаптивное отставание (Unity
# Netcode for Entities, Overwatch; у Valve фиксированные 100 мс считаются
# наследием эпохи модемов). Держим худший разрыв за недавнее окно: растём
# мгновенно (дыра — сразу закладываемся), спадаем медленно (BUF_DECAY,
# ~5 c с потолка до пола). На локальной сети и в тихие минуты отставание
# схлопывается к 60 мс — соперник вместо 7 м позади себя настоящего идёт
# в метре.
const BUF_MIN := 0.06     # 3-4 снимка: меньше — дыра в один пакет уже рвёт
const BUF_MAX := 0.35     # прежняя константа как ПОТОЛОК
const BUF_START := 0.12   # с чего начинаем, пока канал не измерен
# На столько секунд в секунду опускаем «худшее». Подбор 28.08 на живом VDS
# (замираний картинки на 600 кадров, 3 прогона на вариант):
#   x1.25 + 0.025, спад 0.06, пол 60 мс — 0 / 0 / 0   ← берём
#   x1.0  + 0.03,  спад 0.12, пол 50 мс — 0 / 1 / 0
#   x0.8  + 0.03,  спад 0.20, пол 40 мс — 0 / 2 / 1
# Требование «не допускать дрожания» выполняет только первый набор.
const BUF_DECAY := 0.06
## Текущее отставание воспроизведения — ОДНО на все машины: рвёт канал, а
## не отдельную марионетку. Ведёт Main._rx_state через net_note_gap.
static var net_buf_delay := BUF_START
static var _buf_worst := 0.0
static var _buf_sum := 0.0    # для замеров: среднее отставание за прогон
static var _buf_n := 0


## Среднее отставание за прогон (читают стенды).
static func buf_avg() -> float:
	return _buf_sum / float(_buf_n) if _buf_n > 0 else net_buf_delay


## Пришёл снимок через gap секунд после прошлого — пересчитать отставание.
## Запас 1.25 и полтора кадра сверху: интерполяции нужна пара снимков ПО
## ОБЕ стороны от плеера, впритык к худшему разрыву буфер пустеет.
static func net_note_gap(gap: float) -> void:
	_buf_worst = maxf(gap, _buf_worst - gap * BUF_DECAY)
	net_buf_delay = clampf(_buf_worst * 1.25 + 0.025, BUF_MIN, BUF_MAX)
	_buf_sum += net_buf_delay
	_buf_n += 1


## Новый заезд/переподключение: канал меряем заново.
static func net_reset_buf_delay() -> void:
	_buf_worst = 0.0
	net_buf_delay = BUF_START
	_buf_sum = 0.0
	_buf_n = 0


## Воспроизведение записи снимков с отставанием net_buf_delay и адаптивной
## скоростью: буфер разбухает (пачка приехала) — плеер идёт до 15% быстрее,
## буфер тает (дыра канала) — до 15% медленнее, растягивая остаток настоящих
## данных на дыру. Кончился буфер совсем — короткая экстраполяция и, если
## дыра затянулась, честное замирание (см. историю в _follow_snapshot:
## далеко угадывать хуже, чем стоять).
func _follow_buffered(delta: float) -> void:
	if _play_t < 0.0:
		_play_t = _buf_t - net_buf_delay
	# Сколько НАСТОЯЩЕЙ записи ещё впереди плеера.
	var ahead := _buf_t - _play_t
	var err := ahead - net_buf_delay
	var rate := 1.0 + clampf(err * 0.5, -0.15, 0.15)
	# ЗАПАС КОНЧАЕТСЯ — РАСТЯГИВАЕМ ВРЕМЯ, а не замираем (28.08). Приём из
	# джиттер-буферов телефонии (time-scale modification): вместо того чтобы
	# встать колом и потом рвануть догонять, соперник на доли секунды едет
	# медленнее — глаз этого почти не ловит, а замирание ловит сразу.
	# Замер на живом VDS (замираний картинки на 600 кадров, 3 прогона на
	# вариант; чем агрессивнее буфер, тем чаще он пустеет):
	#   буфер ~150 мс (текущие константы): 0 / 0 / 0 замираний
	#   буфер ~90 мс:  без растяжения 2/0/0, с растяжением 0/1/0
	#   буфер ~70 мс:  без растяжения 0/10/1, с растяжением 0/2/1
	# То есть растяжение заметно спасает агрессивные настройки, но НЕ даёт
	# опустить буфер безнаказанно — константы оставлены консервативными
	# («не допускать дрожания»), а растяжение работает страховкой на
	# случайные провалы канала.
	# Порог STRETCH_AT — примерно три снимка: ниже этого запаса дыра уже
	# рвёт интерполяцию.
	const STRETCH_AT := 0.05
	const RATE_MIN := 0.35
	if ahead < STRETCH_AT:
		rate = minf(rate, maxf(RATE_MIN, ahead / STRETCH_AT))
	_play_rate = rate
	_play_t += delta * rate
	# Выкинуть прожитое, оставив одну запись ПЕРЕД плеером (левый конец пары).
	while _buf.size() > 1 and (_buf[1]["t"] as float) <= _play_t:
		_buf.pop_front()
	var a: Dictionary = _buf[0]
	var target: Vector3
	var target_rot: Quaternion
	if _buf.size() >= 2:
		var b: Dictionary = _buf[1]
		var span := (b["t"] as float) - (a["t"] as float)
		var u := clampf((_play_t - (a["t"] as float)) / maxf(span, 0.001),
				0.0, 1.0)
		target = (a["pos"] as Vector3).lerp(b["pos"] as Vector3, u)
		target_rot = (a["rot"] as Quaternion).slerp(b["rot"] as Quaternion, u)
		_play_vel = (a["vel"] as Vector3).lerp(b["vel"] as Vector3, u)
	else:
		# Плеер догнал запись: чуть-чуть угадываем по скорости. Кап нарочно
		# короткий — буфер уже съел типичную дыру, дальше лучше замереть.
		var over := minf(_play_t - (a["t"] as float), MAX_EXTRAP)
		target = (a["pos"] as Vector3) + (a["vel"] as Vector3) * over
		target_rot = a["rot"] as Quaternion
		_play_vel = a["vel"] as Vector3
	# Тело к цели: телепорт при большой невязке, иначе быстрая подтяжка
	# (запись сама гладкая — сглаживание лишь прячет стыки после недоборов)
	# и страховка «назад против хода не едем».
	var k := 1.0 - pow(0.5, delta * 60.0)
	if global_position.distance_to(target) > 8.0:
		global_position = target
	else:
		var next := global_position.lerp(target, k)
		var step := next - global_position
		if _play_vel.length() > 1.0 and step.dot(_play_vel) < 0.0:
			next = global_position
		global_position = next
	var cur := global_transform.basis.get_rotation_quaternion()
	global_transform.basis = Basis(cur.slerp(target_rot, k))
	# Скорость — ВИДИМАЯ, то есть с поправкой на темп воспроизведения: при
	# растяжении времени машина на экране едет медленнее записи, и толчки от
	# неё (contact_velocity) должны считаться от того, что видно. Заодно это
	# делает честными сами замеры: без поправки растянутый кусок выглядел бы
	# «замиранием» на фоне неизменившейся эталонной скорости.
	linear_velocity = _play_vel * _play_rate


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
	# Исключения решателя с марионетками СТОЯТ, и это выстрадано ДВАЖДЫ:
	# 26.08 без исключений решатель выдавливал машины диким импульсом, а
	# 27.08 попытка «сделать твёрдо, дикость держит кап» кончилась хуже —
	# GodotPhysics ЗАВИСАЛ на 300-430 мс на паре «телепортирующаяся
	# кинематика в контакте с динамикой» (вачдог: «машина -> рендер: 324 мс»,
	# у клиентов это выглядело дырами потока снимков в КАЖДОМ заезде и
	# жалобой «теперь ещё больше дёргаются»). Непроницаемость решателем НЕ
	# делается вовсе: сквозной проезд закрывает ручное выдавливание в
	# _bounce_off_cars (см. там), решатель марионеток не видит.
	_set_solid_to_cars(false)
	for p in _smoke:
		p.emitting = false
	if _boost_flame:
		_boost_flame.emitting = false


## Твёрдость к ДРУГИМ МАШИНАМ в решателе физики (дорога и стены не
## трогаются). Исключение действует на пару, если стоит хотя бы у одной
## стороны, поэтому достаточно править список у себя.
func _set_solid_to_cars(solid: bool) -> void:
	for node in get_tree().get_nodes_in_group("cars"):
		if node == self or not (node is PhysicsBody3D):
			continue
		if solid:
			remove_collision_exception_with(node)
		else:
			add_collision_exception_with(node)


## Смена роли машины — это ТЕЛЕПОРТ (клиент пересаживается в свою машину,
## сервер возвращает слот боту): пара положений от прошлой роли врёт, и
## интерполяция протащила бы модель через пол-трассы. Гасим её на кадр —
## _track_visual наберёт новую пару, а _process до тех пор ставит модель
## прямо на тело. Саму отвязку модели (top_level) НЕ отменяем: с 26.08
## интерполируются все машины, а не только марионетки.
func net_visual_reset() -> void:
	_vis_on = false


## Обратно под бота (сервер: игрок вышел). Снимки владельца больше не
## придут — без сброса _snap_seen машина зависла бы марионеткой навсегда.
func net_make_local() -> void:
	net_role = NetRole.LOCAL
	is_player = false
	freeze = false
	_snap_seen = false
	_snap_stamp = -1.0
	_buf.clear()
	_play_t = -1.0
	net_fire = false
	_set_solid_to_cars(true)
	net_visual_reset()


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
	# Футбол: цели ботам считает менеджер матча (роль, мяч, ворота) —
	# трасса не нужна, оружие в футболе не применяется.
	if soccer_brain != null:
		var cmd: Vector2 = soccer_brain.ai_drive(self)
		_drive(delta, on_ground, cmd.x, cmd.y, false, false)
		return
	if track == null:
		return
	var curve: Curve3D = track._curve
	var length := curve.get_baked_length()
	var my_off := track_offset
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
			Weapons.ROCKET, Weapons.LASER, Weapons.FREEZE, Weapons.SCRAMBLE:
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
	# Глушилка: лево и право поменяны местами. Именно здесь, а не на чтении
	# ввода — инверсия достаётся и игроку, и боту одной строкой.
	if _scramble_time > 0.0:
		steer = -steer
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
	var off := track_offset
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
	var off := track_offset
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
	var _wd0 := Time.get_ticks_msec()
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
			# Снаряд живого игрока проверяет попадание по ОТМОТАННЫМ целям —
			# как лазер: он целился в то, что видел на своём экране.
			p.lag = net_shot_lag()
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
		Weapons.SCRAMBLE:
			var w := ScrambleWave.new()
			w.shooter = self
			w.direction = fwd
			# Отмотка целей — как у снарядов: стрелявший целился по своему
			# экрану (протокол 13).
			w.lag = net_shot_lag()
			get_parent().add_child(w)
			w.global_position = global_position + fwd * 2.3 + Vector3.UP * 0.55
			FxKit.muzzle_flash(get_parent(), w.global_position,
					Color(0.4, 0.95, 1.0))
			# Горизонтальная волна от машины в момент выстрела — сразу видно
			# радиус действия (просьба 31.08).
			FxKit.ring(get_parent(), global_position, ScrambleWave.HIT_R,
					Color(0.4, 0.95, 1.0))
		Weapons.AIRSTRIKE:
			_use_airstrike()
		Weapons.BOOST:
			apply_boost()
			FlashFx.spawn(get_parent(),
					global_position + Vector3.UP * 0.5, 1.2,
					Color(0.3, 0.9, 1.0))
			FxKit.ring(get_parent(), global_position, 2.2,
					Color(0.3, 0.9, 1.0))
	var _wd := Time.get_ticks_msec() - _wd0
	if _wd > 100:
		print("[slow] use_weapon(%d) занял %d мс" % [kind, _wd])


## Магнит: ВСЕ машины заезда разово получают импульс к этой машине —
## магнит достаёт всю трассу (так и задумано игроком). Вблизи рывок сильный
## (сносит с траектории и разворачивает), с расстоянием слабеет до
## MAGNET_FAR и дальше уже не спадает.
## ДАЛЬНИХ ТЯНЕТ ВДОЛЬ ТРАССЫ, а не по прямой (см. _magnet_pull_dir): рывок
## по хорде к сопернику за поворотом уводил жертву в поле — жалоба 31.08
## «магнитит куда-то за пределы трассы, где никого нет». Подброса почти
## нет: магнит волочит по земле. Тем, кто ВПЕРЕДИ по гонке, магнит вдобавок
## режет скорость (осаживает); задних — только притягивает.
## Повторные рывки СЛАБЕЮТ (см. Car.magnet_wear): пара соперников, применив
## магнит подряд, выкидывала жертву с трассы суммой импульсов.
func _use_magnet() -> void:
	const MAGNET_PULL := 22.0     # импульс вблизи, м/с
	const MAGNET_FAR := 8.0       # к чему сходит на дальней дистанции
	const MAGNET_RANGE := 55.0    # дистанция, на которой спад завершён
	const MAGNET_SPIN := 2.6      # закрутка от рывка, рад/с
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
		# ДАЛЬНОСТЬ мерим по картине стрелявшего (он видит соперников с
		# отставанием своего буфера, протокол 13), а НАПРАВЛЕНИЕ рывка — по
		# нынешним положениям: тянуть надо туда, где магнит есть сейчас.
		# Раньше вектор шёл из ОТМОТАННОЙ точки жертвы, и после её телепорта
		# (взрыв, респавн) история давала точку в другом конце трассы —
		# машину рвало в сторону от всех.
		var dist := global_position.distance_to(other.past_position(net_shot_lag()))
		var dir := global_position - other.global_position
		dir.y = 0.0
		var len_now := dir.length()
		if len_now < 0.1:
			continue
		dir /= len_now
		# Дальних тянем ПО ТРАССЕ, а не сквозь неё.
		dir = _magnet_pull_dir(other, dir, dist)
		# И с полотна не сдёргиваем: у края рывок разворачивается вдоль
		# трассы, а если и вдоль некуда — магнит эту машину не трогает.
		var pull_dir := _magnet_guard(other, dir)
		if pull_dir.length_squared() < 1e-4:
			continue
		var t: float = clampf(dist / MAGNET_RANGE, 0.0, 1.0)
		var wear := other.magnet_wear()
		var power: float = lerpf(MAGNET_PULL, MAGNET_FAR, t) * wear
		var spin := MAGNET_SPIN * (1.0 - t) * wear \
				* (1.0 if randf() < 0.5 else -1.0)
		# Впередиедущих осаживаем ДО рывка: срежь скорость после — порезался
		# бы и сам импульс притяжения.
		if _rival_is_ahead(other):
			other.apply_speed_cut(lerpf(0.65, 1.0, 1.0 - wear))
		other.push_from_blast(pull_dir, power, spin, 0.12)
		other.show_effect_icon(Weapons.MAGNET, MAGNET_ICON_TIME)
		other.notify_hit_by(self, Weapons.MAGNET)
		# Разряд над жертвой — видно, кого дёрнуло.
		FxKit.lightning_burst(get_parent(),
				other.global_position + Vector3.UP * 0.9,
				Color(0.85, 0.4, 1.0), 4, 0.9)


## Куда магнит тянет жертву. Вблизи (до MAGNET_NEAR) — прямо к магниту, как
## и должно тянуть магнит. Дальше прямая перестаёт быть путём: соперник за
## поворотом стоит «через поле», и рывок по хорде уносил жертву с трассы —
## жалоба 31.08 «магнитит куда-то за пределы трассы, где никого нет».
## Поэтому с расстоянием направление плавно переходит в КАСАТЕЛЬНУЮ К
## ТРАССЕ, повёрнутую в сторону магнита по КРАТЧАЙШЕМУ пути по кольцу:
## дальнего волочёт по полотну — вперёд или назад по трассе.
func _magnet_pull_dir(victim: Car, straight: Vector3, dist: float) -> Vector3:
	const MAGNET_NEAR := 18.0   # ближе — тянем строго по прямой
	const MAGNET_ALONG := 45.0  # дальше — строго вдоль трассы
	if track == null or dist <= MAGNET_NEAR:
		return straight
	var curve: Curve3D = track._curve
	var length := curve.get_baked_length()
	var along := _axis_dir(curve, length, victim.track_offset)
	along.y = 0.0
	if along.length_squared() < 1e-6:
		return straight
	along = along.normalized()
	# Кратчайший ход по кольцу: положительный — магнит впереди по разметке.
	var delta := wrapf(track_offset - victim.track_offset,
			-length * 0.5, length * 0.5)
	if absf(delta) < 0.5:
		return straight
	along *= signf(delta)
	var t: float = clampf((dist - MAGNET_NEAR) / (MAGNET_ALONG - MAGNET_NEAR),
			0.0, 1.0)
	var mixed := straight.lerp(along, t)
	# Прямая и трасса могут смотреть строго навстречу (шпилька): смесь
	# схлопывается в ноль — тогда правда за трассой.
	return mixed.normalized() if mixed.length_squared() > 1e-4 else along


## Множитель силы для СЛЕДУЮЩЕГО рывка магнита по этой машине и отметка
## самого рывка. Пока рывки идут в окне MAGNET_WEAR_TIME, каждый следующий
## слабее: 1.0, 0.55, 0.38, 0.29… Жалоба 31.08: «несколько машин применили
## магнит — и тебя выкидывает с трассы с огромной силой»; сумма трёх полных
## импульсов и правда выносила за ограждение.
func magnet_wear() -> float:
	const MAGNET_WEAR_TIME := 3.0
	var mult := 1.0 / (1.0 + 0.8 * _magnet_worn)
	_magnet_worn += 1.0
	_magnet_worn_time = MAGNET_WEAR_TIME
	return mult


## Не выдёргивать жертву С ПОЛОТНА: составляющую рывка НАРУЖУ от оси трассы
## гасим по мере приближения к краю. Магнит соперника за поворотом тянет по
## хорде — «мимо трассы», и на песчаной трассе (ограждений нет вовсе) это
## заканчивалось полётом в пески. У края рывок остаётся, но идёт ВДОЛЬ
## трассы, а не в сторону от неё; если и вдоль некуда (магнит ровно сбоку
## за ограждением) — возвращаем ноль, и рывка не будет вовсе.
func _magnet_guard(victim: Car, dir: Vector3) -> Vector3:
	const EDGE_MARGIN := 2.0   # ближе этого к грани борта наружу не тянем
	const EDGE_FADE := 5.0     # на каком запасе гашение начинается
	if victim.track == null:
		return dir
	var curve: Curve3D = victim.track._curve
	var length := curve.get_baked_length()
	var off := fposmod(victim.track_offset, length)
	var axis_pos := curve.sample_baked(off)
	var n := victim.global_position - axis_pos
	n.y = 0.0
	var from_axis := n.length()
	if from_axis < 0.01:
		return dir
	n /= from_axis
	var outward := dir.dot(n)
	if outward <= 0.0:
		return dir  # тянет К оси трассы — пусть тянет
	var room: float = victim.track.half_width_at_offset(off) \
			- EDGE_MARGIN - from_axis
	var keep: float = clampf(room / EDGE_FADE, 0.0, 1.0)
	var fixed := dir - n * outward * (1.0 - keep)
	if fixed.length_squared() > 1e-4:
		return fixed.normalized()
	# Рывок был СТРОГО наружу — разворачиваем его вдоль трассы, в ту
	# сторону, куда он и «смотрел».
	var tangent := curve.sample_baked(fposmod(off + 1.0, length)) - axis_pos
	tangent.y = 0.0
	if tangent.length_squared() < 1e-6:
		return Vector3.ZERO
	tangent = tangent.normalized()
	var along := dir.dot(tangent)
	return tangent * signf(along) if absf(along) > 0.05 else Vector3.ZERO


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
	# Отмотка целей для выстрела ЖИВОГО ИГРОКА (на сервере его машина —
	# марионетка): стрелявший целился в картину своего экрана, где соперник
	# отстаёт на буфер воспроизведения (~0.35 c, Car.BUF_DELAY) и полёт
	# пакета. Сервер меряет попадание по позициям НА ТОТ МОМЕНТ (история
	# _pos_hist) — «попал в то, что видел». Боты и оффлайн стреляют по
	# текущему миру: их картина и есть правда.
	var lag := net_shot_lag()
	var from := global_position + Vector3.UP * 0.5
	LaserFx.spawn(get_parent(), from, fwd, RANGE, self)
	for node in get_tree().get_nodes_in_group("cars"):
		var other := node as Car
		if other == self or not other.alive or other.is_ghost():
			continue
		var to := other.past_position(lag) - global_position
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
	var _wd0 := Time.get_ticks_msec()
	_forward_fx(NetFx.DESTROY)
	# И ВСЕМ ОСТАЛЬНЫМ — чтобы взрыв увидел не только владелец машины.
	# Раньше третьи игроки не видели ни вспышки, ни мигания: у них машина
	# просто «переставлялась» снимками и как будто ехала дальше.
	if Net.is_server() and race != null \
			and race.has_method("net_broadcast_destroy"):
		race.net_broadcast_destroy(self)
	_boom_fx(global_position)
	if track:
		# Отметка СВОЯ (по непрерывности): уничтоженную у ограждения машину
		# глобальный поиск мог вернуть на чужой виток кольца.
		global_transform = track.respawn_transform_at(track_offset)
		reset_track_offset()
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	reset_speed_memory()
	_freeze_time = 0.0
	_slip_time = 0.0
	_boost_time = 0.0
	_scramble_time = 0.0
	_start_ghost()
	var _wd := Time.get_ticks_msec() - _wd0
	if _wd > 100:
		print("[slow] destroy() занял %d мс" % _wd)


## Взрыв машины — одной строкой (зовут destroy и сетевая копия события).
func _boom_fx(at: Vector3) -> void:
	FlashFx.spawn(get_parent(), at, 2.4, Color(1.0, 0.45, 0.1))
	FxKit.ring(get_parent(), at, 3.4, Color(1.0, 0.55, 0.15))
	FxKit.smoke_burst(get_parent(), at + Vector3.UP * 0.4, 12, 1.2)
	SparksFx.spawn(get_parent(), at + Vector3.UP * 0.5, 10.0)
	FxKit.fire_burst(get_parent(), at + Vector3.UP * 0.3)
	FxKit.scorch(get_parent(), at)


## Начало «призрака»: мигание с нуля и никаких контактов с машинами
## (слой 4 убран с обеих сторон); дорога (1) и стены (2) остаются.
func _start_ghost() -> void:
	_ghost_time = ghost_time
	_ghost_age = 0.0
	collision_layer = 0
	collision_mask = 0b011


## Конец «призрака»: контакты и видимость возвращаются.
func _end_ghost() -> void:
	_ghost_time = 0.0
	_ghost_age = 0.0
	collision_layer = 0b100
	collision_mask = 0b111
	visible = true


## КЛИЕНТ: соперника уничтожили (Main._rx_destroy_fx). Физику и переезд к
## месту появления привезут снимки — здесь только то, что игрок должен
## УВИДЕТЬ: взрыв там, где машина видна ЕМУ (картинка марионетки отстаёт
## на буфер, и взрыв по «серверному сейчас» вспыхнул бы в стороне), и
## мигание неуязвимости.
func net_show_destroy() -> void:
	_boom_fx(visual_origin())
	net_set_ghost(true)


## Признак «призрака» из снимка (Main._rx_state): пока сервер его шлёт,
## таймер подливается, а кончился флаг — призрак сразу снимается.
## Через эту дверь, а не прямой записью в _ghost_time: начало призрака
## обнуляет фазу мигания и снимает контакты, конец — возвращает их.
func net_set_ghost(active: bool) -> void:
	if active:
		if _ghost_time <= 0.0:
			_start_ghost()
		_ghost_time = maxf(_ghost_time, 0.3)
	elif _ghost_time > 0.0:
		_end_ghost()


## Значок эффекта над машиной: что показывать и как он живёт.
## Два источника: РАЗОВЫЕ эффекты (магнит — его applier зовёт
## show_effect_icon) и ДЛЯЩИЕСЯ (ускорение — читаем прямо _boost_time,
## а не заводим свой таймер: destroy() обнуляет буст, и отдельный таймер
## оставил бы значок висеть над машиной, которую уже отбросило).
## Магнит важнее буста: «по тебе только что применили» — новость.
func _tick_status_icon(delta: float) -> void:
	if _status_icon == null:
		return
	var kind := status_icon_kind()
	# Разовый эффект приоритетнее буста (см. status_icon_kind) — остаток
	# времени берём той же веткой.
	var left := _status_time if _status_time > 0.0 else _boost_time
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
	# От ВИДИМОГО положения машины, а не от тела: тело идёт ступеньками
	# 60 Гц, и значок отрывался бы от машины на каждом кадре рендера.
	_status_icon.global_position = visual_origin() \
			+ Vector3.UP * (height + 0.09 * sin(_status_age * 4.5))
	# «Выпрыгивание» при появлении и затухание в последние 0.3 с.
	var pop: float = clampf(_status_age / 0.16, 0.0, 1.0)
	_status_icon.scale = Vector3.ONE * (1.0 + 0.6 * (1.0 - pop))
	_status_icon.modulate.a = clampf(left / 0.3, 0.0, 1.0)


## Какой значок эффекта действует на машину сейчас (-1 — никакой). БЕЗ
## побочных эффектов: этим же числом СЕРВЕР заполняет снимок
## (Main._pack_state) — у него Sprite3D-значка нет вовсе, и прежняя
## упаковка по _status_shown (обновляется только при живом спрайте)
## означала «по сети значков не видно никому».
func status_icon_kind() -> int:
	if not alive:
		return -1
	if _status_time > 0.0:
		return _status_kind
	if _boost_time > 0.0 and not _boost_from_pad:
		return Weapons.BOOST
	return -1


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


## Глушилка (звуковая волна): на duration секунд лево и право меняются
## местами — руль инвертируется в _drive. Машина едет как ехала, но каждый
## поворот выходит в другую сторону.
## По сети машина живого игрока клиент-авторитетна: рулит её ВЛАДЕЛЕЦ, и
## без пересылки (NetFx.SCRAMBLE) эффекта он бы не почувствовал вовсе.
func apply_scramble(duration: float) -> void:
	if not alive:
		return
	_forward_fx(NetFx.SCRAMBLE, [duration])
	_scramble_time = maxf(_scramble_time, duration)
	show_effect_icon(Weapons.SCRAMBLE, duration)
	FxKit.ring(get_parent(), global_position, 3.0, Color(0.4, 0.95, 1.0))


## Сколько глушилки осталось (стенды и HUD).
func scramble_left() -> float:
	return _scramble_time


## Сколько заморозки осталось. Наружу — для сети: этим числом сервер
## пакует снимок, а владелец докладывает своё состояние (протокол 12).
func freeze_left() -> float:
	return _freeze_time


## Заморозка ПРИЕХАЛА ПО СЕТИ (снимок сервера — Main._rx_state, состояние
## владельца — Main._rx_pstate). Локальный таймер тут не «максимум», а
## ЗАМЕНА: автор состояния один, и его отпустило — значит отпустило.
## Своя машина сюда не попадает (клиент-авторитетна, ей шлют NetFx.FREEZE).
func net_set_freeze(left: float) -> void:
	var was := _freeze_time
	_freeze_time = maxf(0.0, left)
	if _freeze_time > 0.0 and was <= 0.0:
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
	var off := track_offset
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


## Где эта машина находится ПО СЫРЫМ ДАННЫМ её хозяина — для проверок,
## которым важна точность, а не гладкость картинки (подбор боксов).
## У марионетки сервер ведёт СГЛАЖЕННОЕ тело (_follow_snapshot: подтяжка
## с постоянной времени и упреждением), и на поворотах оно уходит вбок от
## настоящего пути на десятки сантиметров. Куб бонуса всего 1.3 м, поэтому
## игрок «задевал куб, а он не подбирался» (жалоба 28.08). Сырое состояние
## владельца такого сдвига не имеет.
func true_position() -> Vector3:
	return _snap_pos if net_role == NetRole.PUPPET and _snap_seen \
			else global_position


## Курс по тем же сырым данным (для «капсулы» кузова при подборе бокса).
func true_forward() -> Vector3:
	var b := Basis(_snap_rot) if net_role == NetRole.PUPPET and _snap_seen \
			else global_transform.basis
	var f := -b.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 1e-6 else Vector3.FORWARD
