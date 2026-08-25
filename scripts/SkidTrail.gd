class_name SkidTrail
extends MeshInstance3D
## Полоса следа шины на асфальте: лента-стрип, которую машина тянет за
## колесом во время сильного заноса. Пока занос идёт, Car каждый кадр
## зовёт add_point() — лента дорастает; по окончании — finish(): полоса
## какое-то время лежит, затем растворяется и удаляется сама.
## Одна нода — один эпизод заноса одного колеса.

const LIFETIME := 4.0    # сколько след лежит до начала растворения, с
const FADE := 2.5        # длительность растворения, с
const MAX_POINTS := 150  # длиннее ленту не тянем — Car начнёт новую
const MIN_STEP := 0.3    # м; чаще точки не добавляем (лента и так гладкая)
const JUMP_BREAK := 3.0  # м; скачок дальше — телепорт/респавн, рвём ленту
const LIFT := 0.05       # м над полотном — чтобы не мерцало о дорогу

var _left := PackedVector3Array()
var _right := PackedVector3Array()
var _last := Vector3.ZERO
var _has_last := false
var _mat: StandardMaterial3D


static func start(parent: Node) -> SkidTrail:
	var t := SkidTrail.new()
	t._mat = StandardMaterial3D.new()
	t._mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	t._mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	t._mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	t._mat.albedo_color = Color(0.05, 0.05, 0.06, 0.6)
	t.material_override = t._mat
	t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(t)
	return t


## Продлить ленту до точки pos (точка касания колеса с дорогой, normal —
## нормаль полотна там). Вернёт false, когда ленту пора закрыть и начать
## новую (набрала MAX_POINTS или точка ускакала телепортом).
func add_point(pos: Vector3, normal: Vector3, width := 0.22) -> bool:
	if _has_last:
		var step := pos.distance_to(_last)
		if step > JUMP_BREAK:
			return false
		if step < MIN_STEP:
			return true
	if _left.size() >= MAX_POINTS:
		return false
	if not _has_last:
		# Первая точка: направления ещё нет — запомним и подождём вторую.
		_last = pos
		_has_last = true
		return true
	var dir := (pos - _last).normalized()
	var side := dir.cross(normal).normalized() * (width * 0.5)
	if _left.is_empty():
		# Вторая точка даёт направление — теперь можно положить и первую.
		_left.append(_last + normal * LIFT - side)
		_right.append(_last + normal * LIFT + side)
	_left.append(pos + normal * LIFT - side)
	_right.append(pos + normal * LIFT + side)
	_last = pos
	_rebuild()
	return true


func _rebuild() -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in _left.size():
		verts.append(_left[i])
		verts.append(_right[i])
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, arrays)
	mesh = m


## Эпизод заноса кончился: полежать и раствориться. Пустую ленту (занос
## был короче двух точек) убираем сразу.
func finish() -> void:
	if _left.size() < 2:
		queue_free()
		return
	var tw := create_tween()
	tw.tween_interval(LIFETIME)
	tw.tween_property(_mat, "albedo_color:a", 0.0, FADE) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
