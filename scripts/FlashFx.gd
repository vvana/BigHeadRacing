class_name FlashFx
extends MeshInstance3D
## Простая вспышка-взрыв: светящаяся сфера раздувается и тает.


static func spawn(parent: Node, pos: Vector3, radius: float, color: Color) -> void:
	var fx := FlashFx.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius * 0.5
	sphere.height = radius
	fx.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fx.material_override = mat
	parent.add_child(fx)
	fx.global_position = pos
	var tw := fx.create_tween()
	tw.set_parallel(true)
	tw.tween_property(fx, "scale", Vector3.ONE * 3.0, 0.35)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(fx.queue_free)
