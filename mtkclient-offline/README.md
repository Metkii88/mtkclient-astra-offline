# mtkclient — автономный пакет для Astra Linux 1.7 «Орёл» (x86-64)

Всё необходимое для установки **без интернета** лежит в этой папке:

```
mtkclient-offline/
├── install.sh          # скрипт установки (sudo ./install.sh)
├── build-python38.sh   # офлайн-сборка Python 3.8.10 в /opt/python38 (нужен для GUI)
├── src/                # исходники mtkclient (github.com/bkerler/mtkclient)
├── wheels/             # python-зависимости для штатного python3.9+ Орла (CLI+GUI)
├── wheels38/           # python-зависимости + PySide6 для Python 3.8 (+get-pip.py)
├── python/             # исходники Python-3.8.10.tgz (для build-python38.sh)
└── debs/               # сюда можно положить .deb-файлы (см. ниже), если apt-репозиторий недоступен
```

## Быстрая установка (на Орле, штатный python3.11)

```bash
tar xf mtkclient-offline.tar.gz
cd mtkclient-offline
sudo ./install.sh
```

Скрипт:
1. ставит из локального репозитория Astra системные библиотеки `libusb-1.0-0` и `libfuse2`
   (для GUI дополнительно `libgl1`, `libxkbcommon0`, `libglib2.0-0`, `dbus`, `fontconfig`);
2. ставит python-пакеты из `wheels/` или `wheels38/` (`--no-index`, PyPI не трогает):
   pyusb, pycryptodomex, colorama, pyserial, capstone, unicorn, mfusepy, keystone-engine,
   shiboken6 + PySide6-Essentials 6.6.3 (GUI), сам mtkclient;
3. кладёт udev-правила в `/etc/udev/rules.d/` и перезагружает udev;
4. создаёт команды `/usr/local/bin/mtk` и `/usr/local/bin/mtk_gui`;
5. проверяет импорты.

## Если на системе только Python 3.7 — как включить GUI

PySide6 требует Python ≥ 3.8, поэтому в пакет добавлен **Python 3.8.10**
(официальные исходники, ~24 МБ) и скрипт его офлайн-сборки. Установка:

```bash
sudo ./build-python38.sh    # соберёт Python 3.8.10 в /opt/python38 (5–15 минут)
sudo ./install.sh           # сам найдёт /opt/python38 и возьмёт wheels38/ — с GUI
```

* Системный `python3` (3.7) **не заменяется** — используется `make altinstall`,
  Python 3.8 живёт изолированно в `/opt/python38`.
* Для сборки нужны компилятор и dev-пакеты (`build-essential libssl-dev zlib1g-dev
  libffi-dev libbz2-dev libreadline-dev libsqlite3-dev tk-dev` и др.) — они берутся
  из штатного репозитория Astra; при полном отсутствии сети скачайте их `.deb`
  заранее в `debs/` тем же способом, что описан ниже.
* После этого `mtk` и `mtk_gui` автоматически работают на Python 3.8.
* Альтернатива без Qt: на Python 3.7 работает **только CLI** (`mtk`) — набор
  `wheels/` для него не подходит (там abi3-колёса от 3.9), но запуск напрямую
  из исходников возможен: `cd src && python3 mtk.py ...` со старыми версиями
  зависимостей.

## Важные замечания про Орёл (python3.11)

* Все колёса совместимы с python3.9…3.15 (теги `abi3`/`py3-none`).
* **PySide6 6.6.3 собран под glibc 2.28.** В Орле glibc новее — работать должно.
  Если GUI не стартует, используйте **только CLI** (`mtk.py`) — он Qt не требует.
* Для **Белого Горизонта 1.6 (python3.9)** этот же набор подходит без изменений.

## Если apt-репозиторий на машине недоступен

На машине с интернетом и тем же архивом Astra скачайте deb-пакеты со всеми
зависимостями в `debs/`:

```bash
apt-get download $(apt-rdepends libusb-1.0-0 libfuse2 | grep -v '^ ')
# или корректно, в чистом контейнере с образом Astra 1.7:
apt-get install --download-only -o Dir::Cache::archives=./debs libusb-1.0-0 libfuse2
```

Затем на целевой машине:

```bash
sudo dpkg -i debs/*.deb
sudo apt-get -f install -y   # только если нужны доп. зависимости из диска-репозитория
```

Пакеты `libusb-1.0-0`, `libfuse2` есть в штатном репозитории Astra SE 1.7 — обычно
докачивать ничего не приходится.

## Использование

```bash
mtk                     # список команд
mtk r boot boot_a.img   # прочитать раздел boot
mtk w preloader foo.img # записать preloader (осторожно!)
mtk da                  # режим direct access (нужен libfuse2)
mtk_gui                 # графический интерфейс
```

Подключите телефон в BootROM-режим (выключенный → зажать Volume Down при
подключении USB, либо выключен + обе кнопки). Проверка: `lsusb | grep -i mediatek`
(идемпотентно виден как `0e8d:MTK...`).

## Пересборка этого пакета (на другой машине)

```bash
git clone https://github.com/bkerler/mtkclient src
pip3 download -d wheels --only-binary=:all: --platform manylinux_2_28_x86_64 \
    --python-version 3.11 pyusb pycryptodomex colorama pyserial capstone \
    unicorn mfusepy keystone-engine
pip3 download -d wheels --no-deps PySide6-Essentials==6.6.3 shiboken6==6.6.3
pip3 wheel --no-deps -w wheels ./src
tar czf mtkclient-offline.tar.gz mtkclient-offline
```
