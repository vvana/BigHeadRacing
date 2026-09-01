extends Node3D
## Стенд космической трассы (31.08): «в космосе не должно быть строений»,
## «пускай кометы пролетают, и какая-нибудь планета должна быть с кольцом
## как сатурн»; дополнено 01.09 (тематический декор): космическим
## АППАРАТАМ (шаттл на орбите, дрейфующие ускорители) быть можно —
## запрет только на ЗЕМНЫЕ строения. Проверяет:
## 1) у декора есть планета с кольцами (двойное кольцо — минимум 2 тора);
## 2) земных FBX-строений нет (допустимые FBX — разметка на полотне:
##    скобы решётки и стрелки — и космические аппараты shuttle/booster);
## 3) комета прилетает и ДВИЖЕТСЯ (за секунду > 10 м);
## 4) одновременно живёт не больше TrackDecor.COMET_MAX комет;
## 5) шаттл есть и ЛЕТИТ по орбите (за секунду сдвинулся > 3 м).

var _main: Node3D
var _frame := 0
var _decor: Node3D
var _comet: Node3D
var _comet_pos := Vector3.ZERO
var _shuttle: Node3D
var _shuttle_pos := Vector3.ZERO
var _ok := {}


func _ready() -> void:
	GameState.track_kind = TrackBuilder.KIND_SPACE
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_d: float) -> void:
	_frame += 1
	match _frame:
		30:
			_decor = _main._track.get_node("Decor")
			_ok["кольца планеты"] = _decor.find_children(
					"PlanetRing*", "MeshInstance3D", true, false).size() >= 2
			_ok["земных строений нет"] = _decor.find_children("*", "", true, false) \
					.filter(func(n: Node) -> bool:
						var p := n.scene_file_path
						return p != "" and not p.contains("gridline") \
								and not p.contains("Arrow") \
								and not p.contains("space_shuttle") \
								and not p.contains("rocket_booster")) \
					.is_empty()
			var shuttles := _decor.find_children("space_shuttle*", "", false, false)
			if not shuttles.is_empty():
				_shuttle = shuttles[0]
				_shuttle_pos = _shuttle.global_position
		90:
			# Секунда прошла: орбитальная скорость ~7.9 м/с — сдвиг заметный.
			_ok["шаттл летит"] = _shuttle != null \
					and _shuttle.global_position.distance_to(_shuttle_pos) > 3.0
		240:
			# COMET_FIRST = 1.5 c — к 4-й секунде комета обязана прилететь.
			var comets := _decor.find_children("Comet*", "", false, false)
			_ok["комета прилетела"] = not comets.is_empty()
			if not comets.is_empty():
				_comet = comets[0]
				_comet_pos = _comet.global_position
		300:
			_ok["комета летит"] = _comet != null \
					and is_instance_valid(_comet) \
					and _comet.global_position.distance_to(_comet_pos) > 10.0
		900:
			var alive := _decor.find_children("Comet*", "", false, false).size()
			_ok["комет не больше лимита"] = alive <= TrackDecor.COMET_MAX
			var all_ok := true
			for k: String in _ok:
				if not _ok[k]:
					all_ok = false
				print("  %s: %s" % [k, "ok" if _ok[k] else "FAIL"])
			print("SPACE TEST: %s" % ("PASS" if all_ok else "FAIL"))
			get_tree().quit(0 if all_ok else 1)
