class_name SoccerArena
extends Node3D
## Футбольная арена: зелёное поле с бортами (мяч из игры не выходит, как в
## аркадном автофутболе), двое ворот в торцах. Длинная ось — X: слева
## (−X) ворота СИНИХ (команда 0 их защищает), справа (+X) — КРАСНЫХ.
## Всё процедурное, в духе TrackBuilder: земля слой 1, стены слой 2.

const HALF_LEN := 46.0        # половина поля до линии ворот, м
const HALF_WID := 28.0        # половина ширины
const WALL_H := 3.0           # борта
const WALL_T := 0.8
const GOAL_HALF_W := 7.0      # полуширина створа ворот
const GOAL_DEPTH := 5.0       # глубина сетки за линией
const GOAL_H := 4.2           # высота рамки ворот (и стенок короба сетки)

const TEAM_COLORS: Array[Color] = [
	Color(0.25, 0.5, 1.0),    # СИНИЕ (игрок)
	Color(0.95, 0.25, 0.2),   # КРАСНЫЕ
]
const GRASS_A := Color(0.24, 0.52, 0.2)
const GRASS_B := Color(0.21, 0.47, 0.18)
const LINE_COLOR := Color(0.95, 0.95, 0.95)


func _ready() -> void:
	_build_ground()
	_build_walls()
	_build_goal(0)   # ворота СИНИХ у −X
	_build_goal(1)   # ворота КРАСНЫХ у +X
	_build_ceiling()
	if not Net.is_server():
		_build_markings()


## ---- Геометрия для матча и ИИ ----

## Центр СВОИХ ворот команды team (куда ей нельзя пропускать мяч).
func goal_center(team: int) -> Vector3:
	return Vector3(-HALF_LEN if team == 0 else HALF_LEN, 0.0, 0.0)


## Мяч в воротах? Возвращает НОМЕР ЗАБИВШЕЙ команды или -1.
## Гол — когда центр мяча полностью за линией внутри створа.
func goal_at(pos: Vector3) -> int:
	if absf(pos.z) > GOAL_HALF_W or pos.y > GOAL_H:
		return -1
	if pos.x > HALF_LEN + SoccerBall.RADIUS * 0.5:
		return 0   # мяч в правых воротах — забили СИНИЕ
	if pos.x < -HALF_LEN - SoccerBall.RADIUS * 0.5:
		return 1
	return -1


func ball_spawn() -> Vector3:
	return Vector3(0.0, SoccerBall.RADIUS + 0.4, 0.0)


## Кикофф-позиция машины i (0..3 — СИНИЕ, 4..7 — КРАСНЫЕ), носом к центру.
## Роли: 0 — нападающий у мяча, 1-2 — фланги, 3 — вратарь.
func kickoff_car(i: int) -> Transform3D:
	var team := 0 if i < 4 else 1
	var role := i % 4
	var spots: Array[Vector3] = [
		Vector3(-6.0, 0.0, 0.0),
		Vector3(-15.0, 0.0, -9.0),
		Vector3(-15.0, 0.0, 9.0),
		Vector3(-HALF_LEN + 5.0, 0.0, 0.0),
	]
	var pos := spots[role]
	var yaw := -PI / 2   # нос (−Z машины) смотрит в +X
	if team == 1:
		pos.x = -pos.x
		yaw = PI / 2
	pos.y = 0.6
	return Transform3D(Basis(Vector3.UP, yaw), pos)


## ---- Постройка ----

