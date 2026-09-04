# Замер посадки аркадных деталей на советских кузовах: для каждой машины и
# каждого варианта выхлопа/спойлера из её набора печатаем положение детали
# относительно кузова (в метрах, модель длиной 3.2 м): y детали от НИЗА
# кузова, y от ВЕРХА, z от кормы. Помогает найти «трубы у фар».
extends SceneTree

func _init() -> void:
	for base: String in CarModelLibrary.SOVIET_IDS:
		var color := CarModelLibrary.default_color(base)
		var parts: Dictionary = CarModelLibrary.SOVIET_PARTS[base]
		var line := "%-6s" % base
		for slot in ["exhaust", "spoiler"]:
			for idx in parts[slot]:
				var id := "%s_%s-%s%d" % [base, color, CarModelLibrary.ARCADE_KEYS[slot], idx]
				var m := CarModelLibrary.build(id, 3.2, 0.0)
				if m == null:
					line += " [%s%d: нет]" % [slot[0], idx]
					continue
				var body_lo := 1e9
				var body_hi := -1e9
				var body_rear := 1e9
				var part: Node3D = null
				for c in m.get_children():
					if c is MeshInstance3D and c.name != slot.capitalize():
						var a: AABB = (m.transform * c.transform) * (c as MeshInstance3D).mesh.get_aabb()
						body_lo = minf(body_lo, a.position.y)
						body_hi = maxf(body_hi, a.end.y)
						body_rear = minf(body_rear, -a.end.z) # корма = +z модели → в машине -z... берём z-мин по осям машины
					if c.name == slot.capitalize():
						part = c
				if part == null:
					line += " [%s%d: ?]" % [slot[0], idx]
					continue
				var pa: AABB = (m.transform * part.transform) * (part as MeshInstance3D).mesh.get_aabb()
				var pc := pa.get_center()
				line += " [%s%d y+%.2f/-%.2f]" % [slot[0], idx, pc.y - body_lo, body_hi - pc.y]
				m.free()
		print(line)
	quit(0)
