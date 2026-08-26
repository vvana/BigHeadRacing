class_name LaserFx
extends MeshInstance3D
## Визуал лазерного луча: светящийся красный стержень от носа машины
## вперёд, тает за треть секунды. Урон наносит Car.use_weapon — тут
## только картинка.


static func spawn(parent: Node, from: Vector3, dir: Vector3, length: float) -> void:
	# Выделенному серверу косметика не нужна и вредна (см. FxKit._skip).
	if FxKit._skip():
		return
	var fx := LaserFx.new()
	var beam := BoxMesh.new()
	beam.size = Vector3(0.22, 0.22, length)
	fx.mesh = beam
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.15, 0.1, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# НЕ unshaded: в unshaded Godot игнорирует emission, и на тёмной
	# ночной трассе луч терялся. Эмиссия сама светит (не зависит от
	# освещения сцены), а HDR-яркость > glow_hdr_threshold зажигает
	# ореол в ночном городе.
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.12, 0.06)
	mat.emission_energy_multiplier = 6.0
	fx.material_override = mat
	parent.add_child(fx)
	fx.global_position = from + dir * (length * 0.5)
	fx.look_at(from + dir * length)
	var tw := fx.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tw.tween_callback(fx.queue_free)
