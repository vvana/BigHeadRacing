extends Node3D
## Стенд жалобы 31.08: «в режиме футбол боты иногда упираются в ворота или
## стены и больше ничего не делают». Воспроизводим упор: мяч кладётся
## вплотную к торцевому борту, бот-нападающий КРАСНЫХ ставится носом в этот
## борт (его цель «позади мяча» на старом коде оказывалась ЗА стеной — он
## таранил её до бесконечности). Остальным машинам управление выключаем,
## чтобы никто не выбил мяч и не растолкал сцену.
## PASS: бот не стоит в упоре дольше STALL_LIMIT подряд и за окно замера
## успевает отъехать от точки упора хотя бы на 4 м.

const STALL_LIMIT := 3.5 * 60   # кадров подряд со скоростью < STALL_SPEED
const STALL_SPEED := 0.8

var _soccer: Node3D
var _bot: Car
var _frame := 0
var _pin := Vector3.ZERO       # где бота прижали к стене
var _stall := 0                # текущая серия «стоим»
var _worst_stall := 0
var _max_move := 0.0


func _ready() -> void:
	_soccer = (load("res://scenes/Soccer.tscn") as PackedScene).instantiate()
	add_child(_soccer)


func _physics_process(_delta: float) -> void:
	_frame += 1
	var ball: SoccerBall = _soccer._ball

	match _frame:
		260:
			# Игра давно идёт. Мяч — к торцевому борту (вне створа ворот,
			# z=12 > GOAL_HALF_W — гола нет), бот — носом в борт.
			for c: Car in _soccer._cars:
				c.controls_enabled = false
			_bot = _soccer._cars[4]   # нападающий КРАСНЫХ: всегда атакует мяч
			_bot.controls_enabled = true
			ball.global_position = Vector3(SoccerArena.HALF_LEN - 1.3, 1.1, 12.0)
			ball.linear_velocity = Vector3.ZERO
			ball.angular_velocity = Vector3.ZERO
			_bot.global_transform = Transform3D(
					Basis(Vector3.UP, -PI / 2),   # нос в +X, прямо в борт
					Vector3(SoccerArena.HALF_LEN - 6.0, 0.6, 12.0))
			_bot.linear_velocity = Vector3.ZERO
			_bot.angular_velocity = Vector3.ZERO
		320:
			# Минута на разгон прошла (1 c) — бот уже упёрся; помним точку.
			_pin = _bot.global_position
		1000:
			var ok := _worst_stall <= STALL_LIMIT and _max_move > 4.0
			print("SOCCER STUCK TEST: %s (худший упор %.1f c при лимите %.1f, "
					% ["PASS" if ok else "FAIL", _worst_stall / 60.0,
						STALL_LIMIT / 60.0]
					+ "отъехал на %.1f м)" % _max_move)
			get_tree().quit(0 if ok else 1)

	if _frame > 320 and _frame < 1000 and _bot != null:
		if _bot.linear_velocity.length() < STALL_SPEED:
			_stall += 1
			_worst_stall = maxi(_worst_stall, _stall)
		else:
			_stall = 0
		_max_move = maxf(_max_move, _bot.global_position.distance_to(_pin))
