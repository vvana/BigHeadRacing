extends Node3D
## ПРОБА (04.09.2026): двойная полоса вдоль кузова на НЕаркадных машинах
## (советские и Unity) — вопрос «полосы вдоль кузова можно в тюнинг всем
## машинам добавить?». У аркадных полоса сидит в UV-развёртке кузова
## («sticker line»), у остальных такой развёртки нет — тут полоса
## рисуется шейдером по ЛОКАЛЬНЫМ координатам меша на ДУБЛЕ меша кузова
## (material_overlay в Godot 4.3 Forward+ не рисуется вовсе — проверено и
## шейдером, и StandardMaterial3D; дубль приподнят по нормали на 4 мм):
## |x − cx| в двух полосах, только на верхних гранях (normal.y > порога),
## стёкла: у советских — клетка палитры (56, 81, 79) по UV, у Unity-машин
## — поверхности «glass»/«Black-T» материалом-невидимкой.
## Игровой код не трогается. Запуск С ОКНОМ:
##   godot --path . res://tools/ShotLineAll.tscn -- <папка> [--noglass]
##   [--solid | --asoverride | --overlay | --stdoverlay] — отладка отрисовки

const IDS: Array[String] = [
	"vz01_red", "vz21_green", "gz24_white", "vz08_blue",
	"fastback", "diablo", "safari", "ac3-yellow2-l1",
]
const SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec4 color : source_color = vec4(0.11, 0.11, 0.11, 1.0);
uniform float cx = 0.0;
uniform float half_w = 0.1;
uniform float gap = 0.05;
uniform float min_ny = 0.35;
uniform bool mask_glass = false;
uniform float lift = 0.0;
uniform sampler2D albedo_tex;
varying vec3 lpos;
varying vec3 lnorm;
void vertex() {
	lpos = VERTEX;
	lnorm = NORMAL;
	VERTEX += NORMAL * lift;
}
void fragment() {
	float dx = abs(lpos.x - cx);
	if (dx < gap || dx > gap + 2.0 * half_w || lnorm.y < min_ny) {
		discard;
	}
	if (mask_glass) {
		// Стекло советского пака — одна клетка палитры (56, 81, 79);
		// сэмплер без source_color, сравниваем сырые значения (NEAREST).
		vec3 t = texture(albedo_tex, UV).rgb;
		if (distance(t, vec3(56.0, 81.0, 79.0) / 255.0) < 0.04) {
			discard;
		}
	}
	ALBEDO = color.rgb;
	ROUGHNESS = 0.5;
	METALLIC = 0.0;
}
"""

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

	var sh := Shader.new()
	sh.code = SHADER
	var colors := [Color(0.11, 0.11, 0.11), Color(1, 1, 1), Color(1, 0, 0),
			Color(1, 1, 0), Color(0.11, 0.11, 0.11), Color(1, 1, 1),
			Color(0, 1, 1), Color.WHITE]
	for i in IDS.size():
		var id := IDS[i]
		var car := CarModelLibrary.build(id, 3.2, 0.0)
		if car == null:
			continue
		car.position = Vector3((i % 4 - 1.5) * 4.6, 0, -5.0 * (i / 4))
		car.rotation.y += 0.35
		add_child(car)
		if not CarModelLibrary.is_arcade(CarModelLibrary.base_id(id)):
			_apply_line(car, sh, colors[i], not args.has("--noglass"))

	var cam := Camera3D.new()
	cam.fov = 50
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 6.2, 6.8), Vector3(0, 0.3, -2.4))


## Полоса оверлеем на все меши кузова (не колёса): полуширина полосы —
## 5 % ширины кузова, зазор — 3 %, в ЕДИНИЦАХ ФАЙЛА (локальные координаты
## меша, контейнер масштабируется целиком).
func _apply_line(car: Node3D, sh: Shader, color: Color, glass: bool) -> void:
	var aabb := AABB()
	var first := true
	var bodies: Array[MeshInstance3D] = []
	for c in car.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var a: AABB = mi.transform * mi.mesh.get_aabb()
			aabb = a if first else aabb.merge(a)
			first = false
			bodies.append(mi)
	if first:
		return
	for mi in bodies:
		var m := ShaderMaterial.new()
		m.shader = sh
		# Центр — в локальных координатах меша (у советских xform ≈ I).
		# В FBX из Unity в трансформе меша зашит масштаб 100 (сантиметры) —
		# ширины переводятся в единицы меша через обратный трансформ.
		var inv := mi.transform.affine_inverse()
		var cx_local := inv * Vector3(aabb.get_center().x, 0, 0)
		var kx := inv.basis.get_scale().x
		m.set_shader_parameter("cx", cx_local.x)
		m.set_shader_parameter("half_w", aabb.size.x * 0.05 * kx)
		m.set_shader_parameter("gap", aabb.size.x * 0.03 * kx)
		m.set_shader_parameter("color", color)
		if OS.get_cmdline_user_args().has("--solid"):   # отладка: залить всё
			m.set_shader_parameter("gap", 0.0)
			m.set_shader_parameter("half_w", 1e6)
			m.set_shader_parameter("min_ny", -2.0)
		var mat := mi.material_override
		if mat == null:
			mat = mi.mesh.surface_get_material(0)
			var names := []
			for i in mi.mesh.get_surface_count():
				var sm := mi.mesh.surface_get_material(i)
				names.append(sm.resource_name if sm else "-")
			print("  %s: %s поверхностей %s" % [car.name, mi.name, names])
		if glass and mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture:
			m.set_shader_parameter("mask_glass", true)
			m.set_shader_parameter("albedo_tex", (mat as BaseMaterial3D).albedo_texture)
		var dbg := OS.get_cmdline_user_args()
		if dbg.has("--stdoverlay"):      # отладка: оверлей обычным материалом
			var sm := StandardMaterial3D.new()
			sm.albedo_color = color
			mi.material_overlay = sm
		elif dbg.has("--asoverride"):    # отладка: шейдер вместо базы
			mi.material_override = m
		elif dbg.has("--overlay"):       # material_overlay (в 4.3 не рисуется)
			mi.material_overlay = m
		else:
			# Боевой вариант: ДУБЛЬ меша с шейдером полосы, чуть приподнятый
			# по нормали (4 мм в мире), без тени. У Unity-машин поверхности
			# стёкол/тонировки — материалом-невидимкой.
			m.set_shader_parameter("lift", 0.004 * kx / car.scale.x)
			var dup := MeshInstance3D.new()
			dup.name = mi.name + "_line"
			dup.mesh = mi.mesh
			dup.transform = mi.transform
			dup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if mi.material_override:
				dup.material_override = m
			else:
				for i in mi.mesh.get_surface_count():
					var sm := mi.mesh.surface_get_material(i)
					var nm := (sm.resource_name if sm else "").to_lower()
					if nm.contains("glass") or nm.contains("black-t"):
						var hid := StandardMaterial3D.new()
						hid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
						hid.alpha_scissor_threshold = 0.5
						hid.albedo_color = Color(0, 0, 0, 0)
						dup.set_surface_override_material(i, hid)
					else:
						dup.set_surface_override_material(i, m)
			car.add_child(dup)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame == 12:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var name := "line_all%s.png" % ("_noglass" if OS.get_cmdline_user_args().has("--noglass") else "")
		img.save_png(_out + "/" + name)
		print("SHOT " + name)
		get_tree().quit(0)
