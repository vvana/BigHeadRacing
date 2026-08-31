extends Node3D
## Автотест выбора числа участников заезда (31.08: «выбор кол-ва участников
## гонки от 4-8»). Оффлайн-половина: GameState.race_size = 7 — сцена обязана
## построить ровно 7 машин (игрок + 6 ботов), все на полотне и без
## наложений; счётчики (_progress и прочие) — той же длины.
## Заодно кламп: 99 обязан ужаться до 8, 1 — до 4.

var _main: Node3D
var _frame := 0


func _ready() -> void:
	GameState.set_race_size(7)
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame != 30:
		return
	var n: int = _main._cars.size()
	var counters_ok: bool = _main._progress.size() == n \
			and _main._slot_taken.size() == n \
			and _main._net_place.size() == n \
			and _main._laps_done.size() == n
	# Машины не наложились друг на друга на решётке.
	var min_gap := 1e9
	for i in n:
		for j in n:
			if j > i:
				min_gap = minf(min_gap, (_main._cars[i] as Car)
						.global_position.distance_to(
						(_main._cars[j] as Car).global_position))
	GameState.race_size = 99
	var clamp_hi := GameState.race_size == GameState.RACE_SIZE_MAX
	GameState.race_size = 1
	var clamp_lo := GameState.race_size == GameState.RACE_SIZE_MIN
	GameState.set_race_size(4)   # вернуть профилю значение по умолчанию

	var ok: bool = n == 7 and counters_ok and min_gap > 1.5 \
			and clamp_hi and clamp_lo
	print("RACE SIZE TEST: %s (машин %d, счётчики=%s, мин. зазор %.1f м, "
			% ["PASS" if ok else "FAIL", n, str(counters_ok), min_gap]
			+ "кламп 99->8=%s, 1->4=%s)" % [str(clamp_hi), str(clamp_lo)])
	get_tree().quit(0 if ok else 1)
