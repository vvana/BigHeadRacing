extends RefCounted
## 2D-окружение трассы из атласов ИИ-художника (tools/gen_env.py):
## «картонки» — изометрические спрайты, стоящие вертикально лицом к игровой
## камере (она никогда не поворачивается, поэтому картонка выглядит
## объёмной, как модель), и плоские куски земли, нарисованные строго сверху.
## Все куски одного атласа — ОДИН меш и один материал: весь мир вокруг
## трассы стоит несколько вызовов отрисовки вместо сотен FBX-моделей.

const FLAT_LIFT := 0.1    # плоские куски над рельефом, м (против мерцания)
const FLAT_GRID := 8      # плоский кусок — сетка N×N по рельефу

var _right: Vector3     # вправо по экрану, горизонтально
var _away: Vector3      # от камеры вглубь сцены, горизонтально
var _stretch: float     # вертикальная картонка видна укороченной в cos(наклон)
var _rise: float        # на сколько м экрана поднимается точка земли за 1 м вглубь
var _sheets := {}       # лист -> {tex, rects, flat, unshaded, size, st, count}


## cam — базис игровой камеры (TrackDecor._iso_basis): x — вправо по
## экрану, z — от сцены к камере. sheets — SHEETS из Env*Atlas.gd.
func _init(cam: Basis, sheets: Dictionary) -> void:
	_right = Vector3(cam.x.x, 0.0, cam.x.z).normalized()
	_away = -Vector3(cam.z.x, 0.0, cam.z.z).normalized()
	# Угол между осью Y камеры и вертикалью = наклон камеры.
	_stretch = 1.0 / maxf(cam.y.dot(Vector3.UP), 0.2)
	_rise = maxf(cam.z.y, 0.1)
	for sheet: String in sheets:
		var d: Array = sheets[sheet]
		var tex: Texture2D = load(String(d[0]))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_sheets[sheet] = {
			"tex": tex, "rects": d[1], "flat": bool(d[2]), "unshaded": bool(d[3]),
			"size": tex.get_size() if tex != null else Vector2.ONE,
			"st": st, "count": 0,
		}


## Направление «к камере» по земле — чтобы выбрать лицевой или тыльный
## вариант трибуны/щита.
func toward_camera() -> Vector3:
	return -_away


## Ширина куска в метрах при данном масштабе.
func width(sheet: String, what: String, scale := 1.0) -> float:
	var r: Array = _sheets[sheet]["rects"][what]
	if bool(_sheets[sheet]["flat"]):
		return float(r[4]) * scale
	return float(r[4]) * scale * float(r[2]) / float(r[3])


## Высота картонки на экране, м.
func height(sheet: String, what: String, scale := 1.0) -> float:
	return float(_sheets[sheet]["rects"][what][4]) * scale


## Поперечник плоского куска (большая сторона), м.
func extent(sheet: String, what: String, scale := 1.0) -> float:
	var r: Array = _sheets[sheet]["rects"][what]
	return float(r[4]) * scale * maxf(1.0, float(r[3]) / float(r[2]))


## Как далеко вглубь сцены (от камеры) картонка высоты h закрывает землю:
## точка земли на d м дальше основания видна на d·_rise м выше по экрану.
func hide_reach(h: float) -> float:
	return h / _rise


## Направление «вглубь сцены» по земле.
func away() -> Vector3:
	return _away


## Направление «вправо по экрану» по земле.
func right() -> Vector3:
	return _right


## Картонка: низ по центру — в точке pos на земле. mirror — отразить по
## горизонтали (для растительности: разнообразие без новых картинок).
func sprite(sheet: String, what: String, pos: Vector3, scale := 1.0,
		mirror := false) -> void:
	var s: Dictionary = _sheets[sheet]
	var r: Array = s["rects"][what]
	var h := float(r[4]) * scale
	var w := h * float(r[2]) / float(r[3])
	var uv := _uv_rect(s, r)
	var u0 := uv.position.x
	var u1 := uv.end.x
	if mirror:
		var t := u0
		u0 = u1
		u1 = t
	var half := _right * (w * 0.5)
	var up := Vector3.UP * (h * _stretch)
	s["count"] = int(s["count"]) + 1
	_quad(s["st"], pos - half + up, pos + half + up, pos + half, pos - half,
			Vector2(u0, uv.position.y), Vector2(u1, uv.position.y),
			Vector2(u1, uv.end.y), Vector2(u0, uv.end.y))


## Плоский кусок с центром center, по рельефу height_at(x, z) -> y, повёрнут
## на angle (рад) вокруг вертикали. Без поворота верх картинки — вглубь
## сцены (от камеры): нарисованное сверху видится игроку «как на листе».
func flat(sheet: String, what: String, center: Vector3, height_at: Callable,
		scale := 1.0, angle := 0.0, grid := FLAT_GRID) -> void:
	var s: Dictionary = _sheets[sheet]
	var r: Array = s["rects"][what]
	var w := float(r[4]) * scale
	var h := w * float(r[3]) / float(r[2])
	var uv := _uv_rect(s, r)
	var ax := _right.rotated(Vector3.UP, angle)
	var ay := _away.rotated(Vector3.UP, angle)
	var pts := []
	for iy in grid + 1:
		var row := []
		var fy := float(iy) / grid
		for ix in grid + 1:
			var fx := float(ix) / grid
			var p := center + ax * ((fx - 0.5) * w) + ay * ((0.5 - fy) * h)
			p.y = float(height_at.call(p.x, p.z)) + FLAT_LIFT
			row.append([p, Vector2(lerpf(uv.position.x, uv.end.x, fx),
					lerpf(uv.position.y, uv.end.y, fy))])
		pts.append(row)
	s["count"] = int(s["count"]) + 1
	for iy in grid:
		for ix in grid:
			var a: Array = pts[iy][ix]
			var b: Array = pts[iy][ix + 1]
			var c: Array = pts[iy + 1][ix + 1]
			var d: Array = pts[iy + 1][ix]
			_quad(s["st"], a[0], b[0], c[0], d[0], a[1], b[1], c[1], d[1])


## Собрать меши и повесить на parent. Картонки тень не отбрасывают и не
## принимают (вертикальная плоскость ловила бы тень полосой); плоские куски
## тень от машин принимают, как сама земля.
func commit(parent: Node3D) -> void:
	for sheet: String in _sheets:
		var s: Dictionary = _sheets[sheet]
		if int(s["count"]) == 0:
			continue
		var st: SurfaceTool = s["st"]
		var mi := MeshInstance3D.new()
		mi.name = "Env_" + sheet
		mi.mesh = st.commit()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = s["tex"]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 1.0
		if bool(s["unshaded"]):
			# Ночные картонки: свет окон и неона нарисован в самой картинке.
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# Нормаль у всех вершин — вверх, как у земли: освещённые куски
		# светлеют и темнеют ровно так же, как земля вокруг.
		mat.disable_receive_shadows = not bool(s["flat"])
		mi.material_override = mat
		parent.add_child(mi)


func _uv_rect(s: Dictionary, r: Array) -> Rect2:
	var size: Vector2 = s["size"]
	return Rect2(float(r[0]) / size.x, float(r[1]) / size.y,
			float(r[2]) / size.x, float(r[3]) / size.y)


## Четырёхугольник a-b-c-d (по часовой, если смотреть с лица).
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	for v: Array in [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [d, ud]]:
		st.set_normal(Vector3.UP)
		st.set_uv(v[1])
		st.add_vertex(v[0])
