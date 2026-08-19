class_name TrackBuilder
extends Node3D
## Процедурно строит кольцевую трассу с перепадами высот: рельефную землю,
## полотно дороги (с собственной коллизией), сплошное ограждение по краям,
## трамплины и финишный створ. Всё из кода, без внешних ассетов.

const TRACK_HALF_WIDTH := 9.0   # половина ширины полотна, м
const WALL_HEIGHT := 2.6   # заметно выше высоты прыжка (~1.9 м) — не улететь
const WALL_THICKNESS := 0.5
const SAMPLES := 384            # детализация контура (сэмплов на круг)

const GROUND_SIZE := 280.0      # сторона квадрата земли, м
const GROUND_RES := 104         # ячеек земли по стороне
const SHOULDER := 5.0           # ширина ровной обочины у дороги, м
# Обочина лежит НИЖЕ полотна: сетка земли грубее дороги, и вровень её
# треугольники пробивались сквозь асфальт (z-fighting). Просвет прячет
# ограждение, продлённое вниз на ту же величину.
const GROUND_DROP := 1.2

var _curve := Curve3D.new()
# Предрассчитанные точки контура и векторы «вправо» в каждой из них.
var _pts := PackedVector3Array()
var _rights := PackedVector3Array()


func _ready() -> void:
	_build_curve()
	_sample_frames()
	_build_ground()
	_build_road()
	_build_walls()
	_build_ramps()
	_build_start_line()
	_build_decor()


## Профиль высот в духе Rock'n'Roll Racing: ровные плато на разных уровнях,
## короткие подъёмы между ними и резкие сходы-обрывы (с них — прыжок).
## Пары [доля круга, высота]; между ними — плато или переход.
const HEIGHT_KEYS: Array = [
	[0.00, 0.0],   # старт/финиш — ровная прямая
	[0.14, 0.0],
	[0.24, 7.0],   # подъём на верхнее плато
	[0.42, 7.0],   # верхнее плато
	[0.47, 1.0],   # резкий сход — трамплин с обрыва
	[0.62, 1.0],   # среднее плато
	[0.70, 4.5],   # подъём
	[0.84, 4.5],   # верхнее плато поменьше
	[0.90, 0.0],   # второй сход
	[1.00, 0.0],
]


## Высота по доле круга: внутри плато — константа, на переходах — плавная
## S-кривая (без изломов, но заметно круче синусоиды).
static func _profile_height(t: float) -> float:
	var f := fposmod(t, 1.0)
	for i in range(HEIGHT_KEYS.size() - 1):
		var t0: float = HEIGHT_KEYS[i][0]
		var t1: float = HEIGHT_KEYS[i + 1][0]
		if f >= t0 and f <= t1:
			var h0: float = HEIGHT_KEYS[i][1]
			var h1: float = HEIGHT_KEYS[i + 1][1]
			if is_equal_approx(h0, h1):
				return h0
			return lerpf(h0, h1, smoothstep(0.0, 1.0, (f - t0) / (t1 - t0)))
	return 0.0


## Замкнутый контур трассы: плавная петля переменного радиуса со ступенчатым
## профилем высот. Точки задаются по углу — так гарантированно нет изломов,
## а касательные считаются по-катмулл-ромовски (пропорционально шагу),
## иначе на длинных участках кривая ломается «уголком».
func _build_curve() -> void:
	var count := 56
	var points: Array[Vector3] = []
	for i in count:
		var a := TAU * i / count
		# Радиус «дышит» — получаются широкие дуги и лёгкие шиканы.
		var r := 52.0 + 9.0 * sin(a * 2.0) + 4.0 * sin(a * 3.0 + 1.2) \
				+ 2.0 * sin(a * 5.0 + 0.4)
		var y := _profile_height(float(i) / count)
		points.append(Vector3(cos(a) * r, y, sin(a) * r))

	for p: Vector3 in points:
		_curve.add_point(p)
	# Curve3D.closed появился только в 4.4 — замыкаем кольцо дублем первой точки.
	_curve.add_point(points[0])

	var n := points.size()
	for i in _curve.point_count:
		var prev: Vector3 = points[(i - 1 + n) % n]
		var next: Vector3 = points[(i + 1) % n]
		# Катмулл-Ром: длина касательной = 1/6 хорды между соседями.
		var tangent := (next - prev) / 6.0
		_curve.set_point_in(i, -tangent)
		_curve.set_point_out(i, tangent)


## Равномерно сэмплирует кривую: позиции и перпендикуляры к ходу трассы.
## «Вправо» держим горизонтальным — полотно без бокового наклона.
func _sample_frames() -> void:
	var length := _curve.get_baked_length()
	for i in SAMPLES:
		var off := length * i / SAMPLES
		var pos := _curve.sample_baked(off)
		var ahead := _curve.sample_baked(fmod(off + 0.5, length))
		var dir := (ahead - pos).normalized()
		_pts.append(pos)
		_rights.append(Vector3(dir.x, 0, dir.z).normalized().cross(Vector3.UP)
				* -1.0)


