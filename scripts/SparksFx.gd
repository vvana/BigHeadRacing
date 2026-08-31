class_name SparksFx
extends CPUParticles3D
## Одноразовый сноп искр — столкновение машин: яркие бело-жёлтые точки-
## угольки веером разлетаются из точки удара, быстро падают и гаснут
## вразнобой. Сила снопа — от скорости сближения. Узел сам удаляется,
## когда все частицы погасли.
## Раньше искрой был спрайт-звёздочка (sparkle.png) — переделано по просьбе
## 31.08: «искры должны быть не в виде звёздочек, а в виде искр».


static func spawn(parent: Node, pos: Vector3, power: float) -> void:
	# Выделенному серверу косметика не нужна и вредна (см. FxKit._skip).
	if FxKit._skip():
		return
	var fx := SparksFx.new()
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.amount = 16 + int(clampf(power, 0.0, 12.0)) * 3
	fx.lifetime = 0.45
	fx.lifetime_randomness = 0.5   # угольки гаснут не разом
	fx.local_coords = false
	fx.direction = Vector3.UP
	fx.spread = 65.0
	var v := clampf(4.0 + power * 0.8, 4.0, 15.0)
	fx.initial_velocity_min = v * 0.4
	fx.initial_velocity_max = v
	fx.gravity = Vector3(0.0, -30.0, 0.0)
	fx.damping_min = 1.0           # воздух тормозит уголёк — хвост дуги короче
	fx.damping_max = 4.0
	fx.scale_amount_min = 0.55
	fx.scale_amount_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)   # маленькая яркая точка, не фигурка
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Мягкое круглое свечение (как у хвоста ракеты) — в движении читается
	# как летящая искра; аддитивно, чтобы горела, а не висела наклейкой.
	mat.albedo_texture = load("res://assets/fx/glow1.png")
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.2)
	mat.emission_energy_multiplier = 2.5
	quad.material = mat
	fx.mesh = quad
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.75, 1.0))   # белое ядро вспышки
	grad.set_color(1, Color(1.0, 0.4, 0.08, 0.0))    # остывает в оранжевый
	fx.color_ramp = grad
	parent.add_child(fx)
	fx.global_position = pos
	fx.emitting = true
	fx.finished.connect(fx.queue_free)
