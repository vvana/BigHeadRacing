extends Node3D
## Снимок аркадных машин-конструкторов: 8 кузовов в ряд, каждый в своей
## краске и с деталями (мотор/спойлер/выхлоп/колёса по номеру кузова),
## плюс второй ряд — те же кузова в стоке. Проверка сборки глазами
## (позиции слотов, оси, краска, наклейки). Запуск С ОКНОМ:
## godot --path . res://tools/ShotArcade.tscn -- <папка_вывода>

var _frame := 0
var _out := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.6, 0.66)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 30)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.32, 0.34)
	floor_mesh.material_override = fm
	add_child(floor_mesh)

	# Ключ `--half 2` (после `--`): кузова 5–8 вместо 1–4.
	var first := 0
	var idx := args.find("--half")
	if idx >= 0 and idx + 1 < args.size() and args[idx + 1] == "2":
		first = 4
	for k in 4:
		var i := first + k
		var base: String = CarModelLibrary.ARCADE_IDS[i]
		var n := i + 1
		# Ряд 1 (дальний): комплектация «всё по номеру кузова» + наклейка
		# + полоса; ряд 2 (ближний): сток в тёмном оттенке.
		var cfg := {
			"color": CarModelLibrary.ARCADE_COLORS[i], "shade": 2,
			"glitter": i % 2, "wheel": n + 1, "engine": n, "spoiler": n,
			"exhaust": n, "sticker": n, "line": 1,
		}
		_place(CarModelLibrary.arcade_id(base, cfg), Vector3(-6.75 + k * 4.5, 0, -2.5))
		_place(CarModelLibrary.skin_id(base, CarModelLibrary.ARCADE_COLORS[i])
				.replace("2-g0", "1-g0"), Vector3(-6.75 + k * 4.5, 0, 3.0))

	var cam := Camera3D.new()
	cam.fov = 55
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 6.5, 11), Vector3(0, 0.2, 0.3))


func _place(id: String, at: Vector3) -> void:
	var m := CarModelLibrary.build(id, 3.2, 0.0)
	if m == null:
		print("FAIL build ", id)
		return
	var holder := Node3D.new()
	holder.position = at
	holder.rotation.y = -0.6   # три четверти — видно капот и корму
	holder.add_child(m)
	add_child(holder)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 12:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var name := "arcade2.png" if OS.get_cmdline_user_args().has("2") \
				else "arcade1.png"
		img.save_png(_out + "/" + name)
		print("SHOT " + name)
		get_tree().quit(0)
