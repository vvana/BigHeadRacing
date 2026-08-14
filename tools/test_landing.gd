extends Node3D
## Автотест «приземление не замедляет»: машину подбрасывают на 3 м с
## горизонтальной скоростью 20 м/с. Меряем скорость после осадки удара
## (кадры 5..13 после касания). Замер ОБРЫВАЕМ, как только сработает
## ведение у стены (_wall_align_time > 0): трасса в плане кольцевая,
## после посадки машина по хорде сближается с внешним бортом, и штраф
## стены (легитимное «стена слегка тормозит») загрязнял бы замер
## приземления. Критерий: скорость ≥ 17 м/с (раньше удар и трение
## съедали заметную часть насовсем).

var _main: Node3D
var _frame := 0
var _landed_frame := -1
var _min_speed := 999.0


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	_frame += 1
	var car: Car = _main._car
	if _frame == 160:
		# Гонка идёт; подбрасываем и разгоняем строго горизонтально.
		car.global_position.y += 3.0
		var fwd := -car.global_transform.basis.z
		fwd.y = 0.0
		car.linear_velocity = fwd.normalized() * 20.0
		car.angular_velocity = Vector3.ZERO
	elif _frame > 165:
		if _landed_frame < 0:
			if car._grounded_wheels >= 2:
				_landed_frame = _frame
		elif _frame <= _landed_frame + 13 and car._wall_align_time <= 0.0:
			if _frame > _landed_frame + 4:
				var hv := car.linear_velocity
				hv.y = 0.0
				_min_speed = minf(_min_speed, hv.length())
		else:
			var ok := _min_speed >= 17.0
			print("LANDING TEST: %s (мин. скорость после касания %.1f м/с, лимит 17)" % [
				"PASS" if ok else "FAIL", _min_speed])
			get_tree().quit(0 if ok else 1)
	if _frame > 500:
		print("LANDING TEST: FAIL (не приземлилась за 500 кадров)")
		get_tree().quit(1)
