extends Node3D
## Тот же замер на классической трассе: газ в пол 2 с, потом полный руль.
var _main: Node3D
var _frame := 0
var _car: Car
var _phase := 0

func ai_drive(_c: Car) -> Vector2:
	return Vector2(1.0, 0.0) if _phase == 0 else Vector2(1.0, 1.0)

func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)

func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 5:
		_car = _main._cars[0]
		_car.is_player = false
		_car.soccer_brain = self
		for c in _main._cars:
			if c != _car:
				c.controls_enabled = false
				c.freeze = true
	if _frame < 300:
		return
	if _frame == 420:
		_phase = 1
	if _frame % 10 == 0:
		var h := _car.linear_velocity
		h.y = 0.0
		print("[grip] f=%d wheels=%d y=%.2f speed=%.1f side=%.2f yaw=%.2f" % [
			_frame, _car._grounded_wheels, _car.global_position.y, h.length(),
			_car._side_speed, _car.angular_velocity.y])
	if _frame >= 560:
		get_tree().quit(0)
