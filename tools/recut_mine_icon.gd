extends SceneTree
## Разовый инструмент: перевырезать значок мины из исходного листа
## _STYLE_CORE_A_sheet_of_12_weap_2.jpg (у wg_mine.png была убита альфа —
## при первом вырезании фон выедался по яркости и съел белые/светлые
## части). Фон убираем ЗАЛИВКОЙ ОТ КРАЁВ по близости к серому фона:
## чёрная мина внутри щитка не задевается.
## Запуск: godot --headless --path . -s res://tools/recut_mine_icon.gd


func _init() -> void:
	var sheet := Image.new()
	var err := sheet.load("res://_STYLE_CORE_A_sheet_of_12_weap_2.jpg")
	if err != OK:
		push_error("лист не загрузился: %d" % err)
		quit(1)
		return
	var tile := sheet.get_region(Rect2i(28, 498, 242, 242))
	tile.convert(Image.FORMAT_RGBA8)

	var w := tile.get_width()
	var h := tile.get_height()
	var bg := Color8(31, 35, 36)
	const TOL := 0.165  # ~42/255 суммарной разницы каналов
	var is_bg := PackedByteArray()
	is_bg.resize(w * h)
	var seen := PackedByteArray()
	seen.resize(w * h)
	var queue: Array[Vector2i] = []
	for x in w:
		queue.append(Vector2i(x, 0))
		queue.append(Vector2i(x, h - 1))
	for y in h:
		queue.append(Vector2i(0, y))
		queue.append(Vector2i(w - 1, y))
	while not queue.is_empty():
		var p: Vector2i = queue.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var idx := p.y * w + p.x
		if seen[idx] == 1:
			continue
		seen[idx] = 1
		var c := tile.get_pixelv(p)
		var d := absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b)
		if d > TOL:
			continue
		is_bg[idx] = 1
		queue.append(p + Vector2i.RIGHT)
		queue.append(p + Vector2i.LEFT)
		queue.append(p + Vector2i.UP)
		queue.append(p + Vector2i.DOWN)

	var removed := 0
	for y in h:
		for x in w:
			if is_bg[y * w + x] == 1:
				var c := tile.get_pixel(x, y)
				tile.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
				removed += 1
	print("фон выеден: %d px из %d" % [removed, w * h])

	tile.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	err = tile.save_png("res://assets/ui/garage/wg_mine.png")
	print("сохранено: %d" % err)
	quit(0 if err == OK else 1)
