extends Node3D
## Снимок аркадных деталей на СОВЕТСКИХ машинах (03.09.2026, вечер):
## все 15 машин в два ряда, каждая — с деталями из своего набора
## (CarModelLibrary.SOVIET_PARTS, по последнему варианту слота: самые
## заметные), в цвете по умолчанию. Проверка позиций слотов глазами —
## ручные поправки складываются в SOVIET_SLOT_FIX. Запуск С ОКНОМ:
##   godot --path . res://tools/ShotCrossTuning.tscn -- <папка> [--back] [--pick N]
##   --back  — вид с носа (моторы), без ключа — с кормы (спойлеры, выхлопы)
##   --pick N — N-й вариант слота (1 — первый), без ключа — последний
##   --catalog <slot> [<paint>] — сами детали слота крупно, 10 штук
##   (для подбора наборов), --back — с другой стороны.

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

	var cam := Camera3D.new()
	cam.fov = 55
	add_child(cam)
	var back := args.has("--back")
	var ci := args.find("--catalog")
	if ci >= 0:
		_catalog(args[ci + 1], args[ci + 2] if ci + 2 < args.size() else "grey", back)
		cam.look_at_from_position(Vector3(0, 5.0, 5.5), Vector3(0, 0.2, 0.2))
		return

	var pick := -1
	var pi := args.find("--pick")
	if pi >= 0 and pi + 1 < args.size():
		pick = int(args[pi + 1])
	var ids := CarModelLibrary.SOVIET_IDS
	for k in ids.size():
		var base: String = ids[k]
		var cfg := CarModelLibrary.default_cfg(base)
		for slot in CarModelLibrary.PART_SLOTS:
			var opts := CarModelLibrary.slot_options(base, slot)
			var n := opts.size() - 1
			if pick > 0:
				n = mini(pick, opts.size() - 1)
			cfg[slot] = opts[n]
		var col := k % 8
		var row := k / 8
		# Ряды: дальний (z<0) — 8 машин, ближний — 7; кормой к камере,
		# три четверти. С ключом --back камера с другой стороны.
		_place(CarModelLibrary.tuned_id(base, cfg),
				Vector3(-12.25 + col * 3.5, 0, -2.6 + row * 5.0), -0.6)
	if back:
		cam.look_at_from_position(Vector3(0, 6.0, -11.5), Vector3(0, 0.3, 0.0))
	else:
		cam.look_at_from_position(Vector3(0, 6.0, 11.5), Vector3(0, 0.3, 0.0))


func _place(id: String, at: Vector3, yaw: float) -> void:
	var m := CarModelLibrary.build(id, 3.2, 0.0)
	if m == null:
		print("FAIL build ", id)
		return
	var holder := Node3D.new()
	holder.position = at
	holder.rotation.y = yaw
	holder.add_child(m)
	add_child(holder)


## Сами детали слота крупно: два ряда по пять, серебристая краска.
func _catalog(slot: String, paint: String, back: bool) -> void:
	for i in 10:
		var idx := i + 1
		var mesh := CarModelLibrary._arcade_mesh("%s %d" % [slot.capitalize(), idx])
		if mesh == null:
			print("нет меша ", slot, idx)
			continue
		var part := CarModelLibrary._arcade_part(mesh, "paint:%s20" % paint, 0, 0)
		var col := i % 5
		var row := i / 5
		var holder := Node3D.new()
		holder.position = Vector3(-4.8 + col * 2.4, 0.0, -1.2 + row * 2.4)
		holder.rotation.y = 0.6 if not back else 2.5
		holder.scale = Vector3.ONE * 0.62
		var aabb := mesh.get_aabb()
		part.position = Vector3(-aabb.get_center().x, -aabb.position.y,
				-aabb.get_center().z)
		holder.add_child(part)
		add_child(holder)
		var tag := Label3D.new()
		tag.text = str(idx)
		tag.font_size = 96
		tag.position = Vector3(-4.8 + col * 2.4, 0.05, 0.0 + row * 2.4)
		tag.rotation.x = -PI / 2
		tag.modulate = Color.YELLOW
		add_child(tag)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 12:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var a := OS.get_cmdline_user_args()
		var name := "cross_tuning_back.png" if a.has("--back") else "cross_tuning.png"
		var ci := a.find("--catalog")
		if ci >= 0:
			name = "cat_%s%s.png" % [a[ci + 1], "_back" if a.has("--back") else ""]
		img.save_png(_out + "/" + name)
		print("SHOT " + name)
		get_tree().quit(0)
