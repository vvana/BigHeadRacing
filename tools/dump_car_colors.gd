extends SceneTree
## Отладочный дамп настоящих цветов краски советского пака: у него цвет
## сидит в UV по общей палитре albedo.png, поэтому «на глазок» подобранные
## квадратики в гараже не совпадали с машиной (жалоба 03.09).
##
## Для каждого цвета берём готовую модель, обходим треугольники всех
## поверхностей, считаем площадь каждого и цвет палитры под его UV; самая
## большая площадь одного тона и есть краска кузова (стёкла, резина и
## хром занимают меньше). Печатает готовые строки для
## CarSelect.SWATCH_COLORS.
##
## Запуск: godot --headless --path . --script tools/dump_car_colors.gd

const BASE := "vz01"


func _init() -> void:
	var alb: Texture2D = load(
			"res://assets/models/sovietcars/Materials/Textures/albedo.png")
	var img: Image = alb.get_image()
	for color in CarModelLibrary.SOVIET_COLORS:
		var model := CarModelLibrary.build("%s_%s" % [BASE, color], 3.2, 0.0)
		if model == null:
			print("нет модели ", color)
			continue
		var areas := {}     # цвет (строкой) → площадь
		_walk(model, img, areas)
		var keys := areas.keys()
		keys.sort_custom(func(a, b): return float(areas[a]) > float(areas[b]))
		var top := ""
		for k in mini(4, keys.size()):
			top += " %s=%.4f" % [keys[k], float(areas[keys[k]])]
		var c := Color(str(keys[0]))
		print('\t"%s": Color(%.3f, %.3f, %.3f),   # топ:%s'
				% [color, c.r, c.g, c.b, top])
		model.free()
	quit()


func _walk(node: Node, img: Image, areas: Dictionary) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			_surface(mi.mesh.surface_get_arrays(s), img, areas)
	for child in node.get_children():
		_walk(child, img, areas)


func _surface(arrays: Array, img: Image, areas: Dictionary) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	if uvs.is_empty():
		return
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if idx.is_empty():
		idx = PackedInt32Array(range(verts.size()))
	var w := img.get_width()
	var h := img.get_height()
	for i in range(0, idx.size() - 2, 3):
		var a := idx[i]
		var b := idx[i + 1]
		var c := idx[i + 2]
		var area := 0.5 * (verts[b] - verts[a]).cross(verts[c] - verts[a]).length()
		if area <= 0.0:
			continue
		var uv := (uvs[a] + uvs[b] + uvs[c]) / 3.0
		var px := clampi(int(uv.x * w), 0, w - 1)
		var py := clampi(int(uv.y * h), 0, h - 1)
		var col := img.get_pixel(px, py).to_html(false)
		areas[col] = float(areas.get(col, 0.0)) + area
