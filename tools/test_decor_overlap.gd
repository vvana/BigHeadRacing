extends Node3D
## Автотест декора (16.09): на зимней трассе ни одна ель/камень/снеговик не
## должны стоять внутри габарита трибуны (жалоба «ель растёт сквозь
## трибуну»). Строит Main с track_kind = snow, берёт мировые AABB трибун
## из Decor и считает пропсы россыпи, чей центр попал внутрь (XZ, +1 м).

var _main: Node3D
var _frame := 0


func _ready() -> void:
	GameState.track_kind = TrackBuilder.KIND_SNOW
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	GameState.track_kind = ""


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame < 5:
		return
	var decor: Node = _main._track.get_node_or_null("Decor")
	if decor == null:
		print("DECOR OVERLAP TEST: FAIL (нет Decor)")
		get_tree().quit(1)
		return
	var boxes: Array[AABB] = []
	var props: Array[Node3D] = []
	for n: Node in decor.get_children():
		if not (n is Node3D):
			continue
		# Имена узлов ненадёжны (дубли, RootNode) — смотрим путь меша.
		var nm := _mesh_path(n).get_file().to_lower()
		if nm.begins_with("tribune") or nm.begins_with("prop_seats"):
			boxes.append(_world_aabb(n))
		elif nm.begins_with("fir_winter") or nm.begins_with("stone") \
				or nm.begins_with("snowman"):
			props.append(n)
	var bad := 0
	for p: Node3D in props:
		var g := p.global_position
		for b: AABB in boxes:
			if g.x > b.position.x - 1.0 and g.x < b.end.x + 1.0 \
					and g.z > b.position.z - 1.0 and g.z < b.end.z + 1.0:
				bad += 1
				print("  внутри трибуны: %s в (%.1f, %.1f)" % [p.name, g.x, g.z])
				break
	print("трибун: %d, пропсов россыпи: %d, внутри трибун: %d"
			% [boxes.size(), props.size(), bad])
	print("DECOR OVERLAP TEST: %s" % ("PASS" if bad == 0 and boxes.size() >= 3 else "FAIL"))
	get_tree().quit(0 if bad == 0 else 1)


func _mesh_path(n: Node) -> String:
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null and mi.mesh.resource_path != "":
			return mi.mesh.resource_path
	return ""


func _world_aabb(n: Node) -> AABB:
	var merged := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var ab := mi.global_transform * mi.mesh.get_aabb()
		merged = ab if first else merged.merge(ab)
		first = false
	return merged
