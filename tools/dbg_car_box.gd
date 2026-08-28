extends Node
## Отладка: куда садятся ФАРЫ на каждой из машин пака. Считает ровно тем
## же кодом, что игра (Car.headlight_anchor), плюс печатает габариты
## кузова — видно, не висит ли лампа выше крыши или сбоку в воздухе.
## Старое (до 28.08) фиксированное место для сравнения: x 0.55, y 0.42.
## Запуск: godot --headless --path . res://tools/DbgCarBox.tscn

const OLD_X := 0.55
const OLD_Y := 0.42


func _ready() -> void:
	var bad_old := 0
	var bad_new := 0
	for id in CarModelLibrary.CAR_IDS:
		var model := CarModelLibrary.build(id)
		if model == null:
			continue
		var pts := Car.model_points(model, model.transform)
		var body := AABB(pts[0], Vector3.ZERO)
		for p in pts:
			body = body.expand(p)
		var a := Car.headlight_anchor(model, model.transform)
		if a.is_empty():
			print("%-14s ФАРУ ПОСТАВИТЬ НЕ УДАЛОСЬ" % id)
			bad_new += 1
			continue
		# «Мимо кузова» — лампа выше крыши или шире борта.
		var edge: float = a["x"] + a["w"] * 0.5
		var old_miss: bool = OLD_Y > body.end.y or OLD_X > body.end.x
		var new_miss: bool = a["y"] > body.end.y or edge > body.end.x
		if old_miss:
			bad_old += 1
		if new_miss:
			bad_new += 1
		print("%-14s кузов x%.2f y[%.2f..%.2f] | фара x%.2f y%.2f z%.2f ш%.2f%s%s" % [
			id, body.end.x, body.position.y, body.end.y,
			a["x"], a["y"], a["z"], a["w"],
			"  СТАРАЯ МИМО" if old_miss else "",
			"  НОВАЯ МИМО" if new_miss else ""])
		model.queue_free()
	print("мимо кузова: старое место %d машин, новое %d" % [bad_old, bad_new])
	get_tree().quit(0)
