class_name FxKit
extends RefCounted
## Набор разовых спецэффектов на текстурах Epic Toon FX (белые силуэты
## с альфой — красятся в цвет эффекта). Все функции static: породил узел,
## тот сам отыграл и удалился. Используются поверх FlashFx (вспышки)
## и SparksFx (искры) — кольцо ударной волны, клубы дыма, вспышка
## выстрела, снежный разлёт.

# ВЫДЕЛЕННОМУ СЕРВЕРУ косметика не нужна и ВРЕДНА: headless-рендер на
# каждый созданный меш сыпет в stderr «Parameter m is null» с бэктрейсом.
# Локальный замер: этот поток, уходя в пайп/консоль, стопорил ГЛАВНЫЙ
# поток на 1-2 с (TestLap с 2>/dev/null — ноль фризов, с пайпом — по два
# за заезд); на VDS тот же спам уже включал rate limit journald (см.
# ПРОГРЕСС 2026-08-25). Все static-точки входа эффектов выходят сразу.
# Проверка та же, что в TrackBuilder._headless_server: autoload Net в
# static-контексте недоступен для стендов --script.
static func _skip() -> bool:
	return OS.get_cmdline_user_args().has("--server")


const TEX_RING := "res://assets/fx/ring_shockwave.png"
const TEX_SMOKE := "res://assets/fx/smoke_cloud_2x2.png"
const TEX_SNOW := "res://assets/fx/snowflake.png"
const TEX_MUZZLE := "res://assets/fx/muzzleflash01.png"
const TEX_STARS := "res://assets/fx/star_4x4.png"
const TEX_LIGHTNING := "res://assets/fx/lightning_3x3.png"
const TEX_CONFETTI := "res://assets/fx/confetti_3x3.png"
const TEX_SCORCH := "res://assets/fx/scorch.png"
const TEX_FIRE := "res://assets/fx/fire_6x3.png"


## Кольцо ударной волны: лежит на земле, разлетается от эпицентра до
## radius и тает. Аддитивное — «светится» поверх дороги.
static func ring(parent: Node, pos: Vector3, radius: float, color: Color) -> void:
	if _skip():
		return
	var fx := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	quad.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = load(TEX_RING)
	mat.albedo_color = color
	quad.material = mat
	fx.mesh = quad
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(fx)
	# Чуть над полотном: эффект короткий, на уклоне лёгкое пересечение
	# с дорогой не успевает броситься в глаза.
	fx.global_position = pos + Vector3.UP * 0.25
	fx.scale = Vector3.ONE * 0.2
	var tw := fx.create_tween().set_parallel(true)
	tw.tween_property(fx, "scale", Vector3.ONE, 0.45) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.45) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(fx.queue_free)


## Клубы дыма после взрыва: мультяшные облачка (атлас 2×2, случайный кадр
## каждой частице) лениво всплывают и растворяются.
static func smoke_burst(parent: Node, pos: Vector3, amount := 10,
		size := 1.0) -> void:
	if _skip():
		return
	var fx := CPUParticles3D.new()
	# ВАЖНО: у нового узла emitting=true по умолчанию — при add_child разовый
	# залп (explosiveness) уходит в точке (0,0,0) ДО установки global_position.
	fx.emitting = false
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.amount = amount
	fx.lifetime = 0.9
	fx.local_coords = false
	fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fx.emission_sphere_radius = 0.6
	fx.direction = Vector3.UP
	fx.spread = 60.0
	fx.gravity = Vector3(0.0, 1.6, 0.0)
	fx.initial_velocity_min = 1.6
	fx.initial_velocity_max = 4.0
	fx.damping_min = 2.0
	fx.damping_max = 3.5
	fx.angle_min = 0.0
	fx.angle_max = 360.0
	fx.scale_amount_min = 0.8 * size
	fx.scale_amount_max = 1.4 * size
	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.5))
	growth.add_point(Vector2(0.4, 1.0))
	growth.add_point(Vector2(1.0, 1.25))
	fx.scale_amount_curve = growth
	fx.anim_offset_min = 0.0
	fx.anim_offset_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.particles_anim_h_frames = 2
	mat.particles_anim_v_frames = 2
	mat.particles_anim_loop = false
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = load(TEX_SMOKE)
	quad.material = mat
	fx.mesh = quad
	var grad := Gradient.new()
	grad.set_color(0, Color(0.45, 0.42, 0.4, 0.85))
	grad.set_color(1, Color(0.75, 0.73, 0.72, 0.0))
	fx.color_ramp = grad
	parent.add_child(fx)
	fx.global_position = pos
	fx.emitting = true
	fx.finished.connect(fx.queue_free)


