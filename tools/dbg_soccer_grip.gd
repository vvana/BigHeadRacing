extends Node3D
## Замер сцепления машины на футбольной арене: газ в пол 2 с, потом
## полный руль. Печатает опору колёс, скорость, боковой снос.
var _soccer: Node3D
var _frame := 0
var _car: Car
var _phase := 0

func ai_drive(_c: Car) -> Vector2:
	return Vector2(1.0, 0.0) if _phase == 0 else Vector2(1.0, 1.0)

func _ready() -> void:
	_soccer = (load("res://scenes/Soccer.tscn") as PackedScene).instantiate()
	add_child(_soccer)
	_car = _soccer._car
	_car.is_player = false
	_car.soccer_brain = self
	for c in _soccer._cars:
		if c != _car:
			c.controls_enabled = false
			c.freeze = true

func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame < 200:
		return
	if _frame == 320:
		_phase = 1
	if _frame % 10 == 0:
		var h := _car.linear_velocity
		h.y = 0.0
		print("[grip] f=%d wheels=%d y=%.2f speed=%.1f side=%.2f yaw=%.2f pos=(%.1f,%.1f)" % [
			_frame, _car._grounded_wheels, _car.global_position.y, h.length(),
			_car._side_speed, _car.angular_velocity.y,
			_car.global_position.x, _car.global_position.z])
	if _frame >= 480:
		get_tree().quit(0)
