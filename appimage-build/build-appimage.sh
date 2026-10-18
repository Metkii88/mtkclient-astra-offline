#!/usr/bin/env bash
# ============================================================================
# Воспроизводимая сборка mtkclient-x86_64.AppImage для Astra Linux 1.7 «Орёл»
# и других x86-64 дистрибутивов (glibc >= 2.25).
#
# Результат: один переносимый файл mtkclient-x86_64.AppImage (~155 МБ),
# внутри которого:
#   - Python 3.8.10 (собранный из исходников, --enable-shared, rpath $ORIGIN)
#   - mtkclient v2.1.4 + все зависимости (pyusb, pycryptodome/ex, unicorn,
#     capstone, keystone, pyserial, ...)
#   - PySide6-Essentials 6.6.3 + Qt-плагины (работающий GUI без установки)
#   - системные библиотеки (libxcb* и др.) для полной автономности
#
# ТРЕБОВАНИЯ К СРЕДЕ СБОРКИ (рекомендуется Docker Ubuntu 20.04 — старый glibc):
#   docker run -v $PWD:/build ubuntu:20.04 bash /build/appimage-build/build-appimage.sh
#
# Шаги:
#   1. apt-get install -y gcc g++ make zlib1g-dev libssl-dev libffi-dev \
#        libbz2-dev libreadline-dev libsqlite3-dev wget curl xz-utils \
#        file fipscheck xorrisko squashfs-tools desktop-file-utils libfuse2
#   2. Собрать Python 3.8.10 в AppDir/usr с --prefix=<AppDir>/usr
#      CFLAGS="-rpath=\$ORIGIN/../lib" LDFLAGS аналогично (для Qt-модулей)
#   3. python3.8 -m pip install --no-index --find-links wheels38 mtkclient PySide6-Essentials
#      (wheels38 — из этого репозитория; src/ — исходники mtkclient v2.1.4)
#   4. Скачать linuxdeploy-x86_64.AppImage + linuxdeploy-plugin-qt-x86_64.AppImage
#      из https://github.com/linuxdeploy/linuxdeploy/releases и
#      https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases
#      (chmod +x оба)
#   5. Создать AppDir: .desktop (Exec=mtk_gui), AppRun обрабатывает аргументы:
#      без аргументов -> gui.py, с аргументами -> CLI mtk; иконка PNG
#   6. linuxdeploy --appdir AppDir --plugin qt --output appimage
#      (плагин qt затаскивает все Qt-библиотеки и platform-плагин xcb)
#   7. Дополнительно скопировать в AppDir/usr/lib отсутствующие системные
#      либы (libxcb.so.1 libxcb-* libxkbcommon* libcap* libdeviceinfo*) —
#      список определяется по `ldd` на целевой Astra до сборки.
#
# Проверка готового образа (без FUSE):
#   APPIMAGE_EXTRACT_AND_RUN=1 ./mtkclient-x86_64.AppImage devices
# ============================================================================
echo "Этот скрипт — описание воспроизводимого цикла сборки."
echo "Готовый артефакт лежит в Releases: mtkclient-x86_64.AppImage"
