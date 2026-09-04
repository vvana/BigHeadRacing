extends Node3D
## Служебные крупные планы для пакета правок 04.09: выхлопы/спойлеры на
## советских машинах, фары (маркеры якорей Car.headlight_anchor), неон,
## полоса на Багги с наклейками. Запуск С ОКНОМ:
##   godot --path . res://tools/ShotFixBatch.tscn -- <папка>

var _out := "user://shots"
var _cam: Camera3D
var _jobs: Array = []
var _frame := 0
var _holder: Node3D
var _busy := false


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
	_cam = Camera3D.new()
	_cam.fov = 62
	add_child(_cam)
	_holder = Node3D.new()
	add_child(_holder)
	# [файл, ids, ракурс: "rear"/"front"/"side"/"top", маркеры фар?]
	_jobs = [
		["exhaust_rear.png", ["gz24_white-x7", "vz05_yellow-x8", "vz01_red-x6", "vz03_white-x7"], "rear", false],
		["exhaust_rear2.png", ["vz06_sand-x6", "vz07_purple-x8", "vz09_lightblue-x8", "vz31_green-x7"], "rear", false],
		["spoiler_rear.png", ["vz08_blue-s7", "vz08_blue-s2", "vz09_lightblue-s9", "vz099_black-s10"], "rear", false],
		["headlights.png", ["vz05r_red", "vz05_yellow", "vz03_white", "vz099_black"], "front", true],
		["headlights2.png", ["gz21_white", "gz24_black", "vz31_green", "vz21_green"], "front", true],
		["neon_side.png", ["vz01_red-nred", "ac3-yellow2-ncyan", "fastback-ngreen", "vz31_green-npurple"], "side", false],
		["buggy_line.png", ["ac3-yellow2-l1", "ac3-yellow2-l1-e5", "ac3-yellow2-l1-s5", "ac3-yellow2-l1-e5-s5-w3"], "top", false],
		["arcade_line.png", ["ac1-red2-l1", "ac2-cyan2-l1", "ac4-green2-l1", "ac6-purple2-l1"], "top", false],
		["line_all.png", ["vz01_red-l1", "vz08_blue-l1-plyellow2", "fastback-l1", "gz24_white-l1-plred2"], "top", false],
		["glass.png", ["vz01_red-tcyan", "vz05_yellow-tblack", "fastback-tred", "ac3-yellow2-tpurple"], "front", false],
		["glass2.png", ["gz24_white-twhite", "vz08_blue-tyellow", "diablo-tgreen", "ac1-red2-tcyan"], "side", false],
		["neon_bw.png", ["vz01_red-nwhite", "vz01_red-nblack", "ac3-yellow2-nwhite", "vz31_green-nblack"], "side", false],
	]


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame % 6 != 0 or _busy:
		return
	if _jobs.is_empty():
		get_tree().quit(0)
		return
	_busy = true
	var job: Array = _jobs.pop_front()
	_show(job)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out + "/" + String(job[0]))
	print("SHOT ", job[0])
	_busy = false


func _show(job: Array) -> void:
	for c in _holder.get_children():
		c.free()
	var ids: Array = job[1]
	var view: String = job[2]
	var marks: bool = job[3]
	for i in ids.size():
		var car := CarModelLibrary.build(String(ids[i]), 3.2, 0.0)
		if car == null:
			print("нет машины ", ids[i])
			continue
		var slot := Node3D.new()
		slot.position = Vector3((i - 1.5) * 3.1, 0, 0)
		print("  built %s -> %s" % [ids[i], car.name])
		_holder.add_child(slot)
		slot.add_child(car)
		if marks:
			var a := Car.headlight_anchor(car, car.transform)
			if a.is_empty():
				print("якорь фар не найден: ", ids[i])
			else:
				for sx in [-1.0, 1.0]:
					var mk := MeshInstance3D.new()
					var bm := BoxMesh.new()
					bm.size = Vector3(a["w"], a["w"] * 0.5, 0.08)
					mk.mesh = bm
					var mm := StandardMaterial3D.new()
					mm.albedo_color = Color(1, 0.1, 0.1)
					mm.emission_enabled = true
					mm.emission = Color(1, 0.2, 0.2)
					mk.material_override = mm
					mk.position = Vector3(sx * a["x"], a["y"], a["z"] + 0.02)
					slot.add_child(mk)
	match view:
		"rear":
			_cam.look_at_from_position(Vector3(0, 1.7, 5.6), Vector3(0, 0.45, 0))
		"front":
			_cam.look_at_from_position(Vector3(0, 1.5, -5.6), Vector3(0, 0.45, 0))
		"side":
			_cam.look_at_from_position(Vector3(0, 0.55, 7.0), Vector3(0, 0.25, 0))
		"top":
			_cam.look_at_from_position(Vector3(0, 8.5, 6.0), Vector3(0, 0.3, 0))