func _static_box(pos: Vector3, size: Vector3, layer: int,
		color := Color.TRANSPARENT, bounce := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	if bounce > 0.0:
		body.physics_material_override = PhysicsMaterial.new()
		body.physics_material_override.bounce = bounce
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	add_child(body)
	if color.a > 0.0 and not Net.is_server():
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mesh.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		if color.a < 1.0:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.85
		mesh.material_override = mat
		body.add_child(mesh)
	return body


func _build_ground() -> void:
	# Опора — один бокс на всё поле с запасом под сетки ворот и зону за
	# бортами (машину, перелетевшую борт, вернёт страховка Soccer).
	_static_box(Vector3(0, -0.5, 0),
			Vector3((HALF_LEN + GOAL_DEPTH + 14.0) * 2.0, 1.0,
					(HALF_WID + 14.0) * 2.0),
			1, Color.TRANSPARENT)
	if Net.is_server():
		return
	# Газон: полосы «стрижки» поперёк поля + тёмная кромка за бортами.
	var strip_n := 10
	var strip_w := HALF_LEN * 2.0 / strip_n
	for k in strip_n:
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(strip_w, 0.04, HALF_WID * 2.0)
		mesh.mesh = bm
		mesh.position = Vector3(-HALF_LEN + strip_w * (k + 0.5), 0.0, 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = GRASS_A if k % 2 == 0 else GRASS_B
		mat.roughness = 1.0
		mesh.material_override = mat
		add_child(mesh)
	var rim := MeshInstance3D.new()
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3((HALF_LEN + GOAL_DEPTH + 14.0) * 2.0, 0.02,
			(HALF_WID + 14.0) * 2.0)
	rim.mesh = rim_mesh
	rim.position.y = -0.02
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.16, 0.34, 0.15)
	rim_mat.roughness = 1.0
	rim.material_override = rim_mat
	add_child(rim)


func _build_walls() -> void:
	var steel := Color(0.32, 0.36, 0.42)
	# Боковые борта во всю длину (с запасом на углы).
	for side in [-1.0, 1.0]:
		_static_box(Vector3(0, WALL_H * 0.5, side * (HALF_WID + WALL_T * 0.5)),
				Vector3(HALF_LEN * 2.0 + WALL_T * 2.0, WALL_H, WALL_T),
				2, steel, 0.5)
	# Торцевые борта — по обе стороны от створа ворот.
	var seg := HALF_WID - GOAL_HALF_W
	for endx in [-1.0, 1.0]:
		for side in [-1.0, 1.0]:
			_static_box(Vector3(endx * (HALF_LEN + WALL_T * 0.5), WALL_H * 0.5,
							side * (GOAL_HALF_W + seg * 0.5)),
					Vector3(WALL_T, WALL_H, seg), 2, steel, 0.5)


## Ворота команды team: короб-сетка за линией, штанги и перекладина в цвет.
func _build_goal(team: int) -> void:
	var sgn := -1.0 if team == 0 else 1.0
	var col := TEAM_COLORS[team]
	var net := Color(0.9, 0.9, 0.95, 0.3)
	var back_x := sgn * (HALF_LEN + GOAL_DEPTH)
	# Задняя стенка, боковины и крыша короба — полупрозрачная «сетка».
	_static_box(Vector3(back_x, GOAL_H * 0.5, 0),
			Vector3(WALL_T, GOAL_H, GOAL_HALF_W * 2.0 + WALL_T * 2.0),
			2, net)
	for side in [-1.0, 1.0]:
		_static_box(Vector3(sgn * (HALF_LEN + GOAL_DEPTH * 0.5), GOAL_H * 0.5,
						side * (GOAL_HALF_W + WALL_T * 0.5)),
				Vector3(GOAL_DEPTH + WALL_T, GOAL_H, WALL_T), 2, net)
	_static_box(Vector3(sgn * (HALF_LEN + GOAL_DEPTH * 0.5), GOAL_H + 0.15, 0),
			Vector3(GOAL_DEPTH + WALL_T, 0.3, GOAL_HALF_W * 2.0 + WALL_T * 2.0),
			2, net)
	if Net.is_server():
		return
	# Штанги и перекладина в цвет команды-хозяйки ворот.
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.28
		cyl.bottom_radius = 0.28
		cyl.height = GOAL_H
		post.mesh = cyl
		post.position = Vector3(sgn * HALF_LEN, GOAL_H * 0.5, side * GOAL_HALF_W)
		post.material_override = _team_mat(col)
		add_child(post)
	var bar := MeshInstance3D.new()
	var bar_mesh := CylinderMesh.new()
	bar_mesh.top_radius = 0.28
	bar_mesh.bottom_radius = 0.28
	bar_mesh.height = GOAL_HALF_W * 2.0 + 0.56
	bar.mesh = bar_mesh
	bar.rotation_degrees = Vector3(90, 0, 0)
	bar.position = Vector3(sgn * HALF_LEN, GOAL_H, 0)
	bar.material_override = _team_mat(col)
	add_child(bar)


func _team_mat(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col * 0.35
	mat.roughness = 0.4
	return mat


## Невидимый потолок: мяч со свечи не улетает за арену насовсем.
func _build_ceiling() -> void:
	_static_box(Vector3(0, 13.0, 0),
			Vector3((HALF_LEN + GOAL_DEPTH) * 2.0 + 4.0, 1.0,
					HALF_WID * 2.0 + 4.0),
			2, Color.TRANSPARENT)


## Белая разметка: центральная линия, круг, точка.
func _build_markings() -> void:
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = LINE_COLOR
	line_mat.roughness = 1.0

	var center := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.35, 0.02, HALF_WID * 2.0)
	center.mesh = cm
	center.position.y = 0.05
	center.material_override = line_mat
	add_child(center)

	var circle := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 8.0
	torus.outer_radius = 8.35
	circle.mesh = torus
	circle.position.y = 0.05
	circle.scale.y = 0.06   # плоское кольцо на газоне
	circle.material_override = line_mat
	add_child(circle)

	var dot := MeshInstance3D.new()
	var dot_mesh := CylinderMesh.new()
	dot_mesh.top_radius = 0.5
	dot_mesh.bottom_radius = 0.5
	dot_mesh.height = 0.02
	dot.mesh = dot_mesh
	dot.position.y = 0.05
	dot.material_override = line_mat
	add_child(dot)

	# Штрафные площади у ворот (прямоугольник линий).
	for sgn in [-1.0, 1.0]:
		var box_w := 24.0   # ширина площади (по Z)
		var box_d := 10.0   # глубина от линии ворот
		for piece: Array in [
			[Vector3(sgn * (HALF_LEN - box_d), 0.05, 0),
					Vector3(0.35, 0.02, box_w)],
			[Vector3(sgn * (HALF_LEN - box_d * 0.5), 0.05, -box_w * 0.5),
					Vector3(box_d, 0.02, 0.35)],
			[Vector3(sgn * (HALF_LEN - box_d * 0.5), 0.05, box_w * 0.5),
					Vector3(box_d, 0.02, 0.35)],
		]:
			var m := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = piece[1]
			m.mesh = bm
			m.position = piece[0]
			m.material_override = line_mat
			add_child(m)
