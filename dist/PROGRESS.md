
## dist пересобран под аркадный пак (2026-09-02, продолжение)
Задание: «делай новую сборку dist».
- `--import` (кэш чист) → `--export-debug "Windows Desktop"
  dist/BigHeadRacing.exe` — на этот раз экспорт прошёл С ПЕРВОГО раза
  (привычного падения с кодом 255 не было).
- pck 57.9 → 59.7 МБ (+ аркадный пак arcadecars, новые иконки/детали UI,
  новый TuningPanel), exe 84.1 МБ без изменений (шаблон тот же).
- Из СОБРАННОГО dist: TestLap — PASS (круг 726 м), TestSelectPrefill —
  PASS, test_car_build — 261/261 ok. Прежние «Parameter "m" is null» и
  утечки RID на выходе — известный headless-шум (TrackBuilder.gd:772),
  новых ошибок нет.
- Теперь exe у игроков совпадает с VDS (PROTOCOL 18, обновлён ранее
  сегодня): аркадные машины видны нормально, а не бокс-заглушкой.
**Файлы:** dist/BigHeadRacing.exe, dist/BigHeadRacing.pck. Код игры не
менялся. Не закоммичено (как и всё на ветке Andrei).

## dist пересобран под правки тюнинга (2026-09-03, 16:22)
Задание: «dist делай». `--import` (код 0) → `--export-debug "Windows
Desktop"` — код 0 с первой попытки. exe 84.1 МБ (без изменений), pck
78.57 МБ (+1.6 КБ). Из СОБРАННОГО exe: TestTuningPreview 24/24,
test_shop 54/54, test_car_build 309/309, TestSelectPrefill — PASS.
**VDS НЕ обновлён** (изменения чисто клиентские, протокол прежний —
серверу ничего не нужно). Не закоммичено.
**Файлы:** dist/BigHeadRacing.exe, dist/BigHeadRacing.pck, PROGRESS.md.
