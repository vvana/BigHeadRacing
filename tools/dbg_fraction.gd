extends Node
var _f := 0
var _vals: Array[float] = []
func _process(_d: float) -> void:
	_f += 1
	_vals.append(Engine.get_physics_interpolation_fraction())
	if _f == 90:
		var distinct := {}
		for v in _vals:
			distinct[snappedf(v, 0.01)] = true
		print("кадров: %d, разных значений дроби: %d, примеры: %s" % [
				_f, distinct.size(), str(_vals.slice(30, 42).map(
				func(x: float) -> float: return snappedf(x, 0.001)))])
		get_tree().quit(0)
