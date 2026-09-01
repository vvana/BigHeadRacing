extends Node3D
## Автотест режима «Футбол» (31.08: «режим игры футбол, 8 машинок 4 на 4,
## мяч в чужие ворота, 5 минут»). Фазы:
## 1) сцена строится: 8 машин, СИНИЕ слева (x<0), КРАСНЫЕ справа, мяч в центре;
## 2) мяч в правых воротах → гол СИНИХ, пауза, после неё кикофф (мяч в центре);
## 3) боты играют: за 10 c мяч обязан уехать от центра (макс. смещение);
## 4) бонус, упавший на игрока, выдаёт ему оружие и исчезает (одноразовый),
##    а штатный дождь бонусов успевает запустить хотя бы один;
## 5) мяч, перелетевший борт (лёг за ограждением в паре метров — раньше
##    это была «мёртвая зона» и игра шла без мяча, жалоба 31.08),
##    через ~2 c вбрасывается в центр;
## 6) анти-паровозик (01.09: «двое таранят друг друга и загоняют
##    впередистоящую машинку вместе с мячом сразу в ворота»): чужой кузов
##    на курсе бота к мячу → ai_drive объезжает (руль вбок) и сбрасывает
##    газ, а не давит газ в пол сквозь машину;
## 7) таймер на нуле → матч окончен, управление выключено.

var _soccer: Node3D
var _frame := 0
var _max_disp := 0.0
var _ok_build := false
var _ok_goal := false
var _ok_kickoff := false
var _ok_drop := false
var _ok_out := false
var _ok_train := false


func _ready() -> void:
	_soccer = (load("res://scenes/Soccer.tscn") as PackedScene).instantiate()
	add_child(_soccer)


