extends SceneTree
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var img := Image.load_from_file(a[0])
	var r := Rect2i(int(a[1]), int(a[2]), int(a[3]), int(a[4]))
	var cut := img.get_region(r)
	cut.resize(r.size.x * 3, r.size.y * 3, Image.INTERPOLATE_NEAREST)
	cut.save_png(a[5])
	print("CROP ok")
	quit()
