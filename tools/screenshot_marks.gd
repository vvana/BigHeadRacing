extends Node3D
## Стенд разметки: стрелки и линии на тёмной «дороге», камера сверху-сбоку.

const ITEMS: Array[String] = [
	TrackDecor.DIR + "Arrow_01_free.fbx",
	TrackDecor.DIR + "Arrow_02_free.fbx",
	TrackDecor.CDIR + "prop_arrow_long.FBX",
	TrackDecor.CDIR + "prop_arrow_short.FBX",
	TrackDecor.CDIR + "prop_distance_1.FBX",
	TrackDecor.CDIR + "prop_distance_2.FBX",
	TrackDecor.CDIR + "prop_distance_3.FBX",
	TrackDecor.CDIR + "prop_gridline.FBX",
]
var _out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var decor := TrackDecor.new()
	add_child(decor)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70, 20, 0)
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 30)
	plane.material = StandardMaterial3D.new()
	(plane.material as StandardMaterial3D).albedo_color = Color(0.18, 0.18, 0.2)
	floor_mesh.mesh = plane
	floor_mesh.position.x = 35.0
	add_child(floor_mesh)
	var x := 0.0
	for m in ITEMS:
		var node := decor._spawn(m, Vector3(x, 0.05, 0), Vector3.BACK, 1.0,
				m.ends_with(".fbx"))
		x += 10.0
	_shoot.call_deferred()


func _shoot() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(35, 26, 26)
	cam.look_at(Vector3(35, 0, 0))
	cam.make_current()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + "/marks.png")
	print("SHOT marks.png")
	get_tree().quit(0)
