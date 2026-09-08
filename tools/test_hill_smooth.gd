extends Node3D
## Гладкость профиля высот трассы (жалоба 08.09 «едет как по стиральной
## доске»). Строит травяную трассу и меряет ПРОФИЛЬ ОСИ по длине:
##   * уклон каждые 0.5 м;
##   * сколько раз уклон меняет направление (локальные экстремумы) —
##     это и есть «доска»: у одной ровной горки перегибов единицы,
##     у лесенки из безье-ступенек — десятки;
##   * пиковая вторая производная (ускорение подвески на м/с²
##     при 25 м/с).
## PASS, если перегибов не больше PEAKS_MAX и |d2y| не больше JERK_MAX.

const STEP := 0.5          # шаг замера вдоль оси, м
const SPEED := 25.0        # с какой скоростью пересчитываем в м/с²
const PEAKS_MAX := 8       # у профиля из одной горки: подножие+гребень×2+спуск
## Порог по ПИКОВОМУ вертикальному ускорению. Сама горка (одна на круг)
## даёт 5.8 м/с² на 25 м/с; лесенка из безье-ступенек до правки 08.09
## давала 141 м/с² при 50 перегибах — вот её и ловим.
const ACC_MAX := 8.0       # вертикальное ускорение на 25 м/с, м/с²

var _done := false


func _ready() -> void:
	var track := TrackBuilder.new()
	track.kind = TrackBuilder.KIND_GRASS
	add_child(track)


func _process(_d: float) -> void:
	if _done:
		return
	_done = true
	var track: TrackBuilder = get_child(0)
	var curve: Curve3D = track._curve
	var length := curve.get_baked_length()
	var n := int(length / STEP)
	var ys: Array[float] = []
	for i in n:
		ys.append(curve.sample_baked(length * i / n).y)
	var slopes: Array[float] = []
	for i in n:
		slopes.append((ys[(i + 1) % n] - ys[i]) / STEP)
	# Перегибы: смена знака производной уклона (шум ±0.2% отсекаем).
	var peaks := 0
	var prev_sign := 0.0
	var acc_max := 0.0
	for i in n:
		var d2 := (slopes[i] - slopes[(i - 1 + n) % n]) / STEP
		acc_max = maxf(acc_max, absf(d2) * SPEED * SPEED)
		var s := 0.0
		if absf(slopes[i] - slopes[(i - 1 + n) % n]) > 0.002:
			s = signf(slopes[i] - slopes[(i - 1 + n) % n])
		if s != 0.0:
			if prev_sign != 0.0 and s != prev_sign:
				peaks += 1
			prev_sign = s
	var hmin := ys[0]
	var hmax := ys[0]
	for y in ys:
		hmin = minf(hmin, y)
		hmax = maxf(hmax, y)
	print("[hill] длина круга %.1f м, перепад %.2f м, шаг замера %.2f м"
			% [length, hmax - hmin, STEP])
	print("[hill] перегибов профиля: %d (норма <= %d)" % [peaks, PEAKS_MAX])
	print("[hill] пиковое вертикальное ускорение на %.0f м/с: %.2f м/с² (норма <= %.1f)"
			% [SPEED, acc_max, ACC_MAX])
	var ok := peaks <= PEAKS_MAX and acc_max <= ACC_MAX
	print("[hill] %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
