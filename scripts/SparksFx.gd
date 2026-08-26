class_name SparksFx
extends CPUParticles3D
## Одноразовый сноп искр — столкновение машин: жёлто-оранжевые точки
## разлетаются из точки удара и гаснут, падая. Сила снопа — от скорости
## сближения. Узел сам удаляется, когда все частицы погасли.


static func spawn(parent: Node, pos: Vector3, power: float) -> void:
	# Выделенному серверу косметика не нужна и вредна (см. FxKit._skip).
	if FxKit._skip():
		return
	var fx := SparksFx.new()
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.amount = 14 + int(clampf(power, 0.0, 12.0)) * 2
	fx.lifetime = 0.4
	fx.local_coords = false
	fx.direction = Vector3.UP
	fx.spread = 70.0
	var v := clampf(3.0 + power * 0.5, 3.0, 10.0)
	fx.initial_velocity_min = v * 0.5
	fx.initial_velocity_max = v
	fx.gravity = Vector3(0.0, -22.0, 0.0)
	fx.scale_amount_min = 0.6
	fx.scale_amount_max = 1.1
	fx.angle_min = 0.0     # случайный поворот звёздочки
	fx.angle_max = 360.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.34, 0.34)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Мультяшная звёздочка-искра из Epic Toon FX (белая — красится ramp).
	mat.albedo_texture = load("res://assets/fx/sparkle.png")
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.2)
	mat.emission_energy_multiplier = 2.5
	quad.material = mat
	fx.mesh = quad
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.92, 0.55, 1.0))
	grad.set_color(1, Color(1.0, 0.45, 0.1, 0.0))
	fx.color_ramp = grad
	parent.add_child(fx)
	fx.global_position = pos
	fx.emitting = true
	fx.finished.connect(fx.queue_free)