## Снежный разлёт заморозки: бело-голубые снежинки брызгают во все
## стороны и опадают.
static func snow_burst(parent: Node, pos: Vector3, amount := 22) -> void:
	if _skip():
		return
	var fx := CPUParticles3D.new()
	# ВАЖНО: у нового узла emitting=true по умолчанию — при add_child разовый
	# залп (explosiveness) уходит в точке (0,0,0) ДО установки global_position.
	fx.emitting = false
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.amount = amount
	fx.lifetime = 0.8
	fx.local_coords = false
	fx.direction = Vector3.UP
	fx.spread = 85.0
	fx.gravity = Vector3(0.0, -7.0, 0.0)
	fx.initial_velocity_min = 3.0
	fx.initial_velocity_max = 6.5
	fx.angle_min = 0.0
	fx.angle_max = 360.0
	fx.scale_amount_min = 0.6
	fx.scale_amount_max = 1.1
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = load(TEX_SNOW)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.8, 1.0)
	mat.emission_energy_multiplier = 1.6
	quad.material = mat
	fx.mesh = quad
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.95, 1.0, 1.0))
	grad.set_color(1, Color(0.55, 0.8, 1.0, 0.0))
	fx.color_ramp = grad
	parent.add_child(fx)
	fx.global_position = pos
	fx.emitting = true
	fx.finished.connect(fx.queue_free)


## Мультяшные звёзды-контуры от удара: выпрыгивают из точки контакта,
## крутятся и опадают (классика тунов — «искры из глаз» при таране).
## Атлас 4×4 — каждой частице свой случайный вариант звезды.
static func stars_burst(parent: Node, pos: Vector3, amount := 7,
		color := Color(1.0, 0.9, 0.25)) -> void:
	if _skip():
		return
	var fx := CPUParticles3D.new()
	# ВАЖНО: у нового узла emitting=true по умолчанию — при add_child разовый
	# залп (explosiveness) уходит в точке (0,0,0) ДО установки global_position.
	fx.emitting = false
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.amount = amount
	fx.lifetime = 0.7
	fx.local_coords = false
	fx.direction = Vector3.UP
	fx.spread = 75.0
	fx.gravity = Vector3(0.0, -7.0, 0.0)
	fx.initial_velocity_min = 2.5
	fx.initial_velocity_max = 5.5
	fx.angle_min = 0.0
	fx.angle_max = 360.0
	fx.angular_velocity_min = -240.0
	fx.angular_velocity_max = 240.0
	fx.scale_amount_min = 0.9
	fx.scale_amount_max = 1.4
	# Случайный кадр атласа, без прокрутки — просто разные звёзды. Берём
	# только первую половину кадров: у нижних рядов контур слишком тонкий,
	# с игровой камеры такие звёзды не читаются.
	fx.anim_offset_min = 0.0
	fx.anim_offset_max = 0.45
	var quad := QuadMesh.new()
	quad.size = Vector2(0.65, 0.65)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.particles_anim_h_frames = 4
	mat.particles_anim_v_frames = 4
	mat.particles_anim_loop = false
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = load(TEX_STARS)
	quad.material = mat
	fx.mesh = quad
	var grad := Gradient.new()
	grad.set_color(0, color)
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	fx.color_ramp = grad
	parent.add_child(fx)
	fx.global_position = pos
	fx.emitting = true
	fx.finished.connect(fx.queue_free)


