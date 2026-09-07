extends Node
## Проверка «фара висит в воздухе»: для каждой машины считаем якорь фары
## тем же кодом, что игра (Car.headlight_anchor), и меряем расстояние от
## центра лампы до БЛИЖАЙШЕЙ вершины кузова (без колёс). Лампа сидит в
## кузове по стекляшку — до ПОВЕРХНОСТИ (ближайшего треугольника) должно
## быть считанные сантиметры; больше AIR_TOL — лампа в воздухе.
## Запуск: godot --headless --path . res://tools/CheckHeadlightFit.tscn
##   [-- id1 id2 …] — дополнительно проверить полные id (с тюнингом).

const AIR_TOL := 0.12


func _ready() -> void:
	var bad := 0
	var ids: Array = Array(CarModelLibrary.CAR_IDS)
	ids.append_array(OS.get_cmdline_user_args())
	for id in ids:
		var model := CarModelLibrary.build(id)
		if model == null:
			continue
		var a := Car.headlight_anchor(model, model.transform)
		if a.is_empty():
			print("%-10s ЯКОРЯ НЕТ" % id)
			bad += 1
			continue
		var pts := Car.model_points(model, model.transform)
		var best := 1e9
		var best_p := Vector3.ZERO
		var lamp := Vector3(a["x"], a["y"], a["z"] + 0.02)
		# model_points отдаёт вершины треугольников по три подряд.
		for t in range(0, pts.size() - 2, 3):
			var q := _closest_on_triangle(lamp, pts[t], pts[t + 1], pts[t + 2])
			var d := q.distance_to(lamp)
			if d < best:
				best = d
				best_p = q
		var flag := "  В ВОЗДУХЕ" if best > AIR_TOL else ""
		if best > AIR_TOL:
			bad += 1
		print("%-10s фара x%.2f y%.2f z%.2f ш%.2f  до кузова %.3f м (ближайшая x%.2f y%.2f z%.2f)%s" % [
				id, a["x"], a["y"], a["z"], a["w"], best, best_p.x, best_p.y, best_p.z, flag])
		model.free()
	print("ИТОГО в воздухе: %d" % bad)
	get_tree().quit()


## Ближайшая к p точка треугольника abc (Ericson, Real-Time Collision
## Detection, 5.1.5).
static func _closest_on_triangle(p: Vector3, a: Vector3, b: Vector3,
		c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denom := 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)
