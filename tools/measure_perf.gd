extends Node3D
## ЗАМЕР СТОИМОСТИ КАДРА в оффлайн-заезде (29.09.2026): время кадра, вызовы
## отрисовки, объекты и треугольники в кадре на каждой трассе, плюс ОПЫТЫ
## «что будет, если» — ключами стенда, код игры не меняется. Грузит Main
## оффлайн, vsync и потолок кадров сняты (на телефоне vsync не снять — там
## читать кадры/с). Запуск С ОКНОМ:
##   godot --path . --rendering-method gl_compatibility res://tools/MeasurePerf.tscn
##         -- <файл_итога> <трасса> [секунд] [ключи]
## Ключи:
##   --static           все машины стоят на решётке (счётчики повторяются точно);
##                      без него едут, свою ведёт ИИ
##   --census           перепись сцены по группам и сеткам
##   --no-sun-shadow    солнце без тени (верхняя граница)
##   --no-ground-shadow земля и полотно не бросают тень
##   --beam-own         тени фар только у своей машины
##   --no-beam-shadow   фары без теней
##   --no-beams         фары не светят вовсе (как в браузере)
##   --shadow-2048      карта теней солнца 2048, жёсткий фильтр (умолчание мобильных)
##   --scale=0.7        3D в уменьшенном разрешении (проверка: упёрлись ли в пиксели)
##   --no-glow          без свечения (glow)
##   --no-lamp-lights   фонари ночного города не светят (OmniLight3D вне машин)
##   --no-omni          никакого точечного света (фонари и неон машин)
##   --neon=3           у первых трёх машин неон под днищем
##   --no-decor         декор трассы скрыт
##   --no-cars-shadow   машины не бросают тень
##   --shot=<файл.png>  снимок кадра через 5 с после «GO!»
##   --gfx=1            уровень графики из меню настроек (0/1/2)
##   --suite            серия опытов подряд в одном процессе (SUITE ниже); на
##                      Android включается сама — ключей там не передать
## Итог — строки «PERF: …» в консоли (на телефоне — logcat) и в файле.

## Серия 05.10: после замены света фонарей пятнами и без света неона на
## телефоне. До замены: фонари 6 мс кадра, неон у трёх машин 20 мс.
## Полная серия 29.09 — SUITE_FULL.
const SUITE := [
	["neon", "--static", "--gfx=2", "--neon=3"],
	["neon", "--static", "--gfx=1", "--neon=3"],
	["neon", "--gfx=2", "--neon=2"],
	["neon", "--gfx=1", "--neon=2"],
	["grass", "--static", "--gfx=2", "--neon=3"],
	["grass", "--gfx=2", "--neon=2"],
	["space", "--gfx=2", "--neon=2"],
]

const SUITE_FULL := [
	["grass", "--static", "--gfx=2"],
	["grass", "--static", "--gfx=1"],
	["grass", "--static", "--gfx=0"],
	["grass", "--gfx=2"],
	["grass", "--gfx=1"],
	["grass", "--gfx=0"],
	["neon", "--static", "--gfx=2"],
	["neon", "--static", "--gfx=1"],
	["neon", "--static", "--gfx=0"],
	["neon", "--gfx=2"],
	["neon", "--gfx=1"],
	["neon", "--gfx=0"],
	["space", "--gfx=2"],
	["space", "--gfx=1"],
	["space", "--gfx=0"],
]

var _main: Node3D
var _out := "user://perf.txt"
var _kind := "grass"
var _seconds := 30.0
var _flags: Array = []
var _queue: Array = []
var _suite := false
var _go_usec := 0
var _last_usec := 0
var _frames: PackedFloat32Array = []
var _draws: PackedFloat32Array = []
var _objs: PackedFloat32Array = []
var _prims: PackedFloat32Array = []
var _phys_ms: PackedFloat32Array = []
var _proc_ms: PackedFloat32Array = []
var _ticks: PackedFloat32Array = []
var _last_tick := 0
var _prepared := false
var _done := true
var _tag := ""


