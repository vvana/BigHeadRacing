extends SceneTree
## Ищем «волны» полотна: перелом уклона (изменение dy/ds на метр пути).
func _init() -> void:
	var tb := TrackBuilder.new()
	tb._build_curve()
	var curve := tb._curve
	var length := curve.get_baked_length()
	var step := 0.5
	var n := int(length / step)
	var kinks: Array = []
	for i in n:
		var y0 := curve.sample_baked(fmod(i * step, length)).y
		var y1 := curve.sample_baked(fmod((i + 1) * step, length)).y
		var y2 := curve.sample_baked(fmod((i + 2) * step, length)).y
		var slope_change := ((y2 - y1) - (y1 - y0)) / step  # рад/м прибл.
		kinks.append([absf(slope_change), float(i) * step / length, y1])
	kinks.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for k in 25:
		print("kink=%.4f t=%.3f y=%.2f" % [kinks[k][0], kinks[k][1], kinks[k][2]])
	tb.free()
	quit(0)
