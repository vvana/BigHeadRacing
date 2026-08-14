extends Node3D
## Автотест: позиция в гонке считается по фактической отметке на трассе,
## а не по накопленному пути от места на решётке. ИИ из заднего ряда
## телепортируется на 1 м ПОЗАДИ игрока — место игрока должно остаться 1
## (до фикса задний ряд стартовал с форой прогресса ~5-7 м и HUD
## показывал игроку 2-е место).

var _main: Node3D
var _frames := 0


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames == 5:
		# ИИ2 (задний ряд) — на 1 м позади игрока, в соседней колонне.
		var st: Transform3D = _main._track.start_transform()
		var dir: Vector3 = -st.basis.z
		var ai: Car = _main._cars[2]
		ai.global_position = st.origin - dir * 3.0 + st.basis.x * 2.2
		ai.linear_velocity = Vector3.ZERO
	if _frames < 10:
		return
	var place: int = _main._player_place()
	var ok: bool = place == 1 and _main._progress[0] > _main._progress[2]
	print("POSITION TEST: %s (место=%d, прогресс P=%.1f ИИ2=%.1f)" % [
		"PASS" if ok else "FAIL", place,
		_main._progress[0], _main._progress[2]])
	get_tree().quit(0 if ok else 1)