func _ready() -> void:
	process_physics_priority = -1000   # тик начинается с нас (см. _prof2)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_kind = args[1]
	if args.size() > 2 and args[2].is_valid_float():
		_seconds = float(args[2])
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Car.debug_autodrive = true
	_suite = args.has("--suite") or OS.has_feature("android")
	# --repeat=N: один и тот же опыт N раз подряд в одном процессе (не
	# дорожает ли кадр от перезагрузок сцены).
	for a in args:
		if a.begins_with("--repeat="):
			_suite = true
			var fl := Array(args.slice(3))
			fl.erase(a)
			for _i in int(a.trim_prefix("--repeat=")):
				_queue.append([_kind] + fl)
			_next()
			return
	if _suite:
		_queue = SUITE.duplicate()
		_seconds = 8.0
		print("PERF-SUITE: опытов %d" % _queue.size())
		_next()
	else:
		_flags = Array(args.slice(2))
		_start()


func _next() -> void:
	if _queue.is_empty():
		print("PERF-SUITE: конец")
		get_tree().quit(0)
		return
	var cfg: Array = _queue.pop_front()
	_kind = cfg[0]
	_flags = cfg.slice(1)
	_start()


func _start() -> void:
	if _main != null:
		_main.queue_free()
		_main = null
		await get_tree().process_frame
		await get_tree().process_frame
	# Настройки рендера, которые трогают опыты, — к значениям проекта.
	var size: int = ProjectSettings.get_setting_with_override(
			"rendering/lights_and_shadows/directional_shadow/size")
	var bits: bool = ProjectSettings.get_setting_with_override(
			"rendering/lights_and_shadows/directional_shadow/16_bits")
	var soft: int = ProjectSettings.get_setting_with_override(
			"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality")
	if _flags.has("--shadow-2048"):
		size = 2048
		bits = true
		soft = 0
	RenderingServer.directional_shadow_atlas_set_size(size, bits)
	RenderingServer.directional_soft_shadow_filter_set_quality(soft)
	get_viewport().scaling_3d_scale = 1.0
	for a: String in _flags:
		if a.begins_with("--scale="):
			get_viewport().scaling_3d_scale = float(a.trim_prefix("--scale="))
	# --gfx=N: уровень графики из меню настроек (0 низкая, 1 средняя, 2 макс.).
	for a: String in _flags:
		if a.begins_with("--gfx="):
			GameState.set_gfx_quality(int(a.trim_prefix("--gfx=")))
	_tag = " ".join(_flags)
	_frames.clear()
	_draws.clear()
	_objs.clear()
	_prims.clear()
	_phys_ms.clear()
	_proc_ms.clear()
	_ticks.clear()
	_prepared = false
	GameState.race_size = GameState.RACE_SIZE_MAX
	for a: String in _flags:
		if a.begins_with("--cars="):
			GameState.race_size = int(a.trim_prefix("--cars="))
	_go_usec = 0
	_last_usec = 0
	GameState.track_kind = _kind
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
	_done = false


func _process(_delta: float) -> void:
	if _done or _main == null:
		return
	var now := Time.get_ticks_usec()
	var ms := (now - _last_usec) / 1000.0 if _last_usec > 0 else 0.0
	_last_usec = now
	if _go_usec == 0:
		var cars: Array = _main.get("_cars")
		if cars.is_empty():
			return
		# Модели и опыты — ещё под отсчётом: шейдеры докомпилируются до замера.
		if not _prepared:
			_prepared = true
			_experiments()
		if not (cars[0] as Car).controls_enabled:
			return
		_go_usec = now
		if _flags.has("--static"):
			for c in cars:
				(c as Car).controls_enabled = false
		return
	# Первые четыре секунды после «GO!» не считаем: гаснет отсчёт, рождаются
	# эффекты (первый дым, первые искры).
	if now - _go_usec < 4000000:
		_last_tick = Engine.get_physics_frames()
		return
	_frames.append(ms)
	_ticks.append(float(Engine.get_physics_frames() - _last_tick))
	_last_tick = Engine.get_physics_frames()
	_phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_proc_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_objs.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if now - _go_usec >= int((_seconds + 4.0) * 1000000.0):
		_finish()


