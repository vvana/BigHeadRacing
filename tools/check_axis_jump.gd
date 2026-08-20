extends SceneTree
## Ищет зоны, где точка у стены ближе к ЧУЖОМУ участку оси, чем к своему.

func _init() -> void:
	var tb := TrackBuilder.new()
	tb._build_curve()
	var curve := tb._curve
	var length := curve.get_baked_length()
	var bad := 0
	var d := 0.0
	while d < length:
		var pos := curve.sample_baked(d)
		var ahead := curve.sample_baked(fmod(d + 0.5, length))
		var dir := (ahead - pos)
		dir.y = 0.0
		dir = dir.normalized()
		var right := dir.cross(Vector3.UP) * -1.0
		for side: float in [-1.0, 1.0]:
			# Точка вплотную к стене (и чуть над полотном, как кузов).
			var p := pos + right * side * 8.6 + Vector3.UP * 0.5
			var got := curve.get_closest_offset(p)
			var diff: float = absf(got - d)
			diff = minf(diff, length - diff)
			if diff > 4.0:
				var t_here := (curve.sample_baked(fmod(d + 0.5, length)) - pos)
				var t_there := (curve.sample_baked(fmod(got + 0.5, length))
						- curve.sample_baked(got))
				t_here.y = 0.0
				t_there.y = 0.0
				var dot := t_here.normalized().dot(t_there.normalized())
				print("JUMP d=%.1f side=%d -> got=%.1f (diff %.1f м, каса dot=%.2f)" % [
						d, side, got, diff, dot])
				bad += 1
		d += 1.0
	print("DONE bad=%d length=%.0f" % [bad, length])
	quit(0)
