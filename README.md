# mtkclient — автономный пакет для Astra Linux 1.7 «Орёл»

Готовый **офлайн-дистрибутив** [mtkclient](https://github.com/bkerler/mtkclient) v2.1.4 —
инструмента для работы с MediaTek-чипсетами (чтение/запись флешей, разблокировка,
exploit-режимы BROM/DA). Пакет собран так, чтобы на целевой машине **не требовался
интернет**: все Python-зависимости лежат внутри в виде wheel-пакетов.

> **Оригинальный проект:** [bkerler/mtkclient](https://github.com/bkerler/mtkclient)
> (MIT-лицензия). Этот репозиторий — не форк кода, а упаковка готового к офлайн-установке
> комплекта под Astra Linux 1.7 «Орёл» (x86-64). Весь код mtkclient принадлежит авторам
> оригинального проекта.

## Вариант 1: AppImage (рекомендуется — без установки вообще)

Самый простой способ: скачайте **`mtkclient-x86_64.AppImage`** (~155 МБ) из
[Releases](../../releases) — один переносимый файл, внутри Python 3.8.10, mtkclient
и PySide6 (GUI). Ничего устанавливать не нужно, системный Python не требуется:

```bash
chmod +x mtkclient-x86_64.AppImage
./mtkclient-x86_64.AppImage                 # запуск GUI
./mtkclient-x86_64.AppImage devices         # CLI-режим
./mtkclient-x86_64.AppImage r /dev/sda BOOTA boot.img   # пример чтения
```

Если на системе нет FUSE (на Astra с параноидальным уровнем безопасности бывает),
запустите так же, как при сборке, или через распаковку:

```bash
APPIMAGE_EXTRACT_AND_RUN=1 ./mtkclient-x86_64.AppImage
# либо: ./mtkclient-x86_64.AppImage --appimage-extract && ./squashfs-root/AppRun
```

Контрольная сумма:

```bash
sha256sum mtkclient-x86_64.AppImage
# c8c99f5cfc17abe5b14494be8e9d22332ad2456c44e98c5c0d4c95766bd11a6b
```

Образ полностью автономен: libfuse2, libxcb-*, Qt-плагины и все библиотеки встроены
внутрь (mfusepy находит libfuse через `FUSE_LIBRARY_PATH` из AppRun), поэтому GUI и CLI
работают даже на системах без FUSE и без дополнительных пакетов.

Сборка образа воспроизводится скриптом [`appimage-build/build-appimage.sh`](appimage-build/build-appimage.sh)
(Docker + linuxdeploy + plugin-Qt, окружение Ubuntu 20.04 ради старого glibc).

## Вариант 2: Установка в систему (tar.gz)

Скачайте `mtkclient-offline.tar.gz` из [Releases](../../releases) (~314 МБ):

```
mtkclient-offline/
├── install.sh          # скрипт установки (sudo ./install.sh)
├── build-python38.sh   # офлайн-сборка Python 3.8.10 в /opt/python38 (нужен для GUI)
├── src/                # исходники mtkclient v2.1.4 (github.com/bkerler/mtkclient)
├── wheels/             # python-зависимости для штатного python3.9+ Орла (CLI + GUI)
├── wheels38/           # зависимости + PySide6-Essentials 6.6.3 для Python 3.8
├── python/             # официальные исходники Python-3.8.10.tgz
└── debs/               # сюда можно положить .deb-пакеты, если apt-репозиторий недоступен
```

Контрольная сумма архива:

```bash
sha256sum mtkclient-offline.tar.gz
# 619ac5e0979b54b46db986b403487d4970acba76be0a6144591cff55f1b7e41e
```

## Быстрая установка (Astra 1.7, штатный Python 3.11)

```bash
tar xf mtkclient-offline.tar.gz
cd mtkclient-offline
sudo ./install.sh
```

Скрипт `install.sh`:

1. ставит из локального репозитория Astra системные библиотеки `libusb-1.0-0`, `libfuse2`
   (для GUI дополнительно `libgl1`, `libxkbcommon0`, `libglib2.0-0`, `dbus`, `fontconfig`);
2. ставит Python-пакеты из `wheels/` или `wheels38/` строго офлайн (`--no-index`, PyPI не трогает):
   pyusb, pycryptodomex, colorama, pyserial, capstone, unicorn, mfusepy, keystone-engine,
   shiboken6 + PySide6-Essentials 6.6.3 (GUI), сам mtkclient;
3. кладёт udev-правила в `/etc/udev/rules.d/` и перезагружает udev;
4. создаёт команды `/usr/local/bin/mtk` и `/usr/local/bin/mtk_gui`;
5. проверяет импорты.

## Если на системе только Python 3.7 — как включить GUI

PySide6 требует Python ≥ 3.8, поэтому в пакет добавлены исходники **Python 3.8.10**
и скрипт его офлайн-сборки:

```bash
sudo ./build-python38.sh    # соберёт Python 3.8.10 в /opt/python38 (5–15 минут)
sudo ./install.sh           # сам найдёт /opt/python38 и возьмёт wheels38/ — с GUI
mtk_gui                     # графический интерфейс работает
```

* Системный `python3` (3.7) **не заменяется** — сборка идёт через `make altinstall`,
  Python 3.8 живёт изолированно в `/opt/python38`.
* Для сборки нужны компилятор и dev-пакеты (`build-essential`, `libssl-dev`, `zlib1g-dev`,
  `libffi-dev`, `libbz2-dev`, `libreadline-dev`, `libsqlite3-dev` и др.) — они берутся
  из штатного репозитория Astra; при полностью закрытом контуре заранее положите их `.deb`
  в папку `debs/`.
* Без Qt-вариант: на чистом Python 3.7 работает **только CLI** (`mtk`).

### Частые проблемы при сборке Python 3.8

| Симптом в логе | Причина | Решение |
|---|---|---|
| `fatal error: ffi.h: Нет такого файла или каталога` (падает `_ctypes`) | не установлен `libffi-dev` | `sudo apt install libffi-dev` (или `.deb` в `debs/`), затем пересобрать: `sudo rm -rf /opt/python38 && sudo ./build-python38.sh` |
| `can\'t open file \'ensurepip\': [Errno 2] No such file or directory` | в `/opt/python38` осталась «недозагруженная» установка Python от прошлой неудачной сборки (например, после падения на `_ctypes` из-за `libffi-dev`) — интерпретатор есть, а модулей pip/ensurepip в нём нет | **обновлено:** запустите `sudo ./build-python38.sh` повторно — скрипт теперь проверяет целостность существующей установки (`import ctypes, ssl, ...`), при проблемах удаляет `/opt/python38` и пересобирает с нуля, а pip доустанавливает офлайн тремя способами (ensurepip → распаковка `wheels38/pip-*.whl` напрямую в site-packages → `get-pip.py --no-index`). Можно и без пересборки: `install.sh` ставит все wheels распаковкой, pip ему не обязателен |
| warnings `'tp_print' is deprecated`, `-Wunused-but-set-variable`, `siginterrupt is deprecated` | штатные предупреждения компилятора на код CPython 3.8 | игнорировать — на результат не влияют |
| `WARNING: The script pip3.8 is installed in '/opt/python38/bin' which is not on PATH` | норма для `altinstall` | использовать полные пути (`/opt/python38/bin/python3.8`) — скрипты так и делают |

## Использование

```bash
mtk                     # справка по командам
mtk r bootl             # чтение загрузчика (пример)
mtk da                  # режим DA
mtk_gui                 # графический интерфейс
```

Подробное описание команд — в оригинальном проекте:
[README-USAGE](https://github.com/bkerler/mtkclient/blob/master/README-USAGE.md).

## Важные замечания

* Все колёса в `wheels/` совместимы с Python 3.9…3.15 (теги `abi3` / `py3-none-any`).
* **PySide6 6.6.3 собран под glibc 2.28** — в «Орле» glibc новее, работать должно.
  Если GUI не стартует, используйте только CLI (`mtk`) — Qt он не требует.
* Работа с устройствами предполагает подключение по USB и перевод устройства
  в BROM/DA-режим; соблюдайте меры предосторожности — прошивки могут повредить устройство.

## Лицензии

| Компонент | Лицензия |
|---|---|
| mtkclient (оригинал) | MIT — © bkerler и соавторы ([репозиторий](https://github.com/bkerler/mtkclient)) |
| Python 3.8.10 (исходники) | PSF License |
| PySide6 / shiboken6 | LGPL-3.0 (Qt Company) |
| pycryptodome(ex) | BSD-2 / Public Domain |
| pyusb, pyserial, capstone, unicorn, keystone, mfusepy, colorama | BSD / Apache-2.0 / MIT (см. wheel-пакеты) |

Данный репозиторий распространяет готовые бинарные артефакты (wheels) и исходники
сторонних проектов в соответствии с их лицензиями. При использовании сохраняйте
уведомления об авторских правах соответствующих проектов.
