extends Node3D
## Автотест гашения самовольной закрутки: машине в полёте (без руля)
## дают рысканье 1.5 рад/с — раньше оно не гасилось вовсе, и машина
## разворачивалась на взлёте/падении сама. Теперь без руля рысканье
## должно затухать: через ~0.65 с |ω.y| < 0.3 рад/с.

var _main: Node3D
var _frame := 0


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _main == null:
		return
	var car: Car = _main._car
	match _frame:
		160:
			# Гонка уже идёт (отсчёт кончился). Подбрасываем машину и крутим.
			car.global_position.y += 8.0
			car.linear_velocity = -car.global_transform.basis.z * 10.0
			car.angular_velocity = Vector3(0.0, 1.5, 0.0)
		200:
			var w := absf(car.angular_velocity.y)
			var ok := w < 0.3
			print("AIRSPIN TEST: %s (|рысканье| через 0.65 с полёта: %.3f рад/с, лимит 0.3)" % [
				"PASS" if ok else "FAIL", w])
			get_tree().quit(0 if ok else 1)


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)