## Квад двумя треугольниками с заданной нормалью.
static func _add_quad(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	normal: Vector3
) -> void:
	st.set_normal(normal)
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


## Высота земли в точке: у трассы — вровень с полотном (ровная обочина),
## дальше плавно уходит вниз и переходит в пологие холмы.
func _ground_height(x: float, z: float) -> float:
	var p := Vector3(x, 0, z)
	var on_curve := _curve.sample_baked(_curve.get_closest_offset(p))
	var d := Vector2(x - on_curve.x, z - on_curve.z).length()
	var edge := TRACK_HALF_WIDTH + SHOULDER
	var base := on_curve.y - GROUND_DROP
	if d <= edge:
		return base
	# За обочиной — склон вниз и рельеф, нарастающий с удалением.
	var away := d - edge
	var blend: float = clampf(away / 22.0, 0.0, 1.0)
	var hills := sin(x * 0.045) * cos(z * 0.052) * 6.0 \
			+ sin((x + z) * 0.021) * 3.0
	return base - away * 0.28 + hills * blend


func _build_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var step := GROUND_SIZE / GROUND_RES
	var half := GROUND_SIZE * 0.5

	# Высоты считаем один раз в узлах сетки — иначе 4 запроса к кривой на ячейку.
	var h := []
	h.resize(GROUND_RES + 1)
	for ix in GROUND_RES + 1:
		var row := PackedFloat32Array()
		row.resize(GROUND_RES + 1)
		var x := -half + ix * step
		for iz in GROUND_RES + 1:
			row[iz] = _ground_height(x, -half + iz * step)
		h[ix] = row

	for ix in GROUND_RES:
		for iz in GROUND_RES:
			var x0 := -half + ix * step
			var x1 := x0 + step
			var z0 := -half + iz * step
			var z1 := z0 + step
			var a := Vector3(x0, h[ix][iz], z0)
			var b := Vector3(x1, h[ix + 1][iz], z0)
			var c := Vector3(x1, h[ix + 1][iz + 1], z1)
			var d := Vector3(x0, h[ix][iz + 1], z1)
			for v in [a, b, c, a, c, d]:
				# Планарная UV по миру: тайл травы 10 м.
				st.set_uv(Vector2(v.x, v.z) * 0.1)
				st.add_vertex(v)
			faces.append_array([a, b, c, a, c, d])
	st.generate_normals()

	var ground := StaticBody3D.new()
	ground.name = "Ground"

	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	# Зелёные поля — трава из Cartoon Tracks Pack.
	mat.albedo_texture = load(
			"res://assets/models/track_env/cartoon/textures/grass_1.png")
	mesh.material_override = mat
	ground.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	col.shape = shape
	ground.add_child(col)

	add_child(ground)


## Полотно трассы: непрерывная лента по кривой с собственной коллизией —
## именно по ней едут машины (земля под ней может уходить вниз).
func _build_road() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var lift := Vector3(0, 0.05, 0)

	for i in SAMPLES:
		var j := (i + 1) % SAMPLES
		var li := _pts[i] - _rights[i] * TRACK_HALF_WIDTH + lift
		var ri := _pts[i] + _rights[i] * TRACK_HALF_WIDTH + lift
		var lj := _pts[j] - _rights[j] * TRACK_HALF_WIDTH + lift
		var rj := _pts[j] + _rights[j] * TRACK_HALF_WIDTH + lift
		var normal := (rj - li).cross(lj - ri).normalized()
		if normal.y < 0.0:
			normal = -normal
		_add_quad(st, li, ri, rj, lj, normal)
		faces.append_array([li, ri, rj, li, rj, lj])

	var body := StaticBody3D.new()
	body.name = "Road"

	var road := MeshInstance3D.new()
	road.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.18, 0.2)
	road.material_override = mat
	body.add_child(road)

	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	col.shape = shape
	body.add_child(col)

	add_child(body)


## Ограждение — два непрерывных «бортика» (внутренняя/внешняя грань + верх),
## коллизия — точная, по тем же треугольникам.
func _build_walls() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	# Юбка вниз: закрывает просвет между полотном и опущенной обочиной.
	var skirt := Vector3(0, GROUND_DROP + 0.4, 0)
	var top := Vector3(0, WALL_HEIGHT + skirt.y, 0)
	var half_t := WALL_THICKNESS * 0.5

	for side: float in [-1.0, 1.0]:
		for i in SAMPLES:
			var j := (i + 1) % SAMPLES
			var ni := _rights[i] * side
			var nj := _rights[j] * side
			var ci := _pts[i] + ni * TRACK_HALF_WIDTH - skirt
			var cj := _pts[j] + nj * TRACK_HALF_WIDTH - skirt
			var ai := ci - ni * half_t   # грань к трассе
			var bi := ci + ni * half_t   # внешняя грань
			var aj := cj - nj * half_t
			var bj := cj + nj * half_t

			var quads: Array = [
				[ai, ai + top, aj + top, aj, -ni],        # к трассе
				[bi, bi + top, bj + top, bj, ni],         # наружу
				[ai + top, bi + top, bj + top, aj + top, Vector3.UP],  # верх
			]
			for q: Array in quads:
				_add_quad(st, q[0], q[1], q[2], q[3], q[4])
				faces.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])

	var body := StaticBody3D.new()
	body.name = "Walls"
	body.add_to_group("walls")  # Car._wall_slide узнаёт стену по группе
	# Слой 2: кузов со стенами сталкивается (mask машины включает 2),
	# а ЛУЧИ ПОДВЕСКИ стены не видят (mask 1) — иначе колёса «едут»
	# по вертикальной стене как по дороге.
	body.collision_layer = 2
	# Стены не упругие: машина не отскакивает, а выравнивается вдоль
	# ограждения и скользит (см. Car._wall_slide).
	body.physics_material_override = PhysicsMaterial.new()
	body.physics_material_override.bounce = 0.0
	body.physics_material_override.friction = 0.1

	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.2, 0.15)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	col.shape = shape
	body.add_child(col)

	add_child(body)


