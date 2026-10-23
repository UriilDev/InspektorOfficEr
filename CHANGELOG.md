# Changelog

## 1.2.0 — подготовка к публичному релизу
- Нейтральные формулировки: функции, переменные, ключи `config.json`, сообщения журнала и заголовки таблицы описывают категории (`remoteAccessDetect`, `diskProtectionDetect`, `hardwareCollector`), а не конкретные продукты.
- Технические сигнатуры распознавания установленного ПО вынесены в единый блок `$script:Sig` (`src/Collectors.ps1`).
- Параметр `-NoHopCli` заменён на `-NoRemoteCli`; ключи `features.anyDesk*`/`hopToDesk*`/`freezeDetect`/`freeze.*` заменены на `features.remoteAccessDetect`, `features.remoteAccessCli`, `features.diskProtectionDetect`, `diskProtectionDetect.*`.
- Добавлена проверка Windows Unified Write Filter через CIM.
- Заголовки таблицы по умолчанию: «Удалённый доступ 1 (ID)», «Удалённый доступ 2 (ID)», «Защита диска»; лист и файл — «Инвентаризация». Для существующих таблиц задайте прежние заголовки в `excel.headers`.
- Добавлены LICENSE (MIT), `.gitignore`, пример паспорта `Passports/pc_info.example.json`, README.

## 1.1.1
- Исправлена ошибка, из-за которой Excel предлагал «восстановление» файла при втором запуске (конфликт имён переменных в `Write-InventoryRow`).
- Самопроверка перед заменой книги (`Test-InventoryDoc`): при ошибке книга не заменяется, строка сохраняется в `_pending_rows.csv`.

## 1.1.0
- Быстрая проверка: пороги в секции `checks` (`uptimeDaysWarn`, `ramGbWarn`, `diskFreePctWarn`, `diskFreePctBad`, `diskFreeGbBad`, `osSupportWarnDays`, `changeFreeGb`, `osSupport`).
- Поддержка ОС определяется по сборке и редакции Windows; состояние антивируса — из SecurityCenter2; брандмауэр — с запасным чтением из реестра.
- Отчёт: блок «что исправить в первую очередь», «что изменилось с прошлого отчёта» (снимок в `Raports\_state`), быстрая таблица программ, поиск, печатная версия.
- Excel: столбцы ищутся по тексту заголовка; записываются только изменённые ячейки; защищённый лист и объединённые ячейки останавливают запись с понятным сообщением; обновление делается на копии с проверкой.

## 1.0.2
- Исходники разделены на `src/*.ps1`; единый переносимый `Inspektor.ps1` собирается `build.ps1`.
- Журнал с уровнями (`log.level`), режим `-Diagnose`.
- Сбой отдельного сборщика или класса WMI не прерывает запуск.
