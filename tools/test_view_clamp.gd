extends Node3D
## Автотест ЗАЖИМА КАРТИНКИ МАРИОНЕТКИ В ОГРАЖДЕНИЯХ (08.09): упреждение и
## догадка по скорости в повороте уводили цель марионетки за борт, и
## «боты и соперник по сети на поворотах частично вылетали за ограждения
## и сразу возвращались». Car._clamp_view_inside_walls обязан: точку
## снаружи полотна вернуть к внутренней грани стены минус полкузова, точку
## внутри — не трогать, высоту — не менять. Проверяем на боте оффлайн-
## заезда в нескольких точках классической трассы (с ограждениями).
## Запуск: godot --headless --path . res://tools/TestViewClamp.tscn
## Вердикт — «VIEW CLAMP TEST: PASS|FAIL».

var _main: Node3D
var _frame := 0


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame < 30:
		return
	var track: TrackBuilder = _main._track
	var curve: Curve3D = track._curve
	var length := curve.get_baked_length()
	var car: Car = _main._cars[1]
	var failed := 0
	var checks := 0
	for k in 12:
		var off := length * (0.05 + 0.08 * k)
		var axis := curve.sample_baked(off)
		var right: Vector3 = track.right_at_offset(off)
		var hw: float = track.half_width_at_offset(off)
		var limit := hw - TrackBuilder.WALL_THICKNESS * 0.5 - 0.95
		# Машина стоит на оси в этой точке — отметка по непрерывности.
		car.global_position = axis + Vector3.UP * 0.6
		car.reset_track_offset()
		car.sync_track_offset()
		for side: float in [-1.0, 1.0]:
			# Снаружи: на 1.5 м за гранью стены — должно вернуть к пределу.
			var outside := axis + right * side * (hw + 1.5) + Vector3.UP * 0.6
			var c := car._clamp_view_inside_walls(outside)
			var d := (c - axis)
			d.y = 0.0
			checks += 1
			if absf(d.dot(right) - side * limit) > 0.05 or absf(c.y - 0.6 - axis.y) > 1e-3:
				failed += 1
				print("  off %.0f сторона %+.0f: снаружи → %.2f (ждали %.2f)" % [
						off, side, d.dot(right), side * limit])
			# Внутри: на полметра до предела — не трогать.
			var inside := axis + right * side * (limit - 0.5) + Vector3.UP * 0.6
			var c2 := car._clamp_view_inside_walls(inside)
			checks += 1
			if c2.distance_to(inside) > 1e-3:
				failed += 1
				print("  off %.0f сторона %+.0f: внутри сдвинуло на %.2f" % [
						off, side, c2.distance_to(inside)])
	print("проверок: %d, провалов: %d" % [checks, failed])
	print("VIEW CLAMP TEST: %s" % ("PASS" if failed == 0 else "FAIL"))
	get_tree().quit(0 if failed == 0 else 1)
