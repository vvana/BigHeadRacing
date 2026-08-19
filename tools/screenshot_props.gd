extends Node3D
## Служебный стенд: BEDRILL-пропсы в ряд (с нормализацией), камера сбоку.
## Запуск: godot --path . res://tools/ScreenshotProps.tscn -- <папка>

const MODELS: Array[String] = [
	"Flag_free.fbx", "Pole_light_free.fbx", "Cone_free.fbx", "Tire_free.fbx",
	"Sign_free.fbx", "Tribune_free.fbx", "Arch_for_banner_free.fbx",
]
var _out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var decor := TrackDecor.new()
	add_child(decor)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 40)
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	var x := 0.0
	for m in MODELS:
		decor._spawn(TrackDecor.DIR + m, Vector3(x, 0, 0), Vector3.BACK, 1.0, true)
		x += 12.0
	_shoot.call_deferred()


func _shoot() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(36, 8, 42)
	cam.look_at(Vector3(36, 3, 0))
	cam.make_current()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out + "/props.png")
	print("SHOT props.png")
	get_tree().quit(0)