## Пара трамплинов на прямых участках — для фирменных прыжков.
func _build_ramps() -> void:
	var ramp_mat := StandardMaterial3D.new()
	ramp_mat.albedo_color = Color(0.9, 0.75, 0.1)

	var length := _curve.get_baked_length()
	# Трамплины — на кромках обрывов (см. HEIGHT_KEYS): с них слетаешь вниз
	# на следующее плато, как в RnRR.
	for t: float in [0.44, 0.875]:
		var offset := length * t
		var pos := _curve.sample_baked(offset)
		var ahead := _curve.sample_baked(fmod(offset + 2.0, length))
		var dir := (ahead - pos).normalized()

		var ramp := StaticBody3D.new()
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(6.0, 0.4, 5.0)
		mesh.mesh = box
		mesh.material_override = ramp_mat
		ramp.add_child(mesh)

		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box.size
		col.shape = shape
		ramp.add_child(col)

		ramp.position = pos + Vector3(0, 0.4, 0)
		add_child(ramp)
		ramp.look_at(ramp.position + dir)
		ramp.rotate_object_local(Vector3.RIGHT, deg_to_rad(9.0))  # наклон-трамплин


## Стартово-финишный створ: шахматная клетка на полотне. Арка, баннер и
## стартовые огни — модели из ассетов (см. TrackDecor). Коллизий нет.
func _build_start_line() -> void:
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.94, 0.94, 0.94)
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.08, 0.08, 0.09)

	var pos := _curve.sample_baked(0.0)
	var ahead := _curve.sample_baked(2.0)
	var gate := Node3D.new()
	gate.name = "FinishGate"
	add_child(gate)
	gate.position = pos
	gate.look_at(pos + (ahead - pos).normalized())

	# Шахматная лента на асфальте: 14 клеток поперёк × 2 ряда вдоль.
	var cols := 14
	var cell := TRACK_HALF_WIDTH * 2.0 / cols
	for row in 2:
		for c in cols:
			var tile := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(cell, 0.06, cell)
			tile.mesh = box
			tile.material_override = white if (c + row) % 2 == 0 else black
			tile.position = Vector3(
				-TRACK_HALF_WIDTH + cell * (c + 0.5), 0.09,
				(row - 0.5) * cell)
			gate.add_child(tile)


## Декор из готовых ассетов — отдельным узлом (см. TrackDecor.gd).
func _build_decor() -> void:
	TrackDecor.new().build(self)


## Горизонтальное расстояние от точки до оси трассы (для детекта вылета).
func distance_from_axis(world_pos: Vector3) -> float:
	var p := _curve.sample_baked(_curve.get_closest_offset(world_pos))
	return Vector2(world_pos.x - p.x, world_pos.z - p.z).length()


## Точка старта и направление для спавна машины.
func start_transform() -> Transform3D:
	var pos := _curve.sample_baked(0.0)
	var ahead := _curve.sample_baked(3.0)
	var dir := (ahead - pos).normalized()
	var basis := Basis.looking_at(dir)
	# 0.62 м — примерно на длину покоя подвески, чтобы машина не падала
	# с высоты и не подпрыгивала при появлении.
	return Transform3D(basis, pos + Vector3(0, 0.62, 0))


## Точка респавна: ось трассы на 6 м вперёд от ближайшей к world_pos точки
## (вперёд — чтобы не вернуть машину в ту же ловушку, где она застряла,
## например прямо на трамплин).
func respawn_transform(world_pos: Vector3) -> Transform3D:
	var length := _curve.get_baked_length()
	var offset := fposmod(_curve.get_closest_offset(world_pos) + 6.0, length)
	var pos := _curve.sample_baked(offset)
	var ahead := _curve.sample_baked(fposmod(offset + 3.0, length))
	var basis := Basis.looking_at((ahead - pos).normalized())
	# 0.62 м — примерно на длину покоя подвески, чтобы машина не падала
	# с высоты и не подпрыгивала при появлении.
	return Transform3D(basis, pos + Vector3(0, 0.62, 0))
