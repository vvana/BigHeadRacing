extends Node3D
## Каталог реквизита гаража (03.09): пропсы из Unity-паков (то, что
## оставлено после отбора; гараж-домик, фонарь, паддок, бак — удалены) в
## ряд с нормализацией, печать габаритов, снимок с 3/4. Запуск С ОКНОМ:
## godot --path . res://tools/ShotGarageProps.tscn -- <папка>

const MODELS: Array[String] = [
	"cartoon/prop_tyre_4x8.FBX", "cartoon/prop_tyre_1x1_B.FBX",
	"cartoon/prop_plastic_block.FBX", "city/trash_can_a.fbx",
	"city/spotlight_a.fbx", "palmov/exhaust_fan.fbx",
	"Tire_free.fbx", "palmov/barrel_a.fbx", "cartoon/prop_tyre_4x1_A.FBX",
]
var _out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	var decor := TrackDecor.new()
	add_child(decor)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.6, 0.6, 0.62)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 60)
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	var x := 0.0
	for m in MODELS:
		var node := decor._spawn(TrackDecor.DIR + m, Vector3(x, 0, 0),
				Vector3.BACK, 1.0, true)
		if node == null:
			print("PROP %s — НЕ ЗАГРУЗИЛСЯ" % m)
			continue
		var ab := _aabb(node)
		print("PROP %-32s size %.2f x %.2f x %.2f  at x=%.1f" % [m, ab.size.x, ab.size.y, ab.size.z, x])
		x += maxf(ab.size.x, 2.0) + 3.0
	_shoot.call_deferred(x)


func _aabb(root: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var ab := mi.transform * mi.mesh.get_aabb()
		merged = ab if first else merged.merge(ab)
		first = false
	return merged


func _shoot(row: float) -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(row * 0.5, row * 0.22, row * 0.6)
	cam.look_at(Vector3(row * 0.5, 2, 0))
	cam.fov = 60
	cam.make_current()
	for i in 4:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + "/garage_props.png")
	# Второй кадр — крупно первая половина ряда (гараж, лампа, огни, шины).
	cam.global_position = Vector3(14, 7, 22)
	cam.look_at(Vector3(14, 2, 0))
	for i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + "/garage_props_2.png")
	print("SHOT garage_props.png")
	get_tree().quit(0)
