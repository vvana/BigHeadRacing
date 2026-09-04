extends Node3D
## Режим «ФУТБОЛ»: 8 машин, 4 на 4, мяч нужно загнать в чужие ворота,
## матч 5 минут. Пока ТОЛЬКО оффлайн: игрок в команде СИНИХ + 7 ботов
## (сетевой футбол потребует нового протокола — см. план в PROGRESS.md).
## Оружие — из БОНУСОВ: они периодически падают с неба в случайные точки
## поля (SoccerDrop, одноразовые), стартуют все с пустыми руками.

const TEAM_SIZE := 4
const CAR_COUNT := 8
const MATCH_TIME := 300.0     # 5 минут
const GOAL_PAUSE := 2.8      # пауза-празднование после гола, с
const TEAM_NAMES := ["СИНИЕ", "КРАСНЫЕ"]

enum State { COUNTDOWN, PLAY, GOAL_PAUSE, OVER }

var _arena: SoccerArena
var _ball: SoccerBall
var _cars: Array[Car] = []
var _car: Car               # машина игрока (индекс 0, команда СИНИХ)
var _state := State.COUNTDOWN
var _score := [0, 0]
var _time_left := MATCH_TIME
var _pause_left := 0.0
var _player_goals := 0
var _last_minute_said := false
var _flip_time: Array[float] = []
# Имена по машинам: игрок — из профиля, боты — ники PlayerNames (анонсы
# голов подписываются ими — бот неотличим от живого игрока, 01.09).
var _names := PackedStringArray()

## Мяч вне игры (перелетел борт, застрял на крыше ворот): столько секунд
## вне игрового объёма — и вбрасывание в центре. Пара секунд, чтобы не
## дёргать мяч, честно скачущий по верхней кромке борта.
const BALL_OUT_TIME := 2.0
var _ball_out_time := 0.0

## Застревание ботов у стен/ворот (жалоба 31.08: «упираются и больше
## ничего не делают»): бот, который ХОЧЕТ ехать (_want_move из ai_drive),
## но стоит на месте дольше STUCK_TIME, на ESCAPE сдаёт назад, доворачивая
## нос на мяч, — и дальше едет как обычно.
const STUCK_TIME := 1.1       # сколько секунд стоим «в упоре», с
const STUCK_SPEED := 1.2      # ниже этой скорости считаем, что стоим, м/с
var _stuck_time: Array[float] = []
var _escape_time: Array[float] = []
var _want_move: Array[bool] = []

var _focus: Focus           # точка между игроком и мячом — цель камеры
var _ball_marker: Node3D
var _player_marker: Node3D
var _marker_time := 0.0

## Бонусы с оружием: падают с неба в случайные точки поля.
const DROP_FIRST := 4.0       # первый бонус после старта, с
const DROP_PERIOD_MIN := 6.0
const DROP_PERIOD_MAX := 11.0
const DROP_MAX := 4           # больше на поле одновременно не держим
var _drop_timer := DROP_FIRST
var _drops_spawned := 0
var _fire_cd: Array[float] = []   # откаты стрельбы ботов

var _score_label: Label
var _timer_label: Label
var _speed_label: Label
var _count_label: Label
var _end_label: Label
var _weapon_icon: TextureRect
var _weapon_name: Label
var _slot_empty_tex: Texture2D
var _last_weapon := -2
var _announcer: Announcer


## Камере нужен target с visual_origin(): держим точку между машиной и мячом,
## чтобы в кадре были оба (сам мяч может укатиться за экран).
class Focus extends Node3D:
	var point := Vector3.ZERO
	func visual_origin() -> Vector3:
		return point


func _ready() -> void:
	Music.play_race()
	_setup_environment()
	_arena = SoccerArena.new()
	_arena.name = "Arena"
	add_child(_arena)

	_ball = SoccerBall.new()
	_ball.name = "Ball"
	add_child(_ball)
	_ball.global_position = _arena.ball_spawn()

	_spawn_cars()

	_focus = Focus.new()
	add_child(_focus)
	_focus.point = _car.global_position
	var cam := IsoCamera.new()
	cam.name = "IsoCamera"
	cam.ortho_size = 30.0
	cam.target = _focus
	add_child(cam)
	cam.make_current()

	_setup_hud()
	_countdown()


