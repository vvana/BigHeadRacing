class_name IsoCamera
extends Camera3D
## Изометрическая камера в духе Rock'n'Roll Racing:
## ортографическая проекция, фиксированный угол, плавно следует за целью.
## Камера НЕ вращается с машиной — как в оригинале, мир статичен.

@export var target: Node3D
@export var ortho_size := 26.0        # «зум» — ширина видимой области
@export var follow_speed := 6.0       # плавность слежения
@export var pitch_deg := -32.0        # наклон вниз (классика изометрии ~30°)
@export var yaw_deg := 45.0           # поворот вокруг вертикали
@export var distance := 60.0          # отступ камеры от цели

var _look_offset: Vector3


func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = ortho_size
	rotation_degrees = Vector3(pitch_deg, yaw_deg, 0)
	_look_offset = -global_transform.basis.z * -distance
	if target:
		global_position = target.global_position + _look_offset


## Слежение — в КАДРЕ РЕНДЕРА, а не в физике. Физика идёт ровно 60 раз в
## секунду, рендер — со своим темпом, и когда камера двигалась только по
## шагам физики, картинка ступенчато замирала: то за кадр рендера проходило
## два шага, то ни одного. Своя машина при этом выглядит ровно (она стоит
## в центре и дрожит ВМЕСТЕ с камерой), а вот трасса и соперники дёргаются —
## это и есть жалоба «все едут дёргано, кроме меня». За цель берём ВИДИМОЕ
## положение машины (Car.visual_origin — интерполяция между шагами физики),
## иначе плавная камера просто показывала бы ступеньки самой машины.
func _process(delta: float) -> void:
	if not target:
		return
	var pos: Vector3 = target.visual_origin() \
			if target.has_method("visual_origin") else target.global_position
	var desired := pos + _look_offset
	# NaN в позиции цели отравил бы камеру навсегда (lerp с NaN — NaN):
	# кадр пропускаем, машину вернёт страховка в Main._check_recovery.
	if not desired.is_finite():
		return
	# Сглаживание кадронезависимое: в физике шаг был всегда 1/60, а кадр
	# рендера гуляет (60, 144, просадка до 30) — на «follow_speed * delta»
	# камера тянулась бы с разной скоростью на разных мониторах.
	global_position = global_position.lerp(desired,
			1.0 - exp(-follow_speed * delta))
