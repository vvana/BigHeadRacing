extends Node3D
## Стенд МАСКИ МАСЛЯНОЙ КЛЯКСЫ (09.09): зона срабатывания пятна — тело
## картинки, а не круг. Проверяем: 1) формула covers() совпадает с UV
## самого QuadMesh FACE_Y (иначе клякса бьёт зеркально картинке);
## 2) центр — накрыт, углы картинки и точки за ней — нет; 3) поворот и
## размер (size_mult) учитываются; 4) наезд в теле → эффект один раз,
## сидящая в пятне машина повторно не бьётся, выход-вход — бьёт снова.
## Запуск: godot --headless --path . res://tools/TestOilMask.tscn
## (сцена, не --script: скрипт-стенд идёт без автозагрузок, а OilSlick тянет
## Car → Net, и компиляция валится).

var _fails := 0
var _n := 0


func _ok(cond: bool, what: String) -> void:
	_n += 1
	if not cond:
		_fails += 1
	print("  %s  %s" % ["ok  " if cond else "FAIL", what])


func _ready() -> void:
	var root := self
	var oil := OilSlick.new()
	oil.inert = true   # без физики машин
	root.add_child(oil)
	await get_tree().process_frame

	# 1) UV квада: у вершины с uv (0,0) — какие знаки x/z?
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	q.orientation = PlaneMesh.FACE_Y
	var arr: Array = q.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var v00 := Vector3.ZERO
	var v11 := Vector3.ZERO
	for i in uvs.size():
		if uvs[i].is_equal_approx(Vector2(0, 0)):
			v00 = verts[i]
		elif uvs[i].is_equal_approx(Vector2(1, 1)):
			v11 = verts[i]
	# covers(): u = 0.5 + x/side, v = 0.5 + z/side → uv (0,0) при x<0, z<0.
	_ok(v00.x < 0.0 and v00.z < 0.0 and v11.x > 0.0 and v11.z > 0.0,
			"UV квада FACE_Y: (0,0) при x<0,z<0; (1,1) при x>0,z>0 — %s / %s"
			% [v00, v11])

	# 2) Центр и края.
	var side: float = OilSlick.QUAD * oil.size_mult
	var xf := oil.global_transform
	_ok(oil.covers(xf.origin), "центр кляксы накрыт")
	var corner := xf * Vector3(side * 0.49, 0.0, side * 0.49)
	_ok(not oil.covers(corner), "угол картинки не накрыт")
	_ok(not oil.covers(xf * Vector3(side * 0.6, 0.0, 0.0)), "за картинкой — нет")
	# Плотность тела: по лучу от центра первые 36 % полустороны (0.18
	# стороны, ≈1.15 м при 6.4 м) накрыты во все стороны — рваный край
	# кляксы начинается дальше.
	var dense := true
	for i in 8:
		var a := float(i) * TAU / 8.0
		for r in [0.05, 0.1, 0.15, 0.18]:
			var p := xf * Vector3(cos(a) * side * r, 0.0, sin(a) * side * r)
			dense = dense and oil.covers(p)
	_ok(dense, "тело кляксы сплошное до 36 % полустороны во все стороны")

	# 3) Поворот и размер: локальные координаты переживают rotation.y.
	oil.rotation.y = 1.3
	oil.size_mult = 1.15
	var xf2 := oil.global_transform
	var side2: float = OilSlick.QUAD * 1.15
	_ok(oil.covers(xf2 * Vector3(side2 * 0.3, 0.0, 0.0))
			and not oil.covers(xf2 * Vector3(side2 * 0.49, 0.0, side2 * 0.49)),
			"после поворота и ×1.15: тело накрыто, угол — нет")

	# 4) Вход в тело — один раз (счётчик через подменённый _on_body).
	var hits := []
	var oil2 := TestOil.new()
	oil2.hits = hits
	root.add_child(oil2)
	var car := Node3D.new()   # заменитель Car: считаем только covers/вход
	root.add_child(car)
	await get_tree().process_frame
	var s3: float = OilSlick.QUAD
	oil2.step_for(car, oil2.global_transform * Vector3(0, 0, 0))
	oil2.step_for(car, oil2.global_transform * Vector3(0.2, 0, 0.1))
	_ok(hits.size() == 1, "вход в тело → один удар (%d)" % hits.size())
	oil2.step_for(car, oil2.global_transform * Vector3(s3 * 0.49, 0, s3 * 0.49))
	oil2.step_for(car, oil2.global_transform * Vector3(0, 0, 0))
	_ok(hits.size() == 2, "выход за тело и снова вход → второй удар (%d)" % hits.size())

	print("OIL MASK TEST: %s (%d/%d)" % ["PASS" if _fails == 0 else "FAIL",
			_n - _fails, _n])
	get_tree().quit(0 if _fails == 0 else 1)


## Пятно со счётчиком: _on_body пишет в hits; step_for повторяет логику
## кадра _physics_process для одного «тела» без физики.
class TestOil extends OilSlick:
	var hits: Array

	func _on_body(body: Node3D) -> void:
		hits.append(body)

	func step_for(body: Node3D, at: Vector3) -> void:
		body.global_position = at
		var id := body.get_instance_id()
		var hit := covers(body.global_position)
		if hit and not bool(_inside.get(id, false)):
			_on_body(body)
		_inside[id] = hit
