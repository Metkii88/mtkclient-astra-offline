#!/usr/bin/env bash
# ============================================================
#  Сборка и установка Python 3.8.10 из исходников (офлайн)
#  для Astra Linux 1.7 «Орёл» / «Белый Горизонт» (x86-64)
#  Требуется: sudo, gcc/make + dev-пакеты (build-essential, libffi-dev,
#  libssl-dev, zlib1g-dev ... — из штатного репозитория Astra или debs/).
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
PYBIN=$PREFIX/bin/python3.8

# ---------------------------------------------------------------
# 0a. Если /opt/python38 уже есть — проверяем его целостность.
#     Ранее бывали «недозагруженные» установки (например, сборка упала
#     на _ctypes из-за отсутствия libffi-dev, но часть файлов установилась).
#     Такой Python удаляем и пересобираем с нуля.
# ---------------------------------------------------------------
if [ -x "$PYBIN" ]; then
    if ! "$PYBIN" -c "import ctypes, ssl, zlib, bz2, sqlite3, readline" >/dev/null 2>&1; then
        echo "[!] Найден неполноценный $PREFIX (не хватает модулей ctypes/ssl/...)."
        echo "    Удаляю и пересобираю с нуля..."
        rm -rf "$PREFIX" /tmp/Python-$PYVER
    else
        echo "[*] Python 3.8 уже установлен и полностью работоспособен:"
        "$PYBIN" -V
        if ! "$PYBIN" -m pip --version >/dev/null 2>&1; then
            echo "[*] pip отсутствует — доустанавливаю офлайн..."
            bootstrap_pip || echo "[!] pip не поставлен — install.sh работает без него."
        fi
        echo "[*] Пропускаю сборку. Дальше:  sudo ./install.sh"
        exit 0
    fi
fi

DEBS_LOCAL=""
[ -d debs ] && DEBS_LOCAL=$(ls debs/*.deb 2>/dev/null || true)

need_pkgs() {
    command -v gcc  >/dev/null || return 0
    command -v make >/dev/null || return 0
    for h in ffi.h openssl/ssl.h zlib.h bzlib.h readline/readline.h sqlite3.h ncurses.h; do
        [ -f "/usr/include/$h" ] || [ -f "/usr/include/x86_64-linux-gnu/$h" ] || return 0
    done
    return 1
}

# ---------------------------------------------------------------
# Функция офлайн-установки pip для python3.8 (используется и после
# сборки, и для «доустановки» в уже готовую инсталляцию).
# Сетевые вызовы исключены (--no-index).
# ---------------------------------------------------------------
bootstrap_pip() {
    local PIPW SETW TMP SP
    # способ 1: ensurepip (работает, если python собран с bundled wheel'ами)
    "$PYBIN" -m ensurepip --upgrade >/dev/null 2>&1 || true
    "$PYBIN" -m pip --version >/dev/null 2>&1 && return 0

    # способ 2: распаковка wheel'а pip напрямую в site-packages (без pip вообще)
    PIPW=$(ls wheels38/pip-*.whl 2>/dev/null | head -1)
    if [ -n "$PIPW" ]; then
        echo "[*] Установка pip из $(basename "$PIPW") напрямую (распаковкой) ..."
        SP="$("$PYBIN" -c 'import sysconfig;print(sysconfig.get_paths()["purelib"])')"
        mkdir -p "$SP"
        TMP=$(mktemp -d)
        "$PYBIN" -m zipfile -e "$PIPW" "$TMP"
        # в wheel'е каталоги pip/ и pip-<ver>.data/ — копируем что есть
        [ -d "$TMP/pip" ] && cp -a "$TMP/pip" "$SP"/
        for d in "$TMP"/pip-*; do
            case "$d" in *.dist-info|*.data) : ;; *) [ -d "$d" ] && cp -a "$d" "$SP"/ ;; esac
        done
        if [ -d "$TMP/pip-"*".data/scripts" ]; then
            cp -a "$TMP"/pip-*.data/scripts/* "$PREFIX/bin/" 2>/dev/null || true
            chmod +x "$PREFIX"/bin/pip* 2>/dev/null || true
        fi
        rm -rf "$TMP"
        "$PYBIN" -m pip --version >/dev/null 2>&1 && return 0
    fi

    # способ 3: get-pip.py строго офлайн из wheels38/
    if [ -f wheels38/get-pip.py ]; then
        echo "[*] Установка pip через get-pip.py (--no-index) ..."
        "$PYBIN" wheels38/get-pip.py --no-index --find-links=wheels38 \
            --no-warn-script-location >/dev/null 2>&1 || true
        "$PYBIN" -m pip --version >/dev/null 2>&1 && return 0
    fi
    return 1
}

# 1. Пакеты для компиляции. БЕЗ libffi-dev модуль _ctypes не соберётся
#    (fatal error: ffi.h), без libssl-dev — ssl/hashlib.
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

# 2a. Гарантируем наличие bundled wheel'ов pip/setuptools в дереве исходников
#     (на случай повреждённого/урезанного tarball).
mkdir -p /tmp/Python-$PYVER/Lib/ensurepip/_bundled
cp -f wheels38/pip-*.whl wheels38/setuptools-*.whl \
    /tmp/Python-$PYVER/Lib/ensurepip/_bundled/ 2>/dev/null || true

echo "[*] Конфигурация и сборка (займёт 5–15 минут) ..."
cd /tmp/Python-$PYVER
# Предупреждения вида "'tp_print' is deprecated", "-Wunused-but-set-variable"
# — ШТАТНЫЕ для CPython 3.8, на результат НЕ влияют.
./configure --prefix=$PREFIX --enable-shared \
    LDFLAGS="-Wl,-rpath,$PREFIX/lib" >/dev/null
make -j"$(nproc)" >/dev/null
make altinstall >/dev/null     # altinstall: не создаёт /usr/local/bin/python3

# 3. КРИТИЧНАЯ проверка модулей
if ! "$PYBIN" -c "import ctypes, ssl, zlib, bz2, sqlite3, readline" 2>/dev/null; then
    echo "[!] ОШИБКА: Python собрался без критичных модулей (ctypes/ssl/...)."
    echo "    Чаще всего не хватает libffi-dev / libssl-dev / zlib1g-dev."
    echo "    Поставьте их (или положите .deb в debs/) и запустите скрипт снова:"
    echo "      sudo rm -rf /opt/python38 && sudo ./build-python38.sh"
    exit 1
fi
"$PYBIN" -V
echo "[*] Python 3.8 собран успешно"

# 4. pip — офлайн (см. bootstrap_pip выше)
if ! "$PYBIN" -m pip --version >/dev/null 2>&1; then
    bootstrap_pip || echo "[!] Не удалось установить pip. install.sh работает и без него (ставит wheels распаковкой)."
fi
if "$PYBIN" -m pip --version >/dev/null 2>&1; then
    echo "[*] pip установлен: $("$PYBIN" -m pip --version)"
fi

# 5. Регистрация общей библиотеки (для GUI / сторонних модулей)
if [ -f "$PREFIX/lib/libpython3.8.so.1.0" ]; then
    echo "$PREFIX/lib" > /etc/ld.so.conf.d/python38.conf
    ldconfig
fi

echo "[*] Теперь запустите:  sudo ./install.sh   (он сам найдёт python3.8)"
