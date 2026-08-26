extends Node
## Разовый замер: насколько близко витки трассы подходят друг к другу и
## насколько далеко от оси можно оказаться, прежде чем Curve3D.get_closest_offset
## «перепрыгнет» на чужой (далёкий по ходу гонки) участок.

func _ready() -> void:
	for kind: String in TrackBuilder.KINDS:
		var tb := TrackBuilder.new()
		tb.kind = kind
		add_child(tb)
		await get_tree().process_frame
		var curve: Curve3D = tb._curve
		var length := curve.get_baked_length()
		var n := 500
		var pts: Array[Vector3] = []
		for i in n:
			pts.append(curve.sample_baked(length * float(i) / float(n)))
		var worst := 1e9
		var wa := 0.0
		var wb := 0.0
		for i in n:
			for j in range(i + 1, n):
				var da := absf(float(j - i)) / float(n) * length
				var along := minf(da, length - da)
				if along < 150.0:
					continue
				var p: Vector3 = pts[i]
				var q: Vector3 = pts[j]
				var d := Vector2(p.x - q.x, p.z - q.z).length()
				if d < worst:
					worst = d
					wa = length * float(i) / float(n)
					wb = length * float(j) / float(n)
		print("%s: длина %.1f м, сближение витков %.1f м (отметки %.0f и %.0f), полуширина там %.1f/%.1f"
				% [kind, length, worst, wa, wb,
				tb.half_width_at_offset(wa), tb.half_width_at_offset(wb)])
		tb.queue_free()
		await get_tree().process_frame
	get_tree().quit()
