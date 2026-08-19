extends Node3D
## Стенд трибун: обе модели «лицом» на +Z (facing=BACK), перед каждой
## на стороне +Z — красный куб-маркер. Камера смотрит со стороны +Z.

var _out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var decor := TrackDecor.new()
	add_child(decor)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	add_child(sun)
	var items: Array = [
		[TrackDecor.DIR + "Tribune_free.fbx", true, 0.0],
		[TrackDecor.CDIR + "prop_seats_big.FBX", false, 30.0],
		[TrackDecor.CDIR + "prop_seats_small.FBX", false, 60.0],
	]
	for it: Array in items:
		var node := decor._spawn(String(it[0]), Vector3(float(it[2]), 0, 0),
				Vector3.BACK, 1.0, bool(it[1]))
		var marker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.5, 1.5, 1.5)
		box.material = StandardMaterial3D.new()
		(box.material as StandardMaterial3D).albedo_color = Color(1, 0, 0)
		marker.mesh = box
		add_child(marker)
		marker.position = Vector3(float(it[2]), 0.75, 10.0)
	_shoot.call_deferred()


func _shoot() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(30, 14, 34)
	cam.look_at(Vector3(30, 4, 0))
	cam.make_current()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + "/tribunes.png")
	print("SHOT tribunes.png")
	get_tree().quit(0)
