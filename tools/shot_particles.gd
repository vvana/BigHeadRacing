extends Node3D
## Крупный план дыма из-под колёс и пламени буста (пакет 04.09, п.12):
## машина стоит на полу с debug_smoke, камера сбоку-сзади.
## Запуск С ОКНОМ: godot --path . res://tools/ShotParticles.tscn -- <папка>

var _out := "user://shots"
var _frame := 0
var _car: Car


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.25, 0.27, 0.3)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	add_child(sun)
	var floor_body := StaticBody3D.new()
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	fm.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.22)
	fm.material_override = mat
	floor_body.add_child(fm)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	col.shape = box
	col.position.y = -0.5
	floor_body.add_child(col)
	add_child(floor_body)
	_car = Car.new()
	_car.is_player = false
	_car.debug_smoke = true
	add_child(_car)
	_car.global_position = Vector3(0, 0.6, 0)
	var model := CarModelLibrary.build("vz01_red-mred", 3.2)
	if model:
		_car.add_child(model)
		_car.collect_wheels(model)
	_car.apply_fx("vz01_red-mred")
	var cam := Camera3D.new()
	cam.fov = 45
	add_child(cam)
	cam.look_at_from_position(Vector3(4.5, 1.6, 5.5), Vector3(0, 0.4, 1.0))


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 90:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out + "/particles.png")
		print("SHOT particles.png")
		get_tree().quit(0)
