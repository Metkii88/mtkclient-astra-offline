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

DEBS_LOCAL=""
[ -d debs ] && DEBS_LOCAL=$(ls debs/*.deb 2>/dev/null || true)

need_pkgs() {
    # возвращает 0, если какого-то пакета/заголовка нет
    command -v gcc  >/dev/null || return 0
    command -v make >/dev/null || return 0
    for h in ffi.h openssl/ssl.h zlib.h bzlib.h readline/readline.h sqlite3.h ncurses.h; do
        [ -f "/usr/include/$h" ] || [ -f "/usr/include/x86_64-linux-gnu/$h" ] || return 0
    done
    return 1
}

# 1. Пакеты для компиляции (обязательно: gcc, make, libffi-dev, libssl-dev,
#    zlib1g-dev, libbz2-dev, libreadline-dev, libsqlite3-dev, libncursesw5-dev).
#    БЕЗ libffi-dev модуль _ctypes НЕ соберётся (fatal error: ffi.h) и
#    mtkclient затем падает при импорте — проверка ниже это ловит.
if need_pkgs; then
    if [ -n "$DEBS_LOCAL" ]; then
        echo "[*] Установка пакетов сборки из локальных debs/ ..."
        dpkg -i $DEBS_LOCAL 2>/dev/null || true
        apt-get -f install -y 2>/dev/null || true
    fi
    echo "[*] Установка пакетов для сборки через apt ..."
    apt-get install -y --no-install-recommends \
        build-essential libssl-dev zlib1g-dev libffi-dev \
        libbz2-dev libreadline-dev libsqlite3-dev \
        libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev || {
            echo "[!] Не удалось поставить пакеты для сборки (нужен локальный репозиторий Astra)."
            echo "    Скачайте их заранее в debs/ на машине с интернетом:"
            echo "    build-essential libssl-dev zlib1g-dev libffi-dev libbz2-dev"
            echo "    libreadline-dev libsqlite3-dev libncursesw5-dev"
            exit 1
        }
fi

# 2. Распаковка и сборка
echo "[*] Распаковка Python-$PYVER ..."
rm -rf /tmp/Python-$PYVER
tar xf "python/Python-$PYVER.tgz" -C /tmp

# 2a. ДОБАВЛЯЕМ wheel pip/setuptools в исходники ДО сборки.
#     В стандартном tarball они лежат в Lib/ensurepip/_bundled/, но если архив
#     был собран без них (или использован --without-pip), то после установки
#     python3.8 -m ensurepip падает с "can't open file 'ensurepip'".
#     Кладём нужные wheel-файлы из wheels38/ прямо в дерево исходников.
mkdir -p /tmp/Python-$PYVER/Lib/ensurepip/_bundled
cp -f wheels38/pip-*.whl wheels38/setuptools-*.whl /tmp/Python-$PYVER/Lib/ensurepip/_bundled/ 2>/dev/null || true

echo "[*] Конфигурация и сборка (займёт 5–15 минут) ..."
cd /tmp/Python-$PYVER
# ВАЖНО: НЕ используем --without-pip; configure сам обнаружит ffi.h/openssl/zlib...
# Предупреждения вида "'tp_print' is deprecated", "-Wunused-but-set-variable",
# "siginterrupt is deprecated" — ШТАТНЫЕ для CPython 3.8, на результат НЕ влияют.
./configure --prefix=$PREFIX --enable-shared \
    LDFLAGS="-Wl,-rpath,$PREFIX/lib" >/dev/null
make -j"$(nproc)" >/dev/null
make altinstall >/dev/null     # altinstall: не создаёт /usr/local/bin/python3

# 3. КРИТИЧНАЯ проверка: ctypes нужен mtkclient (AES/RSA), ssl — для сети/DA
if ! $PREFIX/bin/python3.8 -c "import ctypes, ssl, zlib, bz2, sqlite3, readline" 2>/dev/null; then
    echo "[!] ОШИБКА: Python собрался без критичных модулей (ctypes/ssl/...)."
    echo "    Чаще всего не хватает libffi-dev / libssl-dev / zlib1g-dev."
    echo "    Поставьте их (или положите .deb в debs/) и запустите скрипт снова:"
    echo "      sudo rm -rf /opt/python38 && sudo ./build-python38.sh"
    exit 1
fi
$PREFIX/bin/python3.8 -V
echo "[*] Python 3.8 собран успешно"

# 4. pip для python3.8 — офлайн, тремя способами (по убыванию надёжности)
if ! $PREFIX/bin/python3.8 -m pip --version >/dev/null 2>&1; then
    echo "[*] Установка pip через ensurepip ..."
    $PREFIX/bin/python3.8 -m ensurepip --upgrade 2>/dev/null || true
fi
if ! $PREFIX/bin/python3.8 -m pip --version >/dev/null 2>&1; then
    # если wheel pip лежит в wheels38/ — ставим его напрямую (без сети)
    echo "[*] Установка pip из wheels38/pip-*.whl напрямую ..."
    PIPW=$(ls wheels38/pip-*.whl 2>/dev/null | head -1)
    [ -n "$PIPW" ] && $PREFIX/bin/python3.8 -m zipfile -e "$PIPW" /tmp/pip-extract \
        && PYTHONPATH=/tmp/pip-extract $PREFIX/bin/python3.8 -m pip install --no-index \
            --find-links=wheels38 pip setuptools 2>/dev/null && rm -rf /tmp/pip-extract || true
fi
if ! $PREFIX/bin/python3.8 -m pip --version >/dev/null 2>&1; then
    # последний вариант — get-pip.py (нужна версия под py3.8: bootstrap.pypa.io/pip/3.8/get-pip.py)
    echo "[*] Установка pip через get-pip.py ..."
    $PREFIX/bin/python3.8 wheels38/get-pip.py --no-index --find-links=wheels38 2>/dev/null || true
fi
if $PREFIX/bin/python3.8 -m pip --version >/dev/null 2>&1; then
    echo "[*] pip установлен: $($PREFIX/bin/python3.8 -m pip --version)"
else
    echo "[!] Не удалось установить pip. install.sh работает и без него (ставит wheels напрямую)."
fi

echo "[*] Теперь запустите:  sudo ./install.sh   (он сам найдёт python3.8)"