## Электрический разряд: угловатые осколки-молнии (атлас 3×3, случайный
## кадр) вспыхивают вокруг точки и мгновенно гаснут. Аддитивные — светятся.
static func lightning_burst(parent: Node, pos: Vector3, color: Color,
		amount := 5, size := 1.0) -> void:
	if _skip():
		return
	var fx := CPUParticles3D.new()
	# ВАЖНО: у нового узла emitting=true по умолчанию — при add_child разовый
	# залп (explosiveness) уходит в точке (0,0,0) ДО установки global_position.
	fx.emitting = false
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.amount = amount
	fx.lifetime = 0.22
	fx.local_coords = false
	fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fx.emission_sphere_radius = 0.7 * size
	fx.spread = 180.0
	fx.gravity = Vector3.ZERO
	fx.initial_velocity_min = 0.0
	fx.initial_velocity_max = 0.6
	fx.angle_min = 0.0
	fx.angle_max = 360.0
	fx.scale_amount_min = 1.1 * size
	fx.scale_amount_max = 1.9 * size
	fx.anim_offset_min = 0.0
	fx.anim_offset_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.particles_anim_h_frames = 3
	mat.particles_anim_v_frames = 3
	mat.particles_anim_loop = false
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = load(TEX_LIGHTNING)
	quad.material = mat
	fx.mesh = quad
	var grad := Gradient.new()
	grad.set_color(0, color)
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	fx.color_ramp = grad
	parent.add_child(fx)
	fx.global_position = pos
	fx.emitting = true
	fx.finished.connect(fx.queue_free)


## Залп конфетти: разноцветные ленточки (цветной атлас 3×3 как есть, без
## перекраски) фонтаном вверх, кружатся и опадают. Праздник на финише.
static func confetti_burst(parent: Node, pos: Vector3, amount := 90) -> void:
	if _skip():
		return
	var fx := CPUParticles3D.new()
	# ВАЖНО: у нового узла emitting=true по умолчанию — при add_child разовый
	# залп (explosiveness) уходит в точке (0,0,0) ДО установки global_position.
	fx.emitting = false
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.amount = amount
	fx.lifetime = 1.6
	fx.local_coords = false
	fx.direction = Vector3.UP
	fx.spread = 55.0
	fx.gravity = Vector3(0.0, -5.0, 0.0)
	fx.initial_velocity_min = 5.0
	fx.initial_velocity_max = 10.0
	fx.damping_min = 1.0
	fx.damping_max = 2.5
	fx.angle_min = 0.0
	fx.angle_max = 360.0
	fx.angular_velocity_min = -420.0
	fx.angular_velocity_max = 420.0
	fx.scale_amount_min = 0.7
	fx.scale_amount_max = 1.1
	fx.anim_offset_min = 0.0
	fx.anim_offset_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.28, 0.28)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.particles_anim_h_frames = 3
	mat.particles_anim_v_frames = 3
	mat.particles_anim_loop = false
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = load(TEX_CONFETTI)
	quad.material = mat
	fx.mesh = quad
	# Текстура цветная — рампа управляет только прозрачностью в конце.
	var grad := Gradient.new()
	grad.set_color(0, Color.WHITE)
	grad.add_point(0.75, Color.WHITE)
	grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	fx.color_ramp = grad
	parent.add_child(fx)
	fx.global_position = pos
	fx.emitting = true
	fx.finished.connect(fx.queue_free)


