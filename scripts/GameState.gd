extends Node
## Глобальное состояние игры (autoload GameState):
## всё, что должно пережить смену сцены.

## Машина, выбранная на экране выбора (ID из CarModelLibrary.CAR_IDS).
var selected_car_id := "sharky"

## Кэш миниатюр машин для сетки выбора (ID → Texture2D).
## Генерируются один раз за запуск игры.
var car_thumbs := {}
