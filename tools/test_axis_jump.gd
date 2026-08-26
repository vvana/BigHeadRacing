extends Node3D
## Автотест на «респавн выкинул через пол-трассы».
##
## Кольцо подходит само к себе: на классике участки, разнесённые по ходу
## гонки на 150 м, сближаются до 53 м (замер tools/LoopGap.tscn). Значит
## машине, уехавшей от полотна на 27+ м, ближайшей точкой оси становится
## ЧУЖОЙ участок — и старый глобальный поиск (Curve3D.get_closest_offset)
## отправлял туда и респавн, и прогресс, и прицел ИИ.
##
## Стенд отводит машину строго вбок от оси, шагами по кадру физики (как
## если бы она туда доехала), и проверяет две вещи:
##   1) отметка на оси (Car.track_offset) осталась на СВОЁМ участке;
##   2) авто-возврат поставил машину рядом с тем местом, где она съехала,
##      а не на другом конце трассы.

const START_RATIO := 0.233   # отметка ~169 м: тут виток ближе всего к чужому
const SIDE_STEP := 0.6       # на столько отводим машину за кадр, м
const SIDE_TOTAL := 34.0     # насколько далеко уводим от оси, м
# Сколько метров вдоль трассы позволено «проехать» за время отвода вбок.
# Честное движение — только поперёк, так что запас чисто на кривизну оси.
const OFFSET_TOLERANCE := 25.0
# Возврат ставит машину на +6 м вперёд от отметки; с запасом на кадры,
# пока машина падает на полотно.
const RESPAWN_TOLERANCE := 40.0

var _main: Node3D
var _frame := 0
var _start_off := 0.0
var _side := 0.0
var _drift_off := 0.0        # отметка в самой дальней точке отвода
var _fail := ""


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	_frame += 1
	var track: TrackBuilder = _main._track
	var curve: Curve3D = track._curve
	var length := curve.get_baked_length()
	var car: Car = _main._car

	if _frame == 30:
		_start_off = length * START_RATIO
		car.global_position = curve.sample_baked(_start_off) + Vector3.UP * 0.6
		car.linear_velocity = Vector3.ZERO
		car.reset_track_offset()
		print("старт: отметка %.1f м из %.1f" % [car.track_offset, length])
		return
	if _frame < 30:
		return

	# Фаза 1: отводим машину вбок от оси, кадр за кадром.
	if _side < SIDE_TOTAL:
		_side += SIDE_STEP
		var pos := curve.sample_baked(_start_off)
		var ahead := curve.sample_baked(fposmod(_start_off + 1.0, length))
		var right := (ahead - pos).normalized().cross(Vector3.UP)
		car.global_position = pos + right * _side + Vector3.UP * 0.6
		car.linear_velocity = Vector3.ZERO
		car.sync_track_offset()
		if _side >= SIDE_TOTAL:
			_drift_off = car.track_offset
			var naive := curve.get_closest_offset(car.global_position)
			print("отвели на %.0f м вбок: своя отметка %.1f, глобальный поиск даёт %.1f"
					% [_side, _drift_off, naive])
			var drift := _ring_dist(_drift_off, _start_off, length)
			if drift > OFFSET_TOLERANCE:
				_fail = "отметка уехала на %.0f м (лимит %.0f)" % [
						drift, OFFSET_TOLERANCE]
		return

	# Фаза 2: ждём авто-возврата (он же ловит вылет за ограждение).
	if _frame < 30 + int(SIDE_TOTAL / SIDE_STEP) + 300:
		return
	car.sync_track_offset()
	var back := _ring_dist(car.track_offset, _start_off, length)
	print("после возврата: отметка %.1f (съехали на %.1f), сдвиг %.0f м"
			% [car.track_offset, _start_off, back])
	if back > RESPAWN_TOLERANCE:
		_fail = "возврат унёс на %.0f м вперёд (лимит %.0f)" % [
				back, RESPAWN_TOLERANCE]
	print("AXISJUMP TEST: %s" % ("PASS" if _fail == "" else "FAIL — " + _fail))
	get_tree().quit(0 if _fail == "" else 1)


## Расстояние между отметками по кольцу (учитывает переход через ноль).
func _ring_dist(a: float, b: float, length: float) -> float:
	var d := absf(fposmod(a - b, length))
	return minf(d, length - d)