## Выжженное пятно на месте взрыва: тёмная отметина ложится на полотно
## (луч вниз ищет дорогу — на склоне пятно ляжет по рельефу) и медленно
## растворяется. Чисто косметика, коллизий нет.
static func scorch(parent: Node, pos: Vector3, radius := 2.4) -> void:
	if _skip():
		return
	var up := Vector3.UP
	var ground := pos
	var p3 := parent as Node3D
	var space: PhysicsDirectSpaceState3D = null
	if p3 and p3.is_inside_tree():
		space = p3.get_world_3d().direct_space_state
	if space:
		var q := PhysicsRayQueryParameters3D.create(
				pos + Vector3.UP * 1.5, pos + Vector3.DOWN * 5.0, 1)
		var hit := space.intersect_ray(q)
		if hit:
			ground = hit["position"]
			up = hit["normal"]
	var fx := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	quad.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = load(TEX_SCORCH)
	mat.albedo_color = Color(0.05, 0.04, 0.035, 0.8)
	quad.material = mat
	fx.mesh = quad
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(fx)
	fx.global_position = ground + up * 0.06
	# Развернуть по нормали опоры + псевдослучайный поворот вокруг неё
	# (БЕЗ randf — не сдвигать поток случайных чисел у стендов с seed).
	if up.dot(Vector3.UP) < 0.999:
		fx.global_transform.basis = Basis(Vector3.UP.cross(up).normalized(),
				Vector3.UP.angle_to(up))
	fx.rotate(up, float(fx.get_instance_id() % 628) * 0.01)
	var tw := fx.create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(mat, "albedo_color:a", 0.0, 4.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(fx.queue_free)


## Сноп огня на месте взрыва: языки пламени (атлас 6×3, кадры листаются
## по жизни) коротко полыхают и гаснут. Аддитивные — светятся.
static func fire_burst(parent: Node, pos: Vector3, amount := 14) -> void:
	if _skip():
		return
	var fx := CPUParticles3D.new()
	# ВАЖНО: у нового узла emitting=true по умолчанию — при add_child разовый
	# залп (explosiveness) уходит в точке (0,0,0) ДО установки global_position.
	fx.emitting = false
	fx.one_shot = true
	fx.explosiveness = 0.85
	fx.amount = amount
	fx.lifetime = 0.5
	fx.local_coords = false
	fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fx.emission_sphere_radius = 0.9
	fx.direction = Vector3.UP
	fx.spread = 30.0
	fx.gravity = Vector3(0.0, 2.5, 0.0)
	fx.initial_velocity_min = 1.0
	fx.initial_velocity_max = 2.6
	fx.scale_amount_min = 0.8
	fx.scale_amount_max = 1.4
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.15))
	fx.scale_amount_curve = shrink
	fx.anim_offset_min = 0.0
	fx.anim_offset_max = 1.0
	fx.anim_speed_min = 1.0
	fx.anim_speed_max = 2.0
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.particles_anim_h_frames = 6
	mat.particles_anim_v_frames = 3
	mat.particles_anim_loop = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = load(TEX_FIRE)
	quad.material = mat
	fx.mesh = quad
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	grad.add_point(0.35, Color(1.0, 0.6, 0.1, 1.0))
	grad.set_color(1, Color(0.6, 0.1, 0.02, 0.0))
	fx.color_ramp = grad
	parent.add_child(fx)
	fx.global_position = pos
	fx.emitting = true
	fx.finished.connect(fx.queue_free)


## Вспышка у дула при выстреле снарядом: билборд, «выпрыгивает» и гаснет
## за десятую секунды.
static func muzzle_flash(parent: Node, pos: Vector3, color: Color) -> void:
	if _skip():
		return
	var fx := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 1.5)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = load(TEX_MUZZLE)
	mat.albedo_color = color
	quad.material = mat
	fx.mesh = quad
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(fx)
	fx.global_position = pos
	fx.scale = Vector3.ONE * 0.55
	var tw := fx.create_tween().set_parallel(true)
	tw.tween_property(fx, "scale", Vector3.ONE * 1.15, 0.12)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.12) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(fx.queue_free)
