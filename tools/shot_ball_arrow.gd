extends Node3D
## Снимок стрелки к мячу (07.09): футбол, мяч уносится в дальний угол
## арены — за кадр (в створ чужих ворот: заодно засчитывается гол, это
## неважно), у края экрана должна появиться стрелка с кружком.
## Запуск С ОКНОМ:
## godot --path . res://tools/ShotBallArrow.tscn -- <папка_вывода>

var _frame := 0
var _out := "user://shots"
var _soccer: Node3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_soccer = (load("res://scenes/Soccer.tscn") as PackedScene).instantiate()
	add_child(_soccer)


func _physics_process(_d: float) -> void:
	_frame += 1
	if _frame >= 300 and _frame <= 340:
		# Мяч — в дальний угол поля (за кадр), машина стоит.
		var ball: RigidBody3D = _soccer._ball
		var arena = _soccer._arena
		var spot: Vector3 = arena.ball_spawn() + Vector3(-62.0, 0.0, 0.0)
		ball.global_position = spot
		ball.linear_velocity = Vector3.ZERO
	if _frame == 340:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out + "/ball_arrow.png")
		print("SHOT ball_arrow.png")
		get_tree().quit(0)