## --prof: профиль тика физики. Скрипты машин снимаются с общего обхода и
## зовутся отсюда под секундомером; по отдельности меряются и крупные шаги
## внутри Car._physics_process (зовём их ВТОРОЙ раз вхолостую — машины от
## этого едут чуть иначе, стенд только для замера цены).
var _prof := {}
var _prof_ticks := 0
const PROF_STEPS := ["sync_track_offset", "_track_visual", "_clamp_inside_walls",
		"_touching_wall", "_bounce_off_cars"]


## --prof2: профиль тика БЕЗ повторных вызовов. Все узлы со своим
## _physics_process снимаются с общего обхода и зовутся отсюда под
## секундомером, цена — по имени скрипта. «Движок и прочее» = монитор
## физики минус все скрипты: шаг физического сервера, области, частицы.
var _p2_nodes: Array[Node] = []
var _p2_scan := 0


var _tick_usec := 0
var _tick_frame := -1
var _tick_full: PackedFloat32Array = []


func _prof2(delta: float) -> void:
	# Полная длительность тика (скрипты + шаг физического сервера): интервал
	# между началами соседних тиков ВНУТРИ одного кадра рендера.
	var now := Time.get_ticks_usec()
	if _tick_frame == Engine.get_process_frames() and _tick_usec > 0:
		_tick_full.append((now - _tick_usec) / 1000.0)
	_tick_frame = Engine.get_process_frames()
	_tick_usec = now
	_p2_scan -= 1
	if _p2_scan <= 0:
		_p2_scan = 20
		var stack: Array[Node] = [_main]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			if n.is_physics_processing() and n.has_method("_physics_process"):
				n.set_physics_process(false)
				_p2_nodes.append(n)
	_prof_ticks += 1
	var alive: Array[Node] = []
	for n in _p2_nodes:
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		alive.append(n)
		var scr: Script = n.get_script()
		var key: String = scr.resource_path.get_file() if scr != null else n.get_class()
		var t0 := Time.get_ticks_usec()
		n.call("_physics_process", delta)
		_prof[key] = _prof.get(key, 0) + (Time.get_ticks_usec() - t0)
		_prof["ВСЕ СКРИПТЫ"] = _prof.get("ВСЕ СКРИПТЫ", 0) + (Time.get_ticks_usec() - t0)
	_p2_nodes = alive


func _physics_process(delta: float) -> void:
	if _flags.has("--prof2") and _go_usec != 0 and not _done and _main != null:
		_prof2(delta)
		return
	if not _flags.has("--prof") or _go_usec == 0 or _done or _main == null:
		return
	var cars: Array = _main.get("_cars")
	_prof_ticks += 1
	if _main.is_physics_processing():
		_main.set_physics_process(false)
	var m0 := Time.get_ticks_usec()
	_main._physics_process(delta)
	_prof["заезд (Main)"] = _prof.get("заезд (Main)", 0) + (Time.get_ticks_usec() - m0)
	for c: Car in cars:
		if c.is_physics_processing():
			c.set_physics_process(false)
		var t0 := Time.get_ticks_usec()
		c._physics_process(delta)
		var t1 := Time.get_ticks_usec()
		var key := "машина: бот" if not c.is_player else "машина: своя (ИИ)"
		_prof[key] = _prof.get(key, 0) + (t1 - t0)
		_prof["машины всего"] = _prof.get("машины всего", 0) + (t1 - t0)
		for step: String in PROF_STEPS:
			var a := Time.get_ticks_usec()
			c.call(step)
			_prof["  шаг " + step] = _prof.get("  шаг " + step, 0) \
					+ (Time.get_ticks_usec() - a)
		var a2 := Time.get_ticks_usec()
		c.call("_apply_suspension", delta)
		_prof["  шаг _apply_suspension"] = _prof.get("  шаг _apply_suspension", 0) \
				+ (Time.get_ticks_usec() - a2)
		a2 = Time.get_ticks_usec()
		c.call("_wall_slide", delta)
		_prof["  шаг _wall_slide"] = _prof.get("  шаг _wall_slide", 0) \
				+ (Time.get_ticks_usec() - a2)
		a2 = Time.get_ticks_usec()
		c.call("_ai_allowed_speed", c.track._curve,
				c.track._curve.get_baked_length(), c.track_offset)
		_prof["  шаг _ai_allowed_speed"] = _prof.get("  шаг _ai_allowed_speed", 0) \
				+ (Time.get_ticks_usec() - a2)
		a2 = Time.get_ticks_usec()
		c.call("_tick_effects", 0.0)
		_prof["  шаг _tick_effects"] = _prof.get("  шаг _tick_effects", 0) \
				+ (Time.get_ticks_usec() - a2)
		a2 = Time.get_ticks_usec()
		c.call("_skid_surface_ok", c.global_position)
		_prof["  шаг _skid_surface_ok"] = _prof.get("  шаг _skid_surface_ok", 0) \
				+ (Time.get_ticks_usec() - a2)


