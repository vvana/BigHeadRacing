extends Node3D
## Автотест: машину ставят за внешнюю сторону ограждения (как на скриншоте).
## Печатает фактическое расстояние до оси и проверяет, вернулась ли она.

var _main: Node3D
var _frame := 0
var _dist_when_placed := 0.0


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	_frame += 1
	var track: TrackBuilder = _main._track
	var curve: Curve3D = track._curve
	match _frame:
		30:
			# Ставим машину впритык за наружную грань стены.
			var off := curve.get_baked_length() * 0.3
			var pos := curve.sample_baked(off)
			var ahead := curve.sample_baked(off + 1.0)
			var right := (ahead - pos).normalized().cross(Vector3.UP)
			# Полотно переменной ширины — отступ от ФАКТИЧЕСКОЙ кромки.
			var half := track.half_width_at_offset(off)
			var outside: Vector3 = pos + right * (half + 1.1) + Vector3.UP * 0.6
			_main._car.global_position = outside
			_main._car.linear_velocity = Vector3.ZERO
			_dist_when_placed = track.distance_from_axis(outside)
			print("placed outside wall: dist_to_axis=%.2f (порог %.2f)" % [
				_dist_when_placed,
				half + track.offtrack_margin])
		240:  # ~4 секунды при 60 Гц — авто-возврат должен был сработать
			var dist := track.distance_from_axis(_main._car.global_position)
			print("OFFTRACK TEST: %s (dist_to_axis=%.2f)" % [
				"PASS" if dist < 2.0 else "FAIL", dist])
			get_tree().quit(0 if dist < 2.0 else 1)
