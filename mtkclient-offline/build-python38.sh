#!/usr/bin/env bash
# ============================================================
#  Сборка и установка Python 3.8.10 из исходников (офлайн)
#  для Astra Linux 1.7 «Орёл» / «Белый Горизонт» (x86-64)
#  Требуется: sudo, gcc/make (пакеты build-essential + libssl-dev
#  берутся из штатного репозитория Astra или из папки debs/).
#  Python ставится в /opt/python38 — системный python3 НЕ трогается.
# ============================================================
set -e
cd "$(dirname "$0")"

if [ "$EUID" -ne 0 ]; then
    echo "Запустите от root:  sudo ./build-python38.sh"
    exit 1
fi

PYVER=3.8.10
PREFIX=/opt/python38

if [ -x "$PREFIX/bin/python3.8" ]; then
    echo "[*] Python 3.8 уже установлен в $PREFIX — пропускаю сборку."
    exit 0
fi

# 1. Пакеты для компиляции (если apt-репозиторий недоступен,
#    заранее скачайте их .deb в debs/: gcc, make, libssl-dev, zlib1g-dev,
#    libffi-dev, libbz2-dev, libreadline-dev, libsqlite3-dev, tk-dev ...)
if ! command -v gcc >/dev/null || ! command -v make >/dev/null; then
    if ls debs/*.deb >/dev/null 2>&1; then
        dpkg -i debs/*.deb || apt-get -f install -y || true
    fi
    apt-get install -y --no-install-recommends \
        build-essential libssl-dev zlib1g-dev libffi-dev \
        libbz2-dev libreadline-dev libsqlite3-dev wget curl \
        libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev || {
            echo "[!] Не удалось поставить пакеты для сборки (нужен локальный репозиторий Astra)."
            echo "    Скачайте их заранее в debs/ на машине с интернетом."
            exit 1
        }
fi

# 2. Распаковка и сборка
echo "[*] Распаковка Python-$PYVER ..."
rm -rf /tmp/Python-$PYVER
tar xf "python/Python-$PYVER.tgz" -C /tmp

echo "[*] Конфигурация и сборка (займёт 5–15 минут) ..."
cd /tmp/Python-$PYVER
./configure --prefix=$PREFIX --enable-shared \
    LDFLAGS="-Wl,-rpath,$PREFIX/lib" >/dev/null
make -j"$(nproc)" >/dev/null
make altinstall >/dev/null     # altinstall: не создаёт /usr/local/bin/python3

# 3. Проверка
$PREFIX/bin/python3.8 -V
ldd $PREFIX/bin/python3.8 | grep -q "libpython3.8.so.* => $PREFIX/lib" && \
    echo "[*] Готово: $PREFIX/bin/python3.8 (+ общий libpython3.8.so для GUI)"

# 4. pip для python3.8 — офлайн из get-pip.py
$PREFIX/bin/python3.8 wheels38/get-pip.py --no-index --find-links=wheels38 2>/dev/null || \
    $PREFIX/bin/python3.8 ensurepip --upgrade

echo "[*] Теперь запустите:  sudo ./install.sh   (он сам найдёт python3.8)"