func _setup_environment() -> void:
	# Дневное небо, как на травяной трассе (Main._setup_environment).
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.55, 0.87)
	sky_mat.sky_horizon_color = Color(0.74, 0.85, 0.95)
	sky_mat.ground_horizon_color = Color(0.74, 0.85, 0.95)
	sky_mat.ground_bottom_color = Color(0.28, 0.4, 0.24)
	sky_mat.sun_angle_max = 15.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.65, 0.67, 0.72)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)


func _spawn_cars() -> void:
	var ids := _pick_car_ids()
	for i in CAR_COUNT:
		var car := Car.new()
		car.is_player = i == 0
		car.name = "Car%d" % i
		car.race = self        # авиаудар (leader_car) и анонсы попаданий
		car.weapon = -1        # стартуем без оружия — оно из бонусов
		# Тюнинг косметический — характеристики игрока стоковые (03.09).
		if i != 0:
			car.soccer_brain = self
			car.max_speed += randf_range(-1.0, 1.0)
			car.engine_power += randf_range(-6.0, 6.0)
			car.ai_rubber = randf_range(0.9, 0.99)   # боты чуть медленнее
		car.transform = _arena.kickoff_car(i)
		add_child(car)
		_set_car_model(car, ids[i])
		_attach_team_ring(car, 0 if i < TEAM_SIZE else 1)
		_cars.append(car)
		_flip_time.append(0.0)
		_fire_cd.append(randf_range(1.5, 3.0))
		_stuck_time.append(0.0)
		_escape_time.append(0.0)
		_want_move.append(false)
	# Имена: игрок (слот 0) — своё из профиля, боты — человеческие ники
	# (PlayerNames): в анонсах голов бот выглядит как живой игрок.
	_names = PlayerNames.pick(_cars.size())
	_names[0] = GameState.display_name()
	_car = _cars[0]
	if not Net.is_server():
		_player_marker = _build_cone_marker(Color(0.15, 0.95, 0.25))
		_car.add_child(_player_marker)
		_player_marker.global_position = _car.global_position + Vector3.UP * 2.4
		_ball_marker = _build_cone_marker(Color(1.0, 0.85, 0.2))
		_ball.add_child(_ball_marker)
		_ball_marker.global_position = _ball.global_position + Vector3.UP * 2.6


## Модели: у игрока — выбранная в гараже, у ботов — случайные другие.
func _pick_car_ids() -> PackedStringArray:
	# Пул — полные id скинов (случайный цвет на машину); повторы
	# отсекаются по базе (см. Main._pick_car_ids).
	var pool := CarModelLibrary.shuffled_bot_pool()
	var res := PackedStringArray()
	var used := {}
	res.append(GameState.selected_car_id)
	used[CarModelLibrary.base_id(GameState.selected_car_id)] = true
	for id: String in pool:
		if res.size() >= CAR_COUNT:
			break
		var base := CarModelLibrary.base_id(id)
		if not used.has(base):
			res.append(id)
			used[base] = true
	return res


func _set_car_model(car: Car, id: String) -> void:
	if Net.is_server():
		return
	var model := CarModelLibrary.build(id)
	if model:
		model.name = "CarModel"
		car.add_child(model)
		car.collect_wheels(model)
	car.apply_fx(id)   # цвет дыма/пламени из тюнинга; неон — в модели


## Цветное кольцо команды под машиной: свой/чужой виден с одного взгляда.
func _attach_team_ring(car: Car, team: int) -> void:
	if Net.is_server():
		return
	var ring := MeshInstance3D.new()
	ring.name = "TeamRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 1.45
	torus.outer_radius = 1.75
	ring.mesh = torus
	ring.scale.y = 0.12
	ring.position.y = 0.12
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var col := SoccerArena.TEAM_COLORS[team]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = col * 0.6
	ring.material_override = mat
	car.add_child(ring)


## Конус-указатель (как маркер игрока в гонке): top_level, ставится в _process.
func _build_cone_marker(color: Color) -> Node3D:
	var marker := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.34
	cone.bottom_radius = 0.0
	cone.height = 0.6
	marker.mesh = cone
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color * 0.85
	marker.material_override = mat
	marker.top_level = true
	return marker


func _countdown() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	if _count_label:
		_count_label.visible = true
	for txt in ["3", "2", "1"]:
		_pop_count(txt, UiKit.YELLOW)
		await get_tree().create_timer(0.8).timeout
		if not is_inside_tree():
			return
	_pop_count("GO!", UiKit.TEAL)
	_set_controls(true)
	_state = State.PLAY
	await get_tree().create_timer(0.7).timeout
	if is_inside_tree() and _count_label:
		_count_label.visible = false


