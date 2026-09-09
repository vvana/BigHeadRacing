extends SceneTree
## Служебный дамп таблицы оружия для документации (09.09): вид, группа,
## бесплатная ступень, уровни и цены ступеней, описания I/II/III.
func _initialize() -> void:
	for kind in Weapons.COUNT:
		var g: String = Weapons.group_of(kind)
		var lv: Array = Weapons.STEP_LEVELS[g]
		var pr: Array = Weapons.STEP_PRICES[g]
		var line := "%s|%s|free=%d|" % [Weapons.NAMES[kind],
				Weapons.GROUP_NAMES[g], Weapons.free_step(kind)]
		for s in range(1, Weapons.STEPS + 1):
			line += "%s: %s (ур.%d, %d монет) // " % [Weapons.ROMAN[s],
					Weapons.step_desc(kind, s), int(lv[s - 1]), int(pr[s - 1])]
		print(line)
	quit()
