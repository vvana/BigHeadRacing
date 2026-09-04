# Поиск ячейки СТЕКЛА в палитре аркадного пака: у кузовов Car 1..8 берём
# треугольники поверхности "details" в верхней части кузова (кабина) с
# боковой/наклонной нормалью, сэмплируем палитру по UV центроида и
# считаем гистограмму цветов. Самый частый — стекло.
extends SceneTree

func _init() -> void:
	var pal: Texture2D = load(CarModelLibrary.ARCADE_TEX + "ColorPalette.png")
	var img := pal.get_image()
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	for n in range(1, 9):
		var mesh := CarModelLibrary._arcade_mesh("Car %d" % n)
		if mesh == null:
			print("Car %d: нет меша" % n)
			continue
		var aabb := mesh.get_aabb()
		var y_lo := aabb.position.y + aabb.size.y * 0.55
		var hist := {}
		var uvhist := {}
		for si in mesh.get_surface_count():
			var m := mesh.surface_get_material(si)
			if m == null or m.resource_name != "details":
				continue
			var arr := mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var tri_count := idx.size() / 3 if idx.size() > 0 else verts.size() / 3
			for t in tri_count:
				var i0 := idx[t * 3] if idx.size() > 0 else t * 3
				var i1 := idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1
				var i2 := idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2
				var c := (verts[i0] + verts[i1] + verts[i2]) / 3.0
				var nrm := (norms[i0] + norms[i1] + norms[i2]) / 3.0
				if c.y < y_lo or absf(nrm.y) > 0.85:
					continue
				var uv := (uvs[i0] + uvs[i1] + uvs[i2]) / 3.0
				var px := Vector2i(int(uv.x * w) % w, int(uv.y * h) % h)
				var col := img.get_pixelv(px)
				var key := "%d,%d,%d" % [int(col.r * 255), int(col.g * 255), int(col.b * 255)]
				hist[key] = hist.get(key, 0) + 1
				uvhist[key] = px
		var keys := hist.keys()
		keys.sort_custom(func(a, b): return hist[a] > hist[b])
		var top := []
		for k in keys.slice(0, 4):
			top.append("%s x%d @%s" % [k, hist[k], uvhist[k]])
		print("Car %d: %s" % [n, " | ".join(top)])
	quit(0)
