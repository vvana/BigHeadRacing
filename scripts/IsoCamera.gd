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


func _physics_process(delta: float) -> void:
	if not target:
		return
	var desired := target.global_position + _look_offset
	# NaN в позиции цели отравил бы камеру навсегда (lerp с NaN — NaN):
	# кадр пропускаем, машину вернёт страховка в Main._check_recovery.
	if not desired.is_finite():
		return
	global_position = global_position.lerp(desired, follow_speed * delta)
