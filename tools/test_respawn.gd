extends Node3D
## Автотест клавиши R (respawn): грузим Main, зашвыриваем машину в поле,
## инжектим нажатие R и проверяем, что машина вернулась к оси трассы.

var _main: Node3D
var _frame := 0


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	_frame += 1
	match _frame:
		30:
			_main._car.global_position = Vector3(70, 3, 70)  # далеко вне трассы
		60:
			var ev := InputEventKey.new()
			ev.physical_keycode = KEY_R
			ev.pressed = true
			Input.parse_input_event(ev)
		90:
			var pos: Vector3 = _main._car.global_position
			var track: TrackBuilder = _main._track
			var curve: Curve3D = track._curve
			var axis := curve.sample_baked(curve.get_closest_offset(pos))
			var dist := Vector2(pos.x - axis.x, pos.z - axis.z).length()
			var moved := pos.distance_to(Vector3(70, 3, 70)) > 10.0
			print("RESPAWN TEST: %s (car=%s, dist_to_axis=%.1f)" % [
				"PASS" if moved and dist < 2.0 else "FAIL", pos, dist])
			get_tree().quit(0 if moved and dist < 2.0 else 1)