func _pop_count(txt: String, color: Color) -> void:
	if _count_label == null:
		return
	_count_label.text = txt
	_count_label.add_theme_color_override("font_color", color)
	_count_label.pivot_offset = _count_label.size * 0.5
	_count_label.scale = Vector2(1.6, 1.6)
	var tw := _count_label.create_tween()
	tw.tween_property(_count_label, "scale", Vector2.ONE, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_controls(on: bool) -> void:
	for c in _cars:
		c.controls_enabled = on


func _physics_process(delta: float) -> void:
	_focus_camera()
	match _state:
		State.PLAY:
			_time_left = maxf(0.0, _time_left - delta)
			if _time_left <= 60.0 and not _last_minute_said:
				_last_minute_said = true
				if _announcer:
					_announcer.big("ПОСЛЕДНЯЯ МИНУТА", "", "orange")
			if _time_left <= 0.0:
				_finish_match()
				return
			var scored := _arena.goal_at(_ball.global_position)
			if scored >= 0:
				_on_goal(scored)
				return
			_check_recovery(delta)
			_tick_stuck(delta)
			_tick_drops(delta)
			_tick_bot_weapons(delta)
		State.GOAL_PAUSE:
			_pause_left -= delta
			if _pause_left <= 0.0:
				_kickoff()
		_:
			pass


## Цель камеры: между игроком и мячом, с перевесом к игроку.
func _focus_camera() -> void:
	if _car == null or _ball == null:
		return
	_focus.point = _car.visual_origin().lerp(_ball.visual_origin(), 0.38)


func _on_goal(team: int) -> void:
	_score[team] += 1
	_state = State.GOAL_PAUSE
	_pause_left = GOAL_PAUSE
	_set_controls(false)
	_update_score()

	var scorer := _ball.last_touch
	var sub := ""
	if scorer != null:
		var si := _cars.find(scorer)
		if si >= 0:
			var scorer_team := 0 if si < TEAM_SIZE else 1
			# Автор гола — по имени (бот подписан ником, как живой игрок).
			var scorer_name: String = "вы" if si == 0 else _names[si]
			if scorer_team != team:
				sub = "автогол! (%s)" % scorer_name
			else:
				sub = "забил: %s" % scorer_name
				if si == 0:
					_player_goals += 1
	if _announcer:
		_announcer.big("ГОЛ! Счёт %d : %d" % [_score[0], _score[1]], sub,
				"teal" if team == 0 else "red")
	FxKit.confetti_burst(self, _ball.global_position + Vector3.UP * 2.0)


## Возврат к кикоффу после гола: все по местам, мяч в центр, сразу игра.
func _kickoff() -> void:
	for i in _cars.size():
		_respawn_car(i)
	_ball.reset_to(_arena.ball_spawn())
	_set_controls(true)
	_state = State.PLAY
	if _announcer:
		_announcer.small("ИГРА!")


func _respawn_car(i: int) -> void:
	var car := _cars[i]
	car.transform = _arena.kickoff_car(i)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_speed_memory()
	car.net_visual_reset()
	_flip_time[i] = 0.0
	_stuck_time[i] = 0.0
	_escape_time[i] = 0.0


## Страховка: перевёрнутую машину (2.5 с кверху колёсами), упавшую под
## арену или улетевшую за газон возвращаем на её кикофф-точку.
func _check_recovery(delta: float) -> void:
	for i in _cars.size():
		var car := _cars[i]
		# Пауза появления после взрыва: машины нет, возвращать нечего.
		if car.is_respawning():
			_flip_time[i] = 0.0
			continue
		var pos := car.global_position
		var out: bool = pos.y < -2.0 \
				or absf(pos.x) > SoccerArena.HALF_LEN + SoccerArena.GOAL_DEPTH + 10.0 \
				or absf(pos.z) > SoccerArena.HALF_WID + 10.0
		if out:
			_respawn_car(i)
			continue
		if car.global_transform.basis.y.y < 0.2:
			_flip_time[i] += delta
			if _flip_time[i] > 2.5:
				_respawn_car(i)
		else:
			_flip_time[i] = 0.0
	# Мяч вне игры: перелетел борт (лёг на газон ЗА ограждением, куда
	# машинам не доехать), застрял на крыше короба ворот или провалился
	# под пол. Раньше возврат срабатывал только за 6 м ЗА ареной — мяч в
	# паре метров за бортом попадал в «мёртвую зону» (земля тянется шире
	# арены) и лежал там до конца матча (жалоба 31.08). Правило теперь
	# прямое: НЕ в игровом объёме (поле в бортах или короб ворот) дольше
	# BALL_OUT_TIME — вбрасывание в центр. Провалился под пол — сразу.
	var bp := _ball.global_position
	var fell := bp.y < -1.0
	var in_field: bool = not fell \
			and absf(bp.x) <= SoccerArena.HALF_LEN \
			and absf(bp.z) <= SoccerArena.HALF_WID
	var in_goal: bool = not fell \
			and absf(bp.x) <= SoccerArena.HALF_LEN + SoccerArena.GOAL_DEPTH \
			and absf(bp.z) <= SoccerArena.GOAL_HALF_W \
			and bp.y <= SoccerArena.GOAL_H
	if in_field or in_goal:
		_ball_out_time = 0.0
	else:
		_ball_out_time += BALL_OUT_TIME if fell else delta
		if _ball_out_time >= BALL_OUT_TIME:
			_ball_out_time = 0.0
			_ball.reset_to(_arena.ball_spawn())
			if _announcer:
				_announcer.small("Мяч вылетел — вбрасывание в центре")


func _finish_match() -> void:
	_state = State.OVER
	_time_left = 0.0
	_set_controls(false)
	for c in _cars:
		c.race_over = true   # плавное торможение, как после финиша гонки
	_update_score()

	var title: String
	var kind: String
	var xp: int
	var coins: int   # монеты за матч — победа как 1-е место гонки не платит:
	                 # футбол короче и без риска быть уничтоженным
	if _score[0] > _score[1]:
		title = "ПОБЕДА СИНИХ %d : %d" % [_score[0], _score[1]]
		kind = "teal"
		xp = 100
		coins = 500
	elif _score[0] < _score[1]:
		title = "ПОБЕДА КРАСНЫХ %d : %d" % [_score[1], _score[0]]
		kind = "red"
		xp = 20
		coins = 200
	else:
		title = "НИЧЬЯ %d : %d" % [_score[0], _score[1]]
		kind = "orange"
		xp = 40
		coins = 300
	xp += _player_goals * 15
	coins += _player_goals * 50
	GameState.add_money(coins)
	GameState.add_xp(xp)
	if _announcer:
		_announcer.big(title, "опыт +%d  ·  монеты +%d" % [xp, coins], kind)
	if _end_label:
		_end_label.visible = true


## Детектор упора: бот хочет ехать (см. _want_move), а скорости нет —
## значит, упёрся в борт, штангу или сетку ворот. Через STUCK_TIME даём
## ему ESCAPE: ai_drive на это время сдаёт назад. Вратарь, штатно
## стоящий на позиции, сюда не попадает — он ехать не хочет.
func _tick_stuck(delta: float) -> void:
	for i in range(1, _cars.size()):
		if _escape_time[i] > 0.0:
			_escape_time[i] -= delta
			continue
		var car := _cars[i]
		if _want_move[i] and car.controls_enabled and car.alive \
				and car.linear_velocity.length() < STUCK_SPEED:
			_stuck_time[i] += delta
			if _stuck_time[i] > STUCK_TIME:
				_stuck_time[i] = 0.0
				_escape_time[i] = randf_range(0.8, 1.3)
		else:
			_stuck_time[i] = 0.0


## ---- Бонусы с оружием ----

## Раз в DROP_PERIOD на поле падает золотой куб-бонус (просьба 31.08:
## «периодически на поле падают бонусы в случайное место, подбираешь и
## получаешь оружие»). Точка случайная, но не вплотную к бортам и воротам.
func _tick_drops(delta: float) -> void:
	_drop_timer -= delta
	if _drop_timer > 0.0:
		return
	_drop_timer = randf_range(DROP_PERIOD_MIN, DROP_PERIOD_MAX)
	var live := 0
	for node in get_children():
		if node is SoccerDrop:
			live += 1
	if live >= DROP_MAX:
		return
	var drop := SoccerDrop.new()
	add_child(drop)
	drop.position = Vector3(
			randf_range(-SoccerArena.HALF_LEN + 8.0, SoccerArena.HALF_LEN - 8.0),
			0.0,
			randf_range(-SoccerArena.HALF_WID + 5.0, SoccerArena.HALF_WID - 5.0))
	drop.position.y = SoccerDrop.GROUND_Y + drop.fall_from
	_drops_spawned += 1


## ---- Крючки Car (машины держат race = этот узел) ----

## «Лидер» для авиаудара: в футболе это машина, владеющая мячом, —
## ближайшая к нему.
func leader_car() -> Car:
	var best: Car = _cars[0]
	var best_d := 1e9
	for c in _cars:
		if not c.alive:
			continue
		var d := c.global_position.distance_to(_ball.global_position)
		if d < best_d:
			best_d = d
			best = c
	return best


## Попадание оружием: игроку объясняем, что с ним случилось (в гонке это
## делает лента событий Main — здесь достаточно короткого анонса).
func report_weapon_hit(_attacker: Car, victim: Car, kind: int) -> void:
	if victim != _car or _announcer == null:
		return
	match kind:
		Weapons.SCRAMBLE:
			_announcer.small("Управление сбито: лево и право поменялись!", "red")
		Weapons.FREEZE:
			_announcer.small("Вас заморозили!", "teal")
		Weapons.MAGNET:
			_announcer.small("Вас притянуло магнитом!", "steel")


## Боты применяют подобранное оружие: прицельное — по сопернику в конусе
## перед носом, мину/масло — под соперника сзади, магнит — по ближнему,
## авиаудар и буст — сразу. Своих ботам жалко только прицельно: конус
## смотрит на ЧУЖИХ (случайные жертвы разлёта — как в гонке, часть хаоса).
func _tick_bot_weapons(delta: float) -> void:
	for i in range(1, _cars.size()):
		_fire_cd[i] -= delta
		if _fire_cd[i] > 0.0:
			continue
		_fire_cd[i] = randf_range(1.6, 3.2)
		var car := _cars[i]
		if car.weapon < 0 or not car.alive or car.is_ghost():
			continue
		var team := 0 if i < TEAM_SIZE else 1
		match car.weapon:
			Weapons.ROCKET, Weapons.LASER, Weapons.FREEZE, Weapons.SCRAMBLE:
				if _enemy_ahead_of(car, team):
					car.use_weapon()
			Weapons.MINE, Weapons.OIL:
				if _enemy_behind_of(car, team) and randf() < 0.6:
					car.use_weapon()
			Weapons.MAGNET:
				if _nearest_enemy_dist(car, team) < 14.0:
					car.use_weapon()
			Weapons.AIRSTRIKE:
				car.use_weapon()
			Weapons.BOOST:
				car.use_weapon()


func _enemy_cars(team: int) -> Array[Car]:
	var res: Array[Car] = []
	var from := TEAM_SIZE if team == 0 else 0
	for k in TEAM_SIZE:
		var c := _cars[from + k]
		if c.alive and not c.is_ghost():
			res.append(c)
	return res


## Соперник в конусе ~22° перед носом, не дальше 30 м (как ИИ гонки).
func _enemy_ahead_of(car: Car, team: int) -> bool:
	var fwd := -car.global_transform.basis.z
	fwd.y = 0.0
	for e in _enemy_cars(team):
		var to := e.global_position - car.global_position
		to.y = 0.0
		var d := to.length()
		if d < 1.0 or d > 30.0:
			continue
		if fwd.angle_to(to) < deg_to_rad(22.0):
			return true
	return false


func _enemy_behind_of(car: Car, team: int) -> bool:
	var back := car.global_transform.basis.z
	back.y = 0.0
	for e in _enemy_cars(team):
		var to := e.global_position - car.global_position
		to.y = 0.0
		var d := to.length()
		if d < 12.0 and back.angle_to(to) < deg_to_rad(45.0):
			return true
	return false


func _nearest_enemy_dist(car: Car, team: int) -> float:
	var best := 1e9
	for e in _enemy_cars(team):
		best = minf(best, car.global_position.distance_to(e.global_position))
	return best


## ---- ИИ ботов: вызывается из Car._ai_control (soccer_brain) ----
## Возвращает Vector2(газ, руль). Роли в команде: 0 — нападающий (у СИНИХ
## это игрок, бот-нападающий только у КРАСНЫХ), 1-2 — фланги, 3 — вратарь.
func ai_drive(car: Car) -> Vector2:
	var i := _cars.find(car)
	if i < 0 or _ball == null:
		return Vector2.ZERO
	var team := 0 if i < TEAM_SIZE else 1
	var role := i % TEAM_SIZE
	var bpos := _ball.global_position
	var own_goal := _arena.goal_center(team)
	var enemy_goal := _arena.goal_center(1 - team)

	# Выезд из упора: сдаём назад, доворачивая нос на мяч (руль на заднем
	# ходу зеркалится в _drive сам). Дальше бот едет как обычно.
	if _escape_time[i] > 0.0:
		var to_ball := bpos - car.global_position
		to_ball.y = 0.0
		var fwd_e := -car.global_transform.basis.z
		fwd_e.y = 0.0
		var ang_e := fwd_e.signed_angle_to(to_ball, Vector3.UP)
		return Vector2(-1.0, -signf(ang_e))

	var target := bpos
	var attack := false
	var ram_target: Car = null   # чужой ведущий мяча: его таранить МОЖНО
	match role:
		0:
			attack = true
		1, 2:
			# Фланг атакует, когда мяч на его стороне поля (или у оси),
			# иначе держит позицию между своими воротами и мячом.
			var side := -1.0 if role == 1 else 1.0
			if signf(bpos.z) == side or absf(bpos.z) < 5.0:
				attack = true
			else:
				target = Vector3(lerpf(own_goal.x, bpos.x, 0.55), 0.0,
						side * 11.0)
		3:
			# Вратарь: держит створ, выбивает мяч, когда тот подъехал.
			if bpos.distance_to(own_goal) < 20.0:
				attack = true
			else:
				target = Vector3(own_goal.x - signf(own_goal.x) * 4.0, 0.0,
						clampf(bpos.z, -SoccerArena.GOAL_HALF_W + 1.5,
								SoccerArena.GOAL_HALF_W - 1.5))

	if attack:
		var dir := enemy_goal - bpos
		dir.y = 0.0
		dir = dir.normalized()
		var holder: Car = _ball.carrier
		var hi := _cars.find(holder) if holder != null else -1
		if holder == car:
			# Сам веду мяч — просто везём его в чужие ворота.
			target = enemy_goal
		elif hi >= 0 and (0 if hi < TEAM_SIZE else 1) == team:
			# Мяч ведёт СВОЙ: в корму его не таранить (паровозик заталкивал
			# впередистоящего вместе с мячом прямо в ворота — жалоба 01.09),
			# едем эскортом сбоку-впереди по ходу атаки.
			var eperp := Vector3(-dir.z, 0.0, dir.x)
			var eside := signf(
					(car.global_position - holder.global_position).dot(eperp))
			if eside == 0.0:
				eside = 1.0 if role % 2 == 0 else -1.0
			target = holder.global_position + dir * 9.0 + eperp * eside * 7.0
		elif hi >= 0:
			# Мяч ведёт ЧУЖОЙ: цель — САМ ведущий (любой удар по нему
			# отлипляет мяч), а не мяч у его носа: погоня за мячом сзади
			# ведущего и была тараном в корму с мячом впереди.
			ram_target = holder
			target = holder.global_position
		# Мы «за мячом» (мяч между нами и чужими воротами)? Тогда толкаем
		# сквозь него. Иначе объезжаем: точка позади мяча со смещением вбок,
		# чтобы не запихнуть мяч в свои ворота.
		elif (bpos - car.global_position).dot(dir) > 0.0:
			target = bpos + dir * 1.5
		else:
			var perp := Vector3(-dir.z, 0.0, dir.x)
			var side_of := signf((car.global_position - bpos).dot(perp))
			if side_of == 0.0:
				side_of = 1.0
			target = bpos - dir * 6.0 + perp * side_of * 5.5

	# Цель — только ВНУТРИ поля: точка «позади мяча» у борта или в створе
	# ворот иначе оказывается ЗА стеной, и бот таранит её до бесконечности.
	target.x = clampf(target.x,
			-SoccerArena.HALF_LEN + 3.0, SoccerArena.HALF_LEN - 3.0)
	target.z = clampf(target.z,
			-SoccerArena.HALF_WID + 3.0, SoccerArena.HALF_WID - 3.0)

	# Чужой кузов на курсе ближе цели — ОБЪЕЗЖАЕМ сбоку, а не толкаем перед
	# собой (жалоба 01.09: «двое таранят друг друга и загоняют
	# впередистоящую машинку вместе с мячом сразу в ворота»). Чужого
	# ведущего мяч (ram_target) таранить можно — это перехват.
	var blocker := _car_blocking(car, target, ram_target)
	if blocker != null:
		var bto := target - car.global_position
		bto.y = 0.0
		if bto.length_squared() > 1e-4:
			var bdir := bto.normalized()
			var bperp := Vector3(-bdir.z, 0.0, bdir.x)
			var bside := signf(
					(car.global_position - blocker.global_position).dot(bperp))
			if bside == 0.0:
				bside = 1.0
			target = blocker.global_position + bperp * bside * 5.0
			target.x = clampf(target.x,
					-SoccerArena.HALF_LEN + 3.0, SoccerArena.HALF_LEN - 3.0)
			target.z = clampf(target.z,
					-SoccerArena.HALF_WID + 3.0, SoccerArena.HALF_WID - 3.0)

	var to := target - car.global_position
	to.y = 0.0
	var dist := to.length()
	var fwd := -car.global_transform.basis.z
	fwd.y = 0.0
	var angle := fwd.signed_angle_to(to, Vector3.UP)
	# Цель за спиной вплотную, скорости нет — быстрее развернуться задним
	# ходом (руль на заднем ходу зеркалится в _drive сам).
	if absf(angle) > 2.2 and dist < 9.0 and car.linear_velocity.length() < 4.0:
		_want_move[i] = true
		return Vector2(-1.0, -signf(angle))
	var steer := clampf(angle * 2.0, -1.0, 1.0)
	var throttle := 1.0
	if absf(angle) > 1.1:
		throttle = 0.35
	if not attack and dist < 3.5:
		throttle = clampf(dist / 3.5 - 0.25, -0.2, 1.0)
	# Вплотную к объезжаемому кузову газ сброшен: даже если нос ещё не
	# довернулся в объезд, вагоном паровозика не работаем.
	if blocker != null and car.global_position.distance_to(
			blocker.global_position) < 4.5:
		throttle = minf(throttle, 0.4)
	_want_move[i] = absf(throttle) > 0.3
	return Vector2(throttle, steer)


## Живой кузов (кроме ignore) в узком коридоре по курсу к цели: ближе неё,
## не дальше 7 м, боковой промах меньше пары корпусов — кандидат стать
## «вагоном» паровозика, его надо объезжать, а не толкать.
func _car_blocking(car: Car, target: Vector3, ignore: Car) -> Car:
	var to := target - car.global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 1.0:
		return null
	var dir := to / dist
	var best: Car = null
	var best_d := minf(dist - 0.5, 7.0)
	for c in _cars:
		if c == car or c == ignore or not c.alive or c.is_ghost():
			continue
		var toc := c.global_position - car.global_position
		toc.y = 0.0
		var along := toc.dot(dir)
		if along <= 0.5 or along >= best_d:
			continue
		if (toc - dir * along).length() < 2.4:
			best = c
			best_d = along
	return best


## ---- HUD и ввод ----

func _process(delta: float) -> void:
	_marker_time += delta
	var bob := 2.4 + 0.12 * sin(_marker_time * 3.0)
	if _player_marker and _car != null:
		_player_marker.global_position = _car.visual_origin() + Vector3.UP * bob
	if _ball_marker and _ball != null:
		_ball_marker.global_position = _ball.visual_origin() \
				+ Vector3.UP * (bob + 0.4)
	if _speed_label and _car != null:
		_speed_label.text = str(int(_car.speed_kmh()))
		if _car.weapon != _last_weapon:
			_last_weapon = _car.weapon
			if _car.weapon >= 0:
				_weapon_icon.texture = Weapons.icon(_car.weapon)
				_weapon_name.text = Weapons.display_name(_car.weapon)
			else:
				_weapon_icon.texture = _slot_empty_tex
				_weapon_name.text = "лови бонус"
	if _timer_label:
		var t := int(ceilf(_time_left))
		_timer_label.text = "%d:%02d" % [t / 60, t % 60]

	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/CarSelect.tscn")
		return
	if _state == State.OVER and Input.is_action_just_pressed("ui_accept"):
		get_tree().change_scene_to_file("res://scenes/CarSelect.tscn")
		return
	if _state == State.PLAY and Input.is_action_just_pressed("respawn"):
		_respawn_car(0)


func _update_score() -> void:
	if _score_label:
		_score_label.text = "%d : %d" % [_score[0], _score[1]]


func _setup_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	# Табло по центру сверху: СИНИЕ 0 : 0 КРАСНЫЕ.
	var plate := UiKit.plate(canvas, "steel", Vector2.ZERO, Vector2(380, 64))
	plate.anchor_left = 0.5
	plate.anchor_right = 0.5
	plate.offset_left = -190
	plate.offset_right = 190
	plate.offset_top = 12
	plate.offset_bottom = 76

	var blue := UiKit.label(plate, TEAM_NAMES[0], 20,
			SoccerArena.TEAM_COLORS[0].lightened(0.3), 5)
	blue.position = Vector2(14, 0)
	blue.size = Vector2(110, 64)
	blue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blue.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_score_label = UiKit.label(plate, "0 : 0", 30, Color.WHITE, 6)
	_score_label.position = Vector2(124, 0)
	_score_label.size = Vector2(132, 64)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var red := UiKit.label(plate, TEAM_NAMES[1], 20,
			SoccerArena.TEAM_COLORS[1].lightened(0.25), 5)
	red.position = Vector2(256, 0)
	red.size = Vector2(110, 64)
	red.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	red.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Таймер матча под табло.
	_timer_label = UiKit.label(canvas, "5:00", 26, UiKit.YELLOW, 6)
	_timer_label.anchor_left = 0.5
	_timer_label.anchor_right = 0.5
	_timer_label.offset_left = -60
	_timer_label.offset_right = 60
	_timer_label.offset_top = 80
	_timer_label.offset_bottom = 112
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Скорость — слева внизу, как в гонке.
	var speed_plate := UiKit.plate(canvas, "steel", Vector2.ZERO,
			Vector2(150, 64))
	speed_plate.anchor_top = 1.0
	speed_plate.anchor_bottom = 1.0
	speed_plate.offset_left = 16
	speed_plate.offset_right = 166
	speed_plate.offset_top = -80
	speed_plate.offset_bottom = -16
	_speed_label = UiKit.label(speed_plate, "0", 30, Color.WHITE, 6)
	_speed_label.position = Vector2(10, 0)
	_speed_label.size = Vector2(84, 64)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var kmh := UiKit.label(speed_plate, "км/ч", 14, Color(1, 1, 1, 0.7))
	kmh.position = Vector2(94, 0)
	kmh.size = Vector2(50, 64)
	kmh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Слот оружия над скоростью (как в гонке, только у левого края).
	_slot_empty_tex = load("res://assets/ui/garage/slot_empty.png")
	_weapon_icon = TextureRect.new()
	_weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weapon_icon.anchor_top = 1.0
	_weapon_icon.anchor_bottom = 1.0
	_weapon_icon.offset_left = 40
	_weapon_icon.offset_right = 136
	_weapon_icon.offset_top = -210
	_weapon_icon.offset_bottom = -114
	_weapon_icon.texture = _slot_empty_tex
	canvas.add_child(_weapon_icon)
	_weapon_name = UiKit.label(canvas, "лови бонус", 14, UiKit.YELLOW, 4)
	_weapon_name.anchor_top = 1.0
	_weapon_name.anchor_bottom = 1.0
	_weapon_name.offset_left = 16
	_weapon_name.offset_right = 160
	_weapon_name.offset_top = -112
	_weapon_name.offset_bottom = -90
	_weapon_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Отсчёт 3-2-1-GO по центру.
	_count_label = UiKit.label(canvas, "", 96, UiKit.YELLOW, 10)
	_count_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.visible = false

	# «Enter — в гараж» после финального свистка.
	_end_label = UiKit.label(canvas, "Enter — в гараж", 22, Color.WHITE, 6)
	_end_label.anchor_left = 0.5
	_end_label.anchor_right = 0.5
	_end_label.anchor_top = 0.62
	_end_label.anchor_bottom = 0.62
	_end_label.offset_left = -160
	_end_label.offset_right = 160
	_end_label.offset_bottom = 30
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_label.visible = false

	var help := UiKit.label(canvas,
			"WASD/стрелки — езда  |  Ctrl/J — оружие  |  Shift — прыжок  |  Space — ручник  |  R — на место  |  Esc — в гараж",
			14, Color(1, 1, 1, 0.7))
	help.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.position.y = -30
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_announcer = Announcer.new()
	canvas.add_child(_announcer)
