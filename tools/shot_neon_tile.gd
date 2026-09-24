extends Control
## Снимок плитки лобби (22.09, «чёрный прямоугольник под машиной»): та же
## прозрачная SubViewport, что у Lobby._build_slot (подиум, свет, машина),
## поверх серого фона. Запуск С ОКНОМ:
##   godot --path . res://tools/ShotNeonTile.tscn -- <папка> [<полный id>]
##   (и с --rendering-driver opengl3 для GL-рендерера)
var _frame := 0
var _out := "user://shots"
var _id := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0]
	_id = args[1] if args.size() > 1 \
			else CarModelLibrary.tuned_id("vz08", {"neon": "white", "color": "black"})
	DirAccess.make_dir_recursive_absolute(_out)
	var bg := ColorRect.new()
	bg.color = Color(0.45, 0.45, 0.5)
	bg.size = Vector2(480, 320)
	add_child(bg)
	var view := SubViewportContainer.new()
	view.stretch = true
	view.position = Vector2(40, 20)
	view.size = Vector2(400, 280)
	add_child(view)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	view.add_child(vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.9, 4.6)
	cam.rotation_degrees = Vector3(-16, 0, 0)
	cam.fov = 45
	vp.add_child(cam)
	cam.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.3
	vp.add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.7)
	e.ambient_light_energy = 0.9
	env.environment = e
	vp.add_child(env)
	var podium := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.0
	cyl.bottom_radius = 2.3
	cyl.height = 0.3
	podium.mesh = cyl
	podium.position.y = -0.15
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.16, 0.2)
	mat.metallic = 0.6
	mat.roughness = 0.35
	podium.material_override = mat
	vp.add_child(podium)
	var table := Node3D.new()
	table.rotation.y = deg_to_rad(150)
	vp.add_child(table)
	var model := CarModelLibrary.build(_id, 3.2, 0.02)
	print("машина: ", _id, " ", "ok" if model else "НЕТ")
	if model:
		table.add_child(model)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 12:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var drv := str(ProjectSettings.get_setting("rendering/renderer/rendering_method"))
		var path := "%s/neon_tile_%s.png" % [_out, ("gl" if RenderingServer.get_rendering_device() == null else "rd")]
		img.save_png(path)
		print("снимок: ", path, " (", drv, ")")
		get_tree().quit(0)
