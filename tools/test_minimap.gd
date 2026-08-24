extends Node3D
## Автотест мини-карты: точки машин стоят на своих местах.
## Проверяем, что карта собралась, все точки лежат внутри панели, машина
## на старте и машина, телепортированная на другую сторону круга, дают
## РАЗНЫЕ точки, а два соседних по трассе места — близкие.

var _main: Node3D
var _frames := 0


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames < 5:
		return
	var map: Minimap = _main._minimap
	if map == null:
		print("MINIMAP TEST: FAIL (карта не собрана)")
		get_tree().quit(1)
		return
	var track: TrackBuilder = _main._track
	var curve: Curve3D = track._curve
	var length := curve.get_baked_length()
	var start := curve.sample_baked(0.0)
	var half := curve.sample_baked(length * 0.5)
	var near := curve.sample_baked(6.0)

	var p_start := map.world_to_px(start)
	var p_half := map.world_to_px(half)
	var p_near := map.world_to_px(near)

	# Все точки — внутри панели (с запасом в радиус точки).
	var inside := true
	for p: Vector2 in [p_start, p_half, p_near]:
		if p.x < -1.0 or p.y < -1.0 or p.x > map.size.x + 1.0 \
				or p.y > map.size.y + 1.0:
			inside = false
	# Противоположные стороны круга далеко друг от друга, соседние — рядом.
	var far := p_start.distance_to(p_half)
	var close := p_start.distance_to(p_near)
	# Машины игрока и ботов дают разные точки (все на решётке, но не в одной).
	var dots := {}
	for c: Car in _main._cars:
		dots[map.world_to_px(c.global_position).round()] = true

	# Главное свойство карты: ОРИЕНТАЦИЯ КАК НА ЭКРАНЕ. Сравниваем, куда
	# сдвиг вдоль трассы уводит машину на экране (проекция камеры) и на
	# карте — углы должны совпасть.
	var cam: Camera3D = _main.get_node("IsoCamera")
	var scr := cam.unproject_position(near) - cam.unproject_position(start)
	var map_dir := map.world_to_px(near) - map.world_to_px(start)
	var angle := rad_to_deg(absf(scr.angle_to(map_dir)))

	var ok: bool = inside and far > map.size.x * 0.3 and close < 20.0 \
			and dots.size() == _main._cars.size() and angle < 3.0
	print("MINIMAP TEST: %s (внутри=%s, противоположные=%.1f px, " % [
			"PASS" if ok else "FAIL", inside, far]
			+ "соседние=%.1f px, точек=%d/%d, расхождение с экраном=%.1f°)" % [
			close, dots.size(), _main._cars.size(), angle])
	get_tree().quit(0 if ok else 1)
