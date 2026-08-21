extends SceneTree
## Проверка гладкости трассы: считаем изменение направления между соседними
## сэмплами. Резкий излом = большой угол на коротком шаге.

func _init() -> void:
	var track := TrackBuilder.new()
	var root := Node3D.new()
	root.add_child(track)
	get_root().add_child(root)
	await process_frame

	var curve: Curve3D = track._curve
	var length := curve.get_baked_length()
	var steps := 400
	var step := length / steps
	# Излом в ПЛАНЕ (вид сверху) — дефект: именно он даёт «уголки» на стене.
	# Перелом по ВЕРТИКАЛИ — задумка: кромки плато и обрывы-трамплины.
	var worst_yaw := 0.0
	var worst_yaw_at := 0.0
	var worst_pitch := 0.0
	var worst_pitch_at := 0.0
	var prev_flat := Vector3.ZERO
	var prev_pitch := 0.0
	for i in steps + 1:
		var off := step * i
		var p := curve.sample_baked(fmod(off, length))
		var q := curve.sample_baked(fmod(off + step, length))
		var dir := (q - p).normalized()
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		var pitch := rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))
		if i > 0:
			var yaw := rad_to_deg(prev_flat.angle_to(flat))
			if yaw > worst_yaw:
				worst_yaw = yaw
				worst_yaw_at = off
			var dp := absf(pitch - prev_pitch)
			if dp > worst_pitch:
				worst_pitch = dp
				worst_pitch_at = off
		prev_flat = flat
		prev_pitch = pitch
	# Лимит излома — от САМОГО КРУТОГО поворота конфигурации: на дуге
	# радиуса R поворот между сэмплами = step/R, и это законная крутизна,
	# а не дефект. Запас ×1.4 покрывает стыки прямая↔дуга; настоящий
	# излом (разрыв касательной) даёт угол в разы больше.
	var min_radius := 1e9
	for seg: Array in TrackBuilder.SEGMENTS:
		if seg[0] == "A":
			min_radius = minf(min_radius, float(seg[1]))
	var yaw_limit := rad_to_deg(step / min_radius) * 1.4
	var ok := worst_yaw < yaw_limit and worst_pitch < 20.0
	print("CURVE TEST: %s (длина %.0f м, шаг %.2f м, мин. радиус %.0f м)" % [
		"PASS" if ok else "FAIL", length, step, min_radius])
	print("  излом в плане: %.2f° на %.0f м (лимит %.2f°)" % [
		worst_yaw, worst_yaw_at, yaw_limit])
	print("  перелом профиля: %.2f° на %.0f м (лимит 20°)" % [
		worst_pitch, worst_pitch_at])
	quit(0 if ok else 1)
