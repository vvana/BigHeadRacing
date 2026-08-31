class_name LaserFx
extends MeshInstance3D
## Визуал лазерного луча: светящийся красный стержень от носа машины
## вперёд, тает за полсекунды. Урон наносит Car.use_weapon — тут
## только картинка.
##
## Луч ЕДЕТ ВМЕСТЕ СО СТРЕЛЯВШИМ (source): он привязан к носу машины, а не
## к точке выстрела. Раньше стержень оставался висеть там, где нажали, и
## на скорости 40 м/с машина за треть секунды уезжала от собственного луча
## на десяток метров — «лазер остаётся на том месте, где применили»
## (жалоба 31.08).

const LIFETIME := 0.55   # было 0.3 — луч не успевали разглядеть

var _source: Car = null
var _dir := Vector3.FORWARD
var _length := 70.0


static func spawn(parent: Node, from: Vector3, dir: Vector3, length: float,
		source: Car = null) -> void:
	# Выделенному серверу косметика не нужна и вредна (см. FxKit._skip).
	if FxKit._skip():
		return
	var fx := LaserFx.new()
	fx._source = source
	fx._dir = dir
	fx._length = length
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
	fx._aim(from)
	var tw := fx.create_tween()
	# Гаснет не сразу: первую половину жизни луч держит яркость, дальше
	# тает — так его видно и стрелявшему, и жертве.
	tw.tween_interval(LIFETIME * 0.45)
	tw.tween_property(mat, "albedo_color:a", 0.0, LIFETIME * 0.55)
	tw.tween_callback(fx.queue_free)


## Каждый кадр — от НОСА машины по её нынешнему курсу. Машина уехала из
## сцены (или её нет вовсе — стенды, эхо чужого выстрела) — луч остаётся
## там, где нарисован.
func _process(_delta: float) -> void:
	if _source == null or not is_instance_valid(_source) \
			or not _source.is_inside_tree():
		return
	var fwd := -_source.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 1e-6:
		_dir = fwd.normalized()
	# От ВИДИМОГО положения машины: тело шагает с частотой физики, и луч,
	# посаженный на него, дрожал бы относительно модели.
	_aim(_source.visual_origin() + Vector3.UP * 0.5)


func _aim(from: Vector3) -> void:
	global_position = from + _dir * (_length * 0.5)
	look_at(from + _dir * _length)
