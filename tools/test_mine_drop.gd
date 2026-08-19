extends Node3D
## Автотест мины: сброшенная в воздухе мина НЕ висит, а падает и ложится
## на полотно; наземный сброс кладёт её на дорогу как раньше.

var _main: Node3D
var _frame := 0
var _air_mine: Mine
var _ground_mine: Mine
var _air_y0 := 0.0


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	_frame += 1
	var car: Car = _main._car
	match _frame:
		30:
			# Мина «в воздухе»: кладём вручную на 4 м выше машины.
			car.drop_mine()
			_air_mine = _find_new_mine([])
			_air_mine.global_position = car.global_position \
					+ car.global_transform.basis.z * 2.4 + Vector3.UP * 4.0
			_air_y0 = _air_mine.global_position.y
			# Наземный сброс — как обычно.
			car.drop_mine()
			_ground_mine = _find_new_mine([_air_mine])
			print("сброс: воздух y=%.2f, земля y=%.2f (машина y=%.2f)" % [
				_air_y0, _ground_mine.global_position.y, car.global_position.y])
		150:  # ~2 c — падение с 4 м занимает ~0.9 c
			var road_y := _road_y_under(_air_mine.global_position)
			var air_dy := _air_mine.global_position.y - road_y
			var gnd_dy := _ground_mine.global_position.y \
					- _road_y_under(_ground_mine.global_position)
			var fell := _air_y0 - _air_mine.global_position.y
			var ok := fell > 3.0 and air_dy < 0.3 and gnd_dy < 0.3
			print("MINE DROP TEST: %s (упала на %.2f м, до полотна: воздух %.2f, земля %.2f)" % [
				"PASS" if ok else "FAIL", fell, air_dy, gnd_dy])
			get_tree().quit(0 if ok else 1)


func _find_new_mine(known: Array) -> Mine:
	for child in _main.get_children():
		if child is Mine and not known.has(child):
			return child
	return null


func _road_y_under(pos: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		pos + Vector3.UP * 10.0, pos + Vector3.DOWN * 30.0)
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	return (hit.position as Vector3).y if not hit.is_empty() else -999.0