func _prof_report() -> String:
	var out := "PROF тиков %d; тик целиком: медиана %.2f мс, среднее %.2f мс (замеров %d); мкс на тик:\n" % [
			_prof_ticks, _pct(_tick_full, 0.5), _avg(_tick_full), _tick_full.size()]
	_tick_full.clear()
	var keys := _prof.keys()
	keys.sort()
	for k in keys:
		out += "PROF   %-36s %8.0f\n" % [k, float(_prof[k]) / maxf(_prof_ticks, 1)]
	return out


func _experiments() -> void:
	var cars: Array = _main.get("_cars")
	# Машины ботов — случайные (CarModelLibrary.shuffled_bot_pool, свой RNG),
	# а весят они от 3 до 92 тыс. треугольников: для сравнения «до/после»
	# ставим всем одни и те же модели.
	# --neon=K: у первых K машин неон под днищем (у ботов в игре он выпадает
	# с шансом 1/4 — без ключа стенд мерил бы заезд вовсе без неона).
	var neon_cars := 0
	for a: String in _flags:
		if a.begins_with("--neon="):
			neon_cars = int(a.trim_prefix("--neon="))
	for i in cars.size():
		var id: String = CarModelLibrary.CAR_IDS[(i * 5) % CarModelLibrary.CAR_IDS.size()]
		if i < neon_cars:
			var cfg := CarModelLibrary.parse_cfg(id)
			cfg["neon"] = "cyan"
			id = CarModelLibrary.tuned_id(String(cfg["base"]), cfg)
		_main.call("_set_car_model", cars[i], id)
	var stack: Array[Node] = [_main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var car: Node = n
		while car != null and not (car is Car):
			car = car.get_parent()
		if n is DirectionalLight3D:
			if _flags.has("--no-sun-shadow"):
				(n as DirectionalLight3D).shadow_enabled = false
		elif n is SpotLight3D:
			if _flags.has("--no-beams"):
				(n as SpotLight3D).visible = false
			if _flags.has("--no-beam-shadow"):
				(n as SpotLight3D).shadow_enabled = false
			elif _flags.has("--beam-own") and car != cars[0]:
				(n as SpotLight3D).shadow_enabled = false
		elif n is OmniLight3D:
			if _flags.has("--no-omni") \
					or (_flags.has("--no-lamp-lights") and car == null):
				(n as OmniLight3D).visible = false
		elif n is WorldEnvironment:
			if _flags.has("--no-glow"):
				(n as WorldEnvironment).environment.glow_enabled = false
		elif n is GeometryInstance3D:
			var par := n.get_parent()
			if _flags.has("--no-ground-shadow") and par != null \
					and (par.name == "Ground" or par.name == "Road"):
				(n as GeometryInstance3D).cast_shadow = \
						GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if _flags.has("--no-cars-shadow") and car != null:
				(n as GeometryInstance3D).cast_shadow = \
						GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if (n is CPUParticles3D or n is GPUParticles3D) 				and _flags.has("--no-particles"):
			(n as Node3D).visible = false
		if n is RigidBody3D and _flags.has("--no-ccd"):
			(n as RigidBody3D).continuous_cd = false
		if n is Area3D and _flags.has("--no-areas"):
			(n as Area3D).monitoring = false
			(n as Area3D).monitorable = false
		if n.name == "Decor" and n is Node3D and _flags.has("--no-decor"):
			(n as Node3D).visible = false
	# --ground-shadow-on: земля бросает тень, как до 29.09 (снимок «до»);
	# --look-ratio=0.3: камера смотрит на ось трассы у этой доли круга;
	# --look=x,y,z: камера смотрит в точку.
	if _flags.has("--ground-shadow-on"):
		for c in _main.get_node("Track/Ground").get_children():
			if c is GeometryInstance3D:
				(c as GeometryInstance3D).cast_shadow = 						GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for a: String in _flags:
		var at := Vector3.INF
		if a.begins_with("--look-ratio="):
			var curve: Curve3D = _main.get_node("Track").get("_curve")
			at = curve.sample_baked(curve.get_baked_length()
					* float(a.trim_prefix("--look-ratio=")))
		elif a.begins_with("--look="):
			var v := a.trim_prefix("--look=").split_floats(",")
			at = Vector3(v[0], v[1], v[2])
		if at != Vector3.INF:
			var aim := Node3D.new()
			_main.add_child(aim)
			aim.global_position = at
			var cam := _main.get_node("IsoCamera") as IsoCamera
			cam.target = aim
	for a: String in _flags:
		if a.begins_with("--shot="):
			_shot_later(a.trim_prefix("--shot="))


func _shot_later(path: String) -> void:
	await get_tree().create_timer(5.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


static func _avg(a: PackedFloat32Array) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxf(a.size(), 1.0)


static func _pct(a: PackedFloat32Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[clampi(int(b.size() * p), 0, b.size() - 1)]


static func _tris(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			n += (idx as PackedInt32Array).size() / 3
		else:
			n += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


## Перепись сцены: что именно лежит в кадре — по группам (машины / ветка
## трассы / прочее) и по сеткам: число узлов, поверхностей (≈ вызовов
## отрисовки на проход), треугольников, сколько из них бросает тень.
func _census() -> String:
	var groups := {}
	var meshes := {}
	var tri_cache := {}
	var stack: Array[Node] = [_main]
	var lights := 0
	var particles := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Light3D and (n as Light3D).is_visible_in_tree():
			lights += 1
		if (n is CPUParticles3D or n is GPUParticles3D) \
				and (n as Node3D).is_visible_in_tree():
			particles += 1
		var mesh: Mesh = null
		var count := 1
		if n is MeshInstance3D:
			mesh = (n as MeshInstance3D).mesh
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
			mesh = (n as MultiMeshInstance3D).multimesh.mesh
			count = (n as MultiMeshInstance3D).multimesh.instance_count
		if mesh == null or not (n as Node3D).is_visible_in_tree():
			continue
		if not tri_cache.has(mesh):
			tri_cache[mesh] = _tris(mesh)
		var tris: int = tri_cache[mesh] * count
		# Группа: машина целиком либо второй уровень под Main (ветка трассы).
		var g := "?"
		var p: Node = n
		while p != null and p != _main:
			if p is Car:
				g = "МАШИНЫ"
				break
			if p.get_parent() != null and p.get_parent().get_parent() == _main:
				g = "%s/%s" % [p.get_parent().name, p.name]
			elif p.get_parent() == _main and g == "?":
				g = str(p.name)
			p = p.get_parent()
		var shadow := (n as GeometryInstance3D).cast_shadow \
				!= GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var e: Array = groups.get(g, [0, 0, 0, 0])
		e[0] += 1
		e[1] += mesh.get_surface_count()
		e[2] += tris
		e[3] += tris if shadow else 0
		groups[g] = e
		var key := mesh.resource_path if mesh.resource_path != "" else \
				"%s <%s>" % [mesh.resource_name, n.name]
		var m: Array = meshes.get(key, [0, 0, 0])
		m[0] += count
		m[1] += tris
		m[2] = mesh.get_surface_count()
		meshes[key] = m
	var out := "  источников света %d, эмиттеров частиц %d\n" % [lights, particles]
	out += _ground_slope()
	var gk := groups.keys()
	gk.sort_custom(func(a, b): return groups[a][2] > groups[b][2])
	for k in gk.slice(0, 25):
		out += "  ГРУППА %-40s узлов %4d, поверхностей %4d, треуг. %7d (в тень %7d)\n" % [
				k, groups[k][0], groups[k][1], groups[k][2], groups[k][3]]
	var mk := meshes.keys()
	mk.sort_custom(func(a, b): return meshes[a][1] > meshes[b][1])
	for k in mk.slice(0, 25):
		out += "  СЕТКА %-60s штук %4d, поверхн. %2d, треуг. %7d\n" % [
				str(k).right(60), meshes[k][0], meshes[k][2], meshes[k][1]]
	return out


## Может ли земля что-то затенить: самый крутой склон её сетки против
## высоты солнца над горизонтом. Поле высот со склонами положе луча солнца
## не затеняет ни себя, ни то, что стоит на нём или выше.
func _ground_slope() -> String:
	var ground := _main.get_node_or_null("Track/Ground")
	var sun: DirectionalLight3D = null
	for c in _main.get_children():
		if c is DirectionalLight3D:
			sun = c
	if ground == null or sun == null:
		return "  земля/солнце не найдены\n"
	var steep := 0.0
	var tris := 0
	var away := 0
	var worst := 90.0
	var where := Vector3.ZERO
	var to_sun := sun.global_transform.basis.z.normalized()
	for mi in ground.get_children():
		if not (mi is MeshInstance3D):
			continue
		var m: Mesh = (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var v: PackedVector3Array = m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for i in range(0, v.size() - 2, 3):
				var n := (v[i + 1] - v[i]).cross(v[i + 2] - v[i])
				if n.length() < 1e-9:
					continue
				n = n.normalized()
				if n.y < 0.0:
					n = -n
				steep = maxf(steep, rad_to_deg(acos(clampf(n.y, 0.0, 1.0))))
				# Грань, отвернувшаяся от солнца, — складка в виде от солнца:
				# за ней может лежать тень.
				var facing := rad_to_deg(asin(clampf(n.dot(to_sun), -1.0, 1.0)))
				if facing < worst:
					worst = facing
					where = (v[i] + v[i + 1] + v[i + 2]) / 3.0
				if facing < 3.0:
					away += 1
				tris += 1
	var elev := rad_to_deg(asin(clampf(to_sun.y, -1.0, 1.0)))
	return "  ЗЕМЛЯ: треугольников %d, самый крутой склон %.1f°, солнце над горизонтом %.1f°; граней, отвернувшихся от солнца (угол к лучу < 3°): %d, худшая %.1f° в точке %s\n" % [
			tris, steep, elev, away, worst, str(where.snapped(Vector3.ONE))]


func _finish() -> void:
	_done = true
	var line := "PERF: трасса=%s [%s] | кадр ср %.2f мс (%.1f к/с), медиана %.2f, 99%% %.2f, худший %.1f | тиков физики на кадр %.2f, монитор physics %.2f мс, process %.2f мс | вызовов отрисовки ср %.0f (макс %.0f), объектов ср %.0f, треугольников ср %.0f тыс. | узлов %d, видеопамять %.0f МБ" % [
		_kind, _tag,
		_avg(_frames), 1000.0 / maxf(_avg(_frames), 0.001), _pct(_frames, 0.5),
		_pct(_frames, 0.99), _pct(_frames, 1.0),
		_avg(_ticks), _pct(_phys_ms, 0.5), _pct(_proc_ms, 0.5),
		_avg(_draws), _pct(_draws, 1.0), _avg(_objs), _avg(_prims) / 1000.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0]
	print(line)
	if _flags.has("--census"):
		line += "\n" + _census()
	if _flags.has("--prof2"):
		_p2_nodes.clear()
		_p2_scan = 0
	if _flags.has("--prof") or _flags.has("--prof2"):
		line += "\n" + _prof_report()
		print(_prof_report())
		_prof.clear()
		_prof_ticks = 0
	var f := FileAccess.open(_out, FileAccess.READ_WRITE if FileAccess.file_exists(_out)
			else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(line)
		f.close()
	if _suite:
		_next()
	else:
		get_tree().quit(0)
