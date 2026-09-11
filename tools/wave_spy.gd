extends Node
## Подставной «менеджер гонки» для TestWaveLife: ловит рассылку вспышек
## попадания волны (ScrambleWave._hit_fx → race.net_broadcast_wave_hit).

var hits := 0
var last_at := Vector3.ZERO


func net_broadcast_wave_hit(at: Vector3) -> void:
	hits += 1
	last_at = at


## Волна зовёт у стрелявшего ещё и это (Car.use_weapon), а мины и снаряды —
## своё; пустышки, чтобы подмена race ничего не ломала.
func net_broadcast_weapon(_car: Node, _kind: int) -> void:
	pass


func report_weapon_hit(_a: Node, _b: Node, _kind: int) -> void:
	pass
