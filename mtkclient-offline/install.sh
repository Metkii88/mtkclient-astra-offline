#!/usr/bin/env bash
# ============================================================
#  mtkclient — автономная (offline) установка для Astra Linux 1.7 "Орёл"
#  x86-64, python3.11 (Орёл) / python3.9 (Белый Горизонт 1.6)
#  Требуется: sudo. Интернет НЕ нужен.
# ============================================================
set -e
cd "$(dirname "$0")"

if [ "$EUID" -ne 0 ]; then
    echo "Запустите от root:  sudo ./install.sh"
    exit 1
fi

# Выбор интерпретатора:
#  - python3.8 из /opt (собранный build-python38.sh) — нужен для GUI (PySide6);
#  - штатный python3.11/3.12 Орла — тоже подходит;
#  - python3.7 («Белый Горизонт» и старые Astra) — только CLI, GUI на нём не работает.
if [ -x /opt/python38/bin/python3.8 ]; then
    PYBIN=/opt/python38/bin/python3.8
elif command -v python3.8 >/dev/null; then
    PYBIN=$(command -v python3.8)
else
    PYBIN=$(command -v python3.11 || command -v python3.12 || command -v python3)
fi
PYSHORT=$("$PYBIN" -c 'import sys;print("%d.%d"%sys.version_info[:2])')
echo "Используется интерпретатор: $PYBIN (Python $PYSHORT)"

WHEELS=wheels                       # набор по умолчанию (python>=3.9)
SRCDIR=src                          # исходники mtkclient
if [ "$PYSHORT" = "3.8" ]; then
    WHEELS=wheels38                 # версии под Python 3.8 + PySide6 (GUI)
    SRCDIR=src38                    # пропатчен кодом «X | None» (PEP 604) для py3.8
    echo "[*] Выбраны wheels из $WHEELS/ и исходники $SRCDIR/ (Python 3.8, GUI поддерживается)"
elif [ "$PYSHORT" = "3.7" ]; then
    echo "[!] Внимание: Python 3.7 найден. GUI на нём не работает (нужен >=3.8)."
    echo "    Запустите сначала:  sudo ./build-python38.sh   — и повторите установку."
fi

# 1. Системные библиотеки из локального репозитория Astra (если настроен)
#    libusb-1.0-0 — обязательна; libfuse2 — только для режима дамп-через-FUSE (DA);
#    Qt-зависимости (libgl1, libxkbcommon0 и т.д.) — только для GUI (mtk_gui.py).
if [ "$(ls -A debs/*.deb 2>/dev/null)" ]; then
    echo "[*] Установка системных библиотек из локальных .deb (debs/)..."
    dpkg -i debs/*.deb || apt-get -f install -y || true
elif apt-get -s install libusb-1.0-0 >/dev/null 2>&1; then
    echo "[*] Установка системных библиотек через apt (локальный репозиторий Astra)..."
    apt-get install -y --no-install-recommends libusb-1.0-0 libfuse2 libglib2.0-0 \
        libegl1 libgl1 libxkbcommon0 libxcb1 libdbus-1-3 libfontconfig1 2>/dev/null || \
    apt-get install -y --no-install-recommends libusb-1.0-0 libfuse2
else
    echo "[!] Ни debs/, ни apt-репозиторий недоступны."
    echo "    Убедитесь вручную, что установлены: libusb-1.0-0, libfuse2,"
    echo "    а для GUI: libegl1, libgl1, libxkbcommon0, libglib2.0-0, libdbus-1-3, libfontconfig1."
fi

# 2. Python-пакеты из папки wheels (без обращения к PyPI).
#    --no-deps: у пакета mtkclient в метаданных числится полный PySide6,
#    но нам достаточно PySide6-Essentials из wheels — зависимости ставим явно.
echo "[*] Установка python-пакетов из $WHEELS/ ..."
"$PYBIN" -m pip install --no-index --find-links="$WHEELS" \
    --no-deps pyusb pycryptodome pycryptodomex colorama pyserial capstone \
    unicorn mfusepy keystone-engine shiboken6 PySide6-Essentials mtkclient 2>/dev/null || {
    # если pip недоступен — распаковываем wheels вручную в site-packages
    echo "[!] pip недоступен, устанавливаю wheels распаковкой..."
    SP=$("$PYBIN" -c "import sysconfig; print(sysconfig.get_paths()['purelib'])")
    mkdir -p "$SP"
    for w in "$WHEELS"/*.whl; do
        [ -e "$w" ] || continue
        case "$(basename "$w")" in *cp38*) : ;; esac
        "$PYBIN" -c "
import zipfile,sys
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
" "$w" "$SP"
    done
}

# 3. udev-правила для входа в BootROM-режим MediaTek
echo "[*] Установка udev-правил..."
install -m 644 $SRCDIR/Setup/Linux/*.rules /etc/udev/rules.d/ 2>/dev/null || \
install -m 644 $SRCDIR/Setup/linux/*.rules /etc/udev/rules.d/ 2>/dev/null || \
echo "[!] udev-правила не найдены — для USB от обычного пользователя добавьте их вручную."
udevadm control --reload-rules && udevadm trigger || true

# 4. Команды запуска mtk / mtk_gui (указывают на выбранный интерпретатор).
#    PYTHONPATH=каталог исходников: на Python 3.8 используется пропатченный
#    набор src38 (аннотации вида «X | None» из PEP 604 работают только с py3.10+,
#    future-annotations включает их и на 3.8).
echo "[*] Создание команд /usr/local/bin/mtk и /usr/local/bin/mtk_gui ..."
SRCABS=$(cd "$SRCDIR" && pwd)
cat > /usr/local/bin/mtk <<EOF
#!/bin/sh
PYTHONPATH=$SRCABS exec $PYBIN $SRCABS/mtk.py "\$@"
EOF
cat > /usr/local/bin/mtk_gui <<EOF
#!/bin/sh
PYTHONPATH=$SRCABS exec $PYBIN $SRCABS/mtk_gui.py "\$@"
EOF
chmod +x /usr/local/bin/mtk /usr/local/bin/mtk_gui

# 5. Проверка
echo "[*] Проверка установки..."
PYTHONPATH="$SRCABS" "$PYBIN" -c "import usb, Cryptodome, serial, capstone, unicorn, keystone, mtkclient; print('OK: ядро mtkclient импортируется')"
PYTHONPATH="$SRCABS" "$PYBIN" -c "import ctypes; print('OK: ctypes (криптография) работает')" || \
    echo "[!] ВНИМАНИЕ: модуль ctypes отсутствует — пересоберите Python: sudo rm -rf /opt/python38 && sudo ./build-python38.sh (нужен libffi-dev)."
PYTHONPATH="$SRCABS" "$PYBIN" -c "import PySide6.QtWidgets; print('OK: PySide6 (GUI) импортируется')" || \
    echo "[!] GUI не запустится: не хватает Qt-библиотек (libgl1, libxkbcommon0 и др.) — CLI работает."

cat <<'EOF'
============================================================
Готово! Запуск:
   mtk <команда>                 # CLI (например: mtk w data userdata / mtk r boot boot.img)
   mtk_gui                       # GUI (нужны X11/Wayland + Qt-библиотеки)
или из исходников:
   cd src && python3 mtk.py ...
Для работы с USB от обычного пользователя перелогиньтесь
(udev-правила уже установлены).
============================================================
EOF