func _physics_process(_delta: float) -> void:
	_frame += 1
	var ball: SoccerBall = _soccer._ball

	match _frame:
		30:
			var n: int = _soccer._cars.size()
			var sides_ok := true
			for i in n:
				var x: float = (_soccer._cars[i] as Car).global_position.x
				if (i < 4 and x >= 0.0) or (i >= 4 and x <= 0.0):
					sides_ok = false
			_ok_build = n == 8 and sides_ok \
					and ball.global_position.length() < 2.0
			print("[soccer] сцена: машин %d, стороны %s" % [n, str(sides_ok)])
		200:
			# К этому кадру отсчёт давно кончился — игра идёт. Вкатываем мяч
			# в правые ворота руками.
			ball.global_position = Vector3(SoccerArena.HALF_LEN + 2.0, 1.1, 0.0)
			ball.linear_velocity = Vector3(8.0, 0.0, 0.0)
		210:
			_ok_goal = _soccer._score[0] == 1 and _soccer._score[1] == 0 \
					and _soccer._state == _soccer.State.GOAL_PAUSE
			print("[soccer] гол: счёт %s, состояние %d"
					% [str(_soccer._score), _soccer._state])
		420:
			# Пауза после гола 2.8 c (168 кадров) — кикофф уже случился.
			_ok_kickoff = _soccer._state == _soccer.State.PLAY \
					and Vector3(ball.global_position.x, 0,
							ball.global_position.z).length() < 6.0
			print("[soccer] кикофф: состояние %d, мяч %.1f м от центра"
					% [_soccer._state, ball.global_position.length()])
		430:
			# Бонус падает прямо на машину игрока (боты своё оружие могли бы
			# сразу применить — авиаудар/буст, и проверка бы врала).
			var drop := SoccerDrop.new()
			_soccer.add_child(drop)
			drop.global_position = _soccer._car.global_position \
					+ Vector3.UP * 2.0
		500:
			_ok_drop = _soccer._car.weapon >= 0
			var gone := true
			for node: Node in _soccer.get_children():
				if node is SoccerDrop:
					gone = false
			_ok_drop = _ok_drop and gone
			print("[soccer] бонус: оружие %d, куб исчез %s"
					% [_soccer._car.weapon, str(gone)])
		510:
			# Анти-паровозик: нападающему КРАСНЫХ (4) на курс к мячу ставим
			# чужую машину. Старый код давил газ в пол прямо сквозь неё
			# (throttle 1.0, steer 0) — так «двое сцепившихся» и завозили
			# впередистоящего вместе с мячом в ворота.
			var bot: Car = _soccer._cars[4]
			var block: Car = _soccer._cars[1]
			_soccer._escape_time[4] = 0.0
			ball.carrier = null
			ball.global_position = Vector3(4.0, SoccerBall.RADIUS, 0.0)
			ball.linear_velocity = Vector3.ZERO
			bot.global_transform = Transform3D(
					Basis.looking_at(Vector3(-1, 0, 0)), Vector3(10.0, 0.6, 0.0))
			bot.linear_velocity = Vector3.ZERO
			block.global_transform = Transform3D(
					Basis.looking_at(Vector3(-1, 0, 0)), Vector3(6.5, 0.6, 0.0))
			block.linear_velocity = Vector3.ZERO
			var cmd: Vector2 = _soccer.ai_drive(bot)
			_ok_train = cmd.x <= 0.5 and absf(cmd.y) > 0.3
			print("[soccer] анти-паровозик: газ %.2f, руль %.2f (%s)"
					% [cmd.x, cmd.y, "ok" if _ok_train else "FAIL"])
		700:
			# Мяч «перелетел борт»: лёг на газон в 3 м ЗА боковым ограждением.
			# На старом коде он лежал там до конца матча (возврат срабатывал
			# только за 6 м ЗА ареной).
			ball.global_position = Vector3(0.0, SoccerBall.RADIUS + 0.1,
					SoccerArena.HALF_WID + 3.0)
			ball.linear_velocity = Vector3.ZERO
		870:
			# 2 c вне игры (120 кадров) прошли — мяч обязан вернуться в поле.
			var bp := ball.global_position
			_ok_out = absf(bp.z) <= SoccerArena.HALF_WID \
					and absf(bp.x) <= SoccerArena.HALF_LEN
			print("[soccer] вылет за борт: мяч в поле %s (%.1f, %.1f)"
					% [str(_ok_out), bp.x, bp.z])
		1020:
			# Боты играли ~10 c — мяч не должен был стоять. Дальше — конец
			# матча по таймеру.
			_soccer._time_left = 0.2
		1250:
			var over: bool = _soccer._state == _soccer.State.OVER
			var stopped := true
			for c: Car in _soccer._cars:
				if c.controls_enabled:
					stopped = false
			var ai_ok := _max_disp > 5.0
			var rain_ok: bool = _soccer._drops_spawned >= 1
			var ok := _ok_build and _ok_goal and _ok_kickoff and ai_ok \
					and _ok_drop and rain_ok and _ok_out and _ok_train \
					and over and stopped
			print("SOCCER TEST: %s (сцена=%s, гол=%s, кикофф=%s, "
					% ["PASS" if ok else "FAIL", str(_ok_build),
						str(_ok_goal), str(_ok_kickoff)]
					+ "боты сдвинули мяч на %.1f м, бонус=%s, дождь=%d, "
					% [_max_disp, str(_ok_drop), _soccer._drops_spawned]
					+ "вылет=%s, паровозик=%s, финал=%s, стоп=%s)"
					% [str(_ok_out), str(_ok_train), str(over), str(stopped)])
			get_tree().quit(0 if ok else 1)

	# Макс. уход мяча от центра в окне игры ботов (фаза 3). Окно после
	# кикоффа: голы ботов в нём легальны (мяч вернётся в центр — поэтому
	# меряем МАКСИМУМ, а не положение в конце).
	if _frame > 420 and _frame < 1020:
		_max_disp = maxf(_max_disp, Vector3(ball.global_position.x, 0.0,
				ball.global_position.z).length())
