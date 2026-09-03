extends Node3D
## Автотест уничтожения (ракета/лазер/авиаудар): destroy() убирает машину
## с трассы, через respawn_delay она появляется ТАМ ЖЕ, где её уничтожили
## (без выноса вперёд), и делается «призраком» — мигает, НЕ сталкивается с
## другими машинами, но может ехать; после ghost_time коллизии и видимость
## полностью возвращаются.

var _main: Node3D
var _frame := 0
var _blinked := false          # видимость хоть раз гасла (моргание)
var _speed_after := -1.0
var _off_before := 0.0         # отметка трассы в момент взрыва
var _gap := 999.0              # сдвиг вперёд при появлении, м
var _hidden_ok := false        # на середине паузы машины не видно
var _shown_ok := false         # сразу после паузы машина уже на трассе


func _ready() -> void:
	_main = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	add_child(_main)


func _physics_process(_delta: float) -> void:
	_frame += 1
	var car: Car = _main._car
	if _frame > 240 and not car.visible:
		_blinked = true
	match _frame:
		200:
			car.linear_velocity = -car.global_transform.basis.z * 20.0
			car.sync_track_offset()
			_off_before = car.track_offset
			car.destroy()
			_speed_after = car.linear_velocity.length()
			# Пауза перед появлением: машины нет вовсе — не видно и ни для
			# кого не мишень (is_ghost на паузе тоже true).
			var gone_ok: bool = (car.is_respawning() and car.is_ghost()
					and not car.visible)
			print("destroy: v=%.2f пауза=%s призрак=%s видна=%s" % [
				_speed_after, car.is_respawning(), car.is_ghost(),
				car.visible])
			if not gone_ok or _speed_after > 0.01:
				print("EXPLOSION TEST: FAIL (машина не исчезла или скорость не обнулилась)")
				get_tree().quit(1)
		215:  # 0.25 c — середина паузы (respawn_delay 0.5)
			_hidden_ok = car.is_respawning() and not car.visible
		235:  # 0.58 c — пауза кончилась, машина появилась
			car.sync_track_offset()
			var length: float = _main._track._curve.get_baked_length()
			_gap = (fposmod(car.track_offset - _off_before + length * 0.5,
					length) - length * 0.5)
			# Призрак живёт на слое 8 (03.09: боксы и плиты его видят, машины
			# — нет), слой 4 снят с обеих сторон.
			_shown_ok = (not car.is_respawning() and car.is_ghost()
					and car.collision_layer == 0b1000
					and (car.collision_mask & 0b100) == 0
					and _main._track.distance_from_axis(car.global_position)
							< TrackBuilder.TRACK_HALF_WIDTH)
			print("появилась: сдвиг=%.2f м слои=%d/%d" % [
				_gap, car.collision_layer, car.collision_mask])
		420:  # 3.7 c спустя (пауза 0.5 + ghost_time 2.0) — всё как раньше
			var back_ok: bool = (not car.is_ghost() and car.visible
					and car.collision_layer == 0b100
					and car.collision_mask == 0b111)
			var on_track: bool = _main._track.distance_from_axis(
					car.global_position) < TrackBuilder.TRACK_HALF_WIDTH
			# Появление ровно на месте взрыва: раньше машину выносило на
			# +6 м вперёд («появляются немного впереди»).
			var same_spot: bool = absf(_gap) < 1.5
			var ok: bool = (back_ok and on_track and _blinked and car.alive
					and _hidden_ok and _shown_ok and same_spot)
			print("EXPLOSION TEST: %s (вернулась=%s на_трассе=%s мигала=%s пауза=%s появление=%s на_месте=%s сдвиг=%.2f)" % [
				"PASS" if ok else "FAIL", back_ok, on_track, _blinked,
				_hidden_ok, _shown_ok, same_spot, _gap])
			get_tree().quit(0 if ok else 1)
