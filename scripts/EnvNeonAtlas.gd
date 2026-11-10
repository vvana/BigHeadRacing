extends RefCounted
## СГЕНЕРИРОВАНО tools/gen_env.py — руками не править.
## Куски атласов 2D-окружения трассы «neon»:
## имя -> [x, y, ширина, высота в px атласа, размер в метрах].
## У картонок размер — высота на экране, у плоских кусков — ширина.

const GROUND := "res://assets/env/neon/ground.png"
const ROAD := "res://assets/env/neon/road.png"

const PATCHES := {
	"car_meet": [599, 4, 286, 282, 32.0],
	"drift_spot": [4, 297, 287, 280, 30.0],
	"gas_station": [295, 297, 286, 280, 30.0],
	"garage_yard": [879, 297, 287, 278, 30.0],
	"port_yard": [4, 4, 289, 289, 34.0],
	"plaza": [889, 4, 288, 282, 34.0],
	"intersection": [297, 4, 298, 288, 34.0],
	"roof_deck": [585, 297, 290, 279, 32.0],
	"skate_plaza": [4, 581, 288, 278, 30.0],
}

const DECALS := {
	"puddle_cyan": [191, 156, 182, 103, 4.0],
	"puddle_pink": [377, 156, 184, 103, 4.0],
	"puddle_orange": [445, 4, 183, 109, 4.0],
	"oil_slick": [819, 4, 184, 108, 3.5],
	"pool_orange": [1007, 4, 183, 108, 6.0],
	"pool_blue": [4, 156, 183, 108, 6.0],
	"pool_violet": [632, 4, 183, 109, 6.0],
	"manhole": [185, 4, 108, 140, 1.6],
	"grate": [771, 156, 146, 80, 1.6],
	"crosswalk": [565, 156, 202, 86, 5.0],
	"start_line": [4, 4, 177, 148, 6.0],
	"nitro_mark": [297, 4, 144, 114, 3.0],
}

const BUILDINGS := {
	"tower_cyan": [4, 4, 154, 223, 24.0],
	"tower_slim": [162, 4, 147, 220, 26.0],
	"office_curved": [469, 4, 206, 215, 13.0],
	"tower_round": [313, 4, 152, 217, 22.0],
	"tuning_shop": [600, 231, 212, 188, 9.0],
	"car_wash": [422, 429, 206, 166, 8.0],
	"diner": [4, 429, 209, 173, 7.5],
	"nightclub": [217, 429, 201, 171, 10.0],
	"car_park": [679, 4, 216, 210, 12.0],
	"screen_store": [4, 231, 206, 194, 10.0],
	"showroom": [816, 231, 205, 188, 9.0],
	"corner_store": [214, 231, 215, 189, 8.0],
	"hotel": [433, 231, 163, 189, 16.0],
	"billboard_big": [992, 4, 123, 202, 9.0],
	"skybridge": [1025, 231, 189, 178, 12.0],
	"mast": [899, 4, 89, 203, 20.0],
}

const STREET := {
	"lamp": [4, 224, 91, 173, 6.0],
	"lamp_double": [627, 4, 98, 186, 6.0],
	"traffic_red": [1185, 4, 35, 177, 4.5],
	"traffic_yellow": [1224, 4, 32, 177, 4.5],
	"bus_stop": [304, 4, 184, 195, 3.5],
	"vending": [729, 4, 146, 182, 2.4],
	"billboard_front": [168, 4, 132, 196, 6.5],
	"billboard_back": [492, 4, 131, 193, 6.5],
	"neon_arrow": [879, 4, 108, 181, 4.5],
	"power_pole": [4, 4, 160, 216, 8.0],
	"barrier": [293, 224, 124, 143, 2.0],
	"cones": [421, 224, 189, 135, 1.5],
	"bench_bin": [99, 224, 190, 146, 1.8],
	"taxi": [614, 224, 183, 131, 2.6],
	"bus": [991, 4, 190, 178, 4.2],
}

const BUILDINGS_TALL := {
	"tower_stepped": [871, 4, 128, 224, 26.0],
	"tower_twisted": [124, 4, 92, 234, 26.0],
	"tower_checker": [543, 4, 114, 229, 24.0],
	"tower_helipad": [1003, 4, 120, 221, 24.0],
	"office_l": [617, 248, 204, 187, 13.0],
	"twin_towers": [1127, 4, 149, 221, 26.0],
	"tower_cylinder": [761, 4, 106, 226, 22.0],
	"tower_crane": [4, 4, 116, 240, 22.0],
	"bank": [184, 248, 227, 209, 11.0],
	"glass_cube": [4, 248, 176, 212, 14.0],
	"tower_screen": [661, 4, 96, 228, 24.0],
	"tower_glassroof": [433, 4, 106, 232, 22.0],
	"center_curved": [415, 248, 198, 200, 13.0],
	"residential_tall": [294, 4, 135, 233, 22.0],
	"tv_tower": [220, 4, 70, 234, 28.0],
}

const BUILDINGS_MID := {
	"brick_fire": [4, 4, 169, 236, 14.0],
	"corner_glass": [991, 244, 176, 227, 14.0],
	"townhouses": [539, 244, 229, 229, 11.0],
	"balconies": [364, 244, 171, 230, 14.0],
	"lofts": [177, 4, 174, 236, 13.0],
	"gym": [653, 4, 179, 235, 13.0],
	"office_violet": [991, 4, 145, 234, 14.0],
	"roof_frame": [355, 4, 147, 236, 15.0],
	"roof_billboard": [506, 4, 143, 236, 15.0],
	"pharmacy": [836, 4, 151, 235, 14.0],
	"parking_deck": [772, 244, 215, 228, 9.0],
	"motel": [4, 480, 231, 169, 8.0],
	"pizza": [4, 244, 198, 232, 13.0],
	"mural": [206, 244, 154, 232, 15.0],
}

const BUILDINGS_LOW := {
	"garage_low": [851, 4, 218, 198, 7.0],
	"burger": [445, 212, 222, 192, 7.0],
	"club_low": [231, 212, 210, 196, 8.0],
	"warehouse_low": [897, 212, 215, 180, 7.0],
	"gas_shop": [421, 4, 206, 199, 7.0],
	"workshop_low": [4, 4, 215, 204, 7.0],
	"shops_row": [4, 212, 223, 197, 7.5],
	"carwash_low": [223, 4, 194, 203, 7.0],
	"parking_booth": [4, 413, 188, 166, 5.0],
	"bar_low": [631, 4, 216, 199, 7.0],
	"substation": [671, 212, 222, 183, 6.0],
}

## Лист -> [атлас, куски, плоский (лежит на земле), без освещения,
## сложением цвета (чёрное = прозрачно)].
const SHEETS := {
	"patches": ["res://assets/env/neon/patches.png", PATCHES, true, false, false],
	"decals": ["res://assets/env/neon/decals.png", DECALS, true, false, false],
	"buildings": ["res://assets/env/neon/buildings.png", BUILDINGS, false, true, false],
	"street": ["res://assets/env/neon/street.png", STREET, false, true, false],
	"buildings_tall": ["res://assets/env/neon/buildings_tall.png", BUILDINGS_TALL, false, true, false],
	"buildings_mid": ["res://assets/env/neon/buildings_mid.png", BUILDINGS_MID, false, true, false],
	"buildings_low": ["res://assets/env/neon/buildings_low.png", BUILDINGS_LOW, false, true, false],
}
