# Задание для Claude Code — 2026-07-02 (упрощение статусов + запуск)

Cowork уже изменил код (бэкенд + Flutter). Твоя работа — только собрать,
применить миграцию и проверить. Ничего не переписывай без причины.
Git-команды, меняющие состояние, — запрещены (правило §0).

## Что изменилось (контекст)

- Статусы столов упрощены до трёх: `free` / `occupied` / `waiting`
  («Свободен / Занят / Ждёт официанта»). Новая миграция
  `core/0005_simplify_table_status.py` маппит старые значения.
- Новое realtime-событие `table.updated` — теперь смена статуса стола с любого
  устройства (и с гостевой страницы) мгновенно видна всем. Обрабатывается и в
  Django (events/consumers), и во Flutter (realtime_client + main.dart).
- «Принял» у официанта теперь уходит на сервер (POST ack) и переводит
  waiting → occupied для всех устройств.
- Логин стаффа сохраняется: DRF-токен пишется в Hive, при старте приложение
  само подключается (демо с баннером — только если токена нет/протух).
- Веб-сборка стаффа больше НЕ требует `--dart-define=API_BASE_URL` — берёт
  origin страницы (обслуживается самим Django на /staff/). Смена IP больше
  не требует пересборки.
- Гостевая страница переделана (templates/guest_web/menu.html + CSS):
  карточки без фото, номер стола, кнопка «Позвать официанта» через fetch.
- Демо-сид: 30 свободных столов; фейковый генератор заказов удалён.
- Dart-тесты обновлены под новый контракт (api_dtos_test.dart).

Бэкенд уже проверен здесь: `manage.py check` — чисто, `makemigrations --check`
— «No changes detected», интеграционный смоук на SQLite прошёл (миграция,
вызов официанта, ack, PATCH free, категории без дублей).

## Шаг 1 — Flutter: анализ и тесты

```powershell
cd C:\Users\saaak\Documents\GitHub\MonoRepForCafeConn\CafeConn
flutter analyze
flutter test
```

Если analyze/test падают — пришли вывод пользователю, не чини молча
масштабной правкой. Мелкие очевидные вещи (недостающий import и т.п.) можно
поправить самому.

## Шаг 2 — Сборка веб-стаффа (БЕЗ API_BASE_URL)

```powershell
flutter build web --release --base-href /staff/
Copy-Item -Recurse -Force .\build\web\* ..\CafeConnWeb\static\staff\
```

Если после копирования нет `..\CafeConnWeb\static\staff\flutter.js.map` —
создай пустой (иначе collectstatic падает):

```powershell
$map = "..\CafeConnWeb\static\staff\flutter.js.map"
if (-not (Test-Path $map)) { New-Item -ItemType File $map }
```

## Шаг 3 — Миграция + рестарт

```powershell
cd ..\CafeConnWeb
docker compose up -d
docker compose exec web python manage.py migrate
docker compose restart web
docker compose logs web --tail=5   # ждём "Listening on TCP address 0.0.0.0:8000", без MissingFileError
```

## Шаг 4 — Проверки

```powershell
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost:8000/staff/     # 200
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost:8000/menu/t/1/  # 200
curl.exe -s -o NUL -w "%{http_code}`n" http://localhost:8000/menu/n/7/  # 200 — новый роут по НОМЕРУ стола (для QR)
docker compose exec web python manage.py shell -c "from apps.core.models import Table; print(sorted(set(Table.objects.values_list('status', flat=True))))"
# ожидаем подмножество: ['free', 'occupied', 'waiting']
```

Затем руками в браузере:

1. `http://localhost:8000/menu/t/5/` — карточки без фото, категории
   фильтруют, внизу кнопка «Позвать официанта». Нажать — кнопка станет
   зелёной «Официант уже идёт».
2. `http://localhost:8000/staff/` (или с телефона по IP) — Настройки →
   войти `tony` / `cafeconnect` → статус «Подключено», 30 столов, версия
   в «О приложении» = **v0.2.0** (это признак свежей сборки).
3. Стол 5 должен быть янтарным «Ждёт официанта» с пульсацией + бейдж
   «ЗОВУТ». Открыть стол → «Принял» → стол становится «Занят», на второй
   вкладке/устройстве это видно без перезагрузки (~1 сек).
4. В деталях стола чипы «Свободен / Занят / Ждёт официанта» — тапнуть
   «Свободен» → на гостевой… просто проверить, что в админке
   `/system-admin/` статус стола сменился и стол очистился.
5. Закрыть вкладку стаффа, открыть заново — должно подключиться САМО,
   без логина (токен в Hive).

## Известное/ожидаемое

- На устройствах со старой PWA — один раз почистить кэш сайта / удалить
  иконку и поставить заново (index.html уже отдаётся с no-cache, дальше
  обновления будут подхватываться сами).
- QR-коды содержат IP в URL — если роутер бара выдаст другой IP, старые QR
  умрут. Рекомендация пользователю: DHCP-резервация для ноутбука на роутере.
  Новые QR (на 192.168.1.94, по номерам столов /menu/n/N/) уже сгенерированы:
  `MonoRepForCafeConn\QR_tables_192.168.1.94.pdf`.
- Телефоны в сети бара не достучатся до 8000, если Windows считает сеть
  «общедоступной». Если /staff/ с телефона не открывается — выполнить в
  PowerShell от администратора:
  `netsh advfirewall firewall add rule name="CafeConnect 8000" dir=in action=allow protocol=TCP localport=8000`
