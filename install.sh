#!/usr/bin/env bash
# Установка Materialfy (клиент Spotify в стиле Material 3 Expressive) на Linux — сборка из исходников:
#
#   ./install.sh                                         # из уже скачанного репозитория
#   MATERIALFY_REPO=<git-url> bash install.sh             # скачать исходники в ~/.local/share/materialfy
#
# Что делает: ставит системные пакеты (компилятор C++, заголовки ALSA/PulseAudio/OpenGL/xkb — спросит
# разрешение и пароль sudo), ставит Rust (rustup, в ~/.cargo, без sudo) и Qt 6.12 (если в системе Qt
# старее — скачивает рядом с исходниками), собирает cargo build --release и кладёт команду
# ~/.local/bin/materialfy и значок в меню. Повторный запуск обновляет программу.
# Удаление: install.sh --uninstall (настройки и вход остаются).
#
# Переменные: MATERIALFY_REPO — git-адрес исходников, MATERIALFY_DIR — куда их класть (если скрипт запущен
# не из репозитория), MATERIALFY_QMAKE — свой qmake6, MATERIALFY_YES=1 — без вопросов,
# MATERIALFY_KEEP_BUILD=1 — не удалять каталог сборки target/ (быстрее обновления, но +3–5 ГБ).
set -euo pipefail
PATH_ORIG="$PATH"

APP="materialfy"
BIN="$HOME/.local/bin"
APPS="$HOME/.local/share/applications"
ICONS="$HOME/.local/share/icons/hicolor/scalable/apps"
ICONS_PNG="$HOME/.local/share/icons/hicolor/512x512/apps"
QT_VERSION="6.12.0"
RUST_MIN="1.98"

say()  { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mОшибка:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
# версия a >= b (через sort -V)
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

# Запуск из репозитория — собираем на месте; иначе — клон в MATERIALFY_DIR
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/crates/materialfy/Cargo.toml" ]; then
    DIR="$SELF_DIR"
    IN_PLACE=1
else
    DIR="${MATERIALFY_DIR:-$HOME/.local/share/materialfy}"
    IN_PLACE=0
fi

if [ "${1:-}" = "--uninstall" ]; then
    [ "$IN_PLACE" = "1" ] || rm -rf "$DIR"
    rm -f "$BIN/$APP" "$APPS/$APP.desktop" "$ICONS/$APP.svg" "$ICONS_PNG/$APP.png"
    say "Materialfy удалён. Настройки (~/.config/materialfy), данные (~/.local/share/materialfy),"
    echo "    кэш (~/.cache/materialfy), вход в связке ключей и Rust (~/.cargo) оставлены."
    exit 0
fi

[ "$(uname -s)" = "Linux" ] || fail "Этот скрипт — для Linux. Windows: build_windows.ps1 или инсталлер со страницы выпусков."
case "$(uname -m)" in
    x86_64) QT_HOST=linux; QT_ARCH=gcc_64 ;;
    aarch64) QT_HOST=linux_arm64; QT_ARCH=gcc_arm64 ;;
    *) fail "Архитектура $(uname -m) не поддерживается: для неё нет готовой сборки Qt." ;;
esac
[ "$(id -u)" != "0" ] || fail "Запускайте от обычного пользователя, без sudo: пароль спросится сам, когда понадобится."

confirm() {
    [ "${MATERIALFY_YES:-}" = "1" ] && return 0
    printf '    Продолжить? [Y/n] '
    local answer
    read -r answer </dev/tty || answer=n
    case "$answer" in "" | y | Y | д | Д) ;; *) fail "Отменено." ;; esac
}

# --- Системные пакеты -------------------------------------------------------

has_header() { [ -e "/usr/include/$1" ]; }
has_pc() { have pkg-config && pkg-config --exists "$1"; }

# Qt ищем заранее: скачивать его (а значит, и ставить 7zip для распаковки) нужно, только если в системе нет годного
qt_ok() { [ -x "$1" ] && ver_ge "$("$1" -query QT_VERSION 2>/dev/null || echo 0)" "${QT_VERSION%.*}"; }
# системный Qt годится, только если стоят и QML-модули (qt6-declarative и т. п.)
qt_full() {
    local qml
    qml="$("$1" -query QT_INSTALL_QML 2>/dev/null)" || return 1
    [ -e "$qml/QtQuick/qmldir" ] && [ -e "$qml/QtQuick/Effects/qmldir" ] && [ -e "$qml/Qt/labs/platform/qmldir" ]
}

QMAKE="${MATERIALFY_QMAKE:-}"
if [ -z "$QMAKE" ]; then
    for q in "$(command -v qmake6 || true)" /usr/lib/qt6/bin/qmake6 /usr/lib64/qt6/bin/qmake6 /usr/lib/qt6/bin/qmake; do
        if [ -n "$q" ] && qt_ok "$q" && qt_full "$q"; then QMAKE="$q"; break; fi
    done
fi

need=()
[ "$IN_PLACE" = "1" ] || have git || need+=(git)
have curl || need+=(curl)
have c++ || need+=(c++)
have pkg-config || need+=(pkg-config)
have python3 || need+=(python3)
[ -n "$QMAKE" ] || have 7z || have 7zz || need+=(7zip)
# звук: cpal (ALSA) и librespot (PulseAudio)
has_pc alsa || need+=(alsa-dev)
has_pc libpulse || need+=(pulse-dev)
has_header GL/gl.h || need+=(opengl-dev)
has_header xkbcommon/xkbcommon.h || need+=(xkbcommon-dev)
# cxx-qt не линкуется GNU ld.bfd: нужен lld, mold или gold
{ have ld.lld || have ld.mold || have ld.gold; } || need+=(lld)

if [ ${#need[@]} -gt 0 ]; then
    if have pacman; then
        cmd="sudo pacman -S --needed --noconfirm base-devel pkgconf git curl python 7zip alsa-lib libpulse mesa libxkbcommon lld"
    elif have apt-get; then
        sz=7zip
        apt-cache show 7zip >/dev/null 2>&1 || sz=p7zip-full
        cmd="sudo apt-get install -y build-essential pkg-config lld git curl python3 $sz \
libasound2-dev libpulse-dev libgl-dev libegl-dev libxkbcommon-dev libfontconfig1-dev libdbus-1-dev \
libegl1 libxkbcommon-x11-0 libxcb-cursor0 libxcb-icccm4 libxcb-keysyms1 libxcb-shape0 libfontconfig1 libdbus-1-3"
    elif have dnf; then
        cmd="sudo dnf install -y gcc-c++ make pkgconf lld git curl python3 7zip alsa-lib-devel pulseaudio-libs-devel \
mesa-libGL-devel mesa-libEGL-devel libxkbcommon-devel libxkbcommon-x11 fontconfig-devel xcb-util-cursor"
    elif have zypper; then
        cmd="sudo zypper install -y gcc-c++ make pkg-config lld git curl python3 7zip alsa-devel libpulse-devel \
Mesa-libGL-devel Mesa-libEGL-devel libxkbcommon-devel libxkbcommon-x11-0 fontconfig-devel libxcb-cursor0"
    else
        fail "Не хватает: ${need[*]}. Установите их пакетным менеджером своего дистрибутива и запустите скрипт снова."
    fi
    say "Не хватает системных пакетов: ${need[*]}"
    echo "    Будет выполнено: $cmd"
    confirm
    $cmd
fi

# --- Исходники --------------------------------------------------------------

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

if [ "$IN_PLACE" = "1" ]; then
    say "Собираю из $DIR"
elif [ -d "$DIR/.git" ]; then
    say "Обновляю Materialfy в $DIR"
    git -C "$DIR" pull --ff-only --quiet || fail "Не удалось обновить $DIR (там есть свои правки?). Удалите папку и запустите скрипт снова."
else
    [ -n "${MATERIALFY_REPO:-}" ] || fail "Укажите адрес исходников: MATERIALFY_REPO=<git-url> bash install.sh (или запустите скрипт из репозитория)."
    say "Скачиваю Materialfy в $DIR"
    mkdir -p "$(dirname "$DIR")"
    git clone --depth 1 --quiet "$MATERIALFY_REPO" "$DIR"
fi

# --- Qt 6.12 ----------------------------------------------------------------

QT_PRIVATE=""
if [ -z "$QMAKE" ]; then
    QT_PRIVATE="$DIR/qt/$QT_VERSION/$QT_ARCH"
    say "Qt $QT_VERSION в системе нет — скачиваю в $QT_PRIVATE (около 250 МБ)"
    QMAKE="$(python3 "$DIR/.github/scripts/install_qt.py" --host "$QT_HOST" --version "$QT_VERSION" \
        --addons qtshadertools qtimageformats --out "$QT_PRIVATE" | tail -n1)"
fi
qt_ok "$QMAKE" || fail "Qt ${QT_VERSION%.*}+ не найден ($QMAKE). Укажите свой: MATERIALFY_QMAKE=/путь/к/qmake6"
say "Qt $("$QMAKE" -query QT_VERSION): $QMAKE"

# --- Rust -------------------------------------------------------------------

rust_ok() { have cargo && ver_ge "$(rustc --version | awk '{print $2}')" "$RUST_MIN"; }
if ! rust_ok; then
    if have rustup; then
        say "Обновляю Rust (rustup update stable)"
        rustup update stable --no-self-update
        rustup default stable >/dev/null
    else
        say "Ставлю Rust через rustup (в ~/.cargo, без sudo)"
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --no-modify-path
    fi
    # shellcheck disable=SC1091
    [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
    rust_ok || fail "Нужен Rust $RUST_MIN или новее (сейчас: $(rustc --version 2>/dev/null || echo нет))."
fi
say "$(rustc --version)"

# --- Сборка -----------------------------------------------------------------

say "Собираю Materialfy (первый раз — 5–15 минут)"
# --locked: Cargo.lock держит vergen 9.0.6 (9.1 ломает build-скрипт librespot-core)
(cd "$DIR" && QMAKE="$QMAKE" cargo build --locked --release -p "$APP" --quiet) || fail "Сборка не удалась (вывод выше)."
mkdir -p "$DIR/bin"
install -m755 "$DIR/target/release/$APP" "$DIR/bin/$APP"
[ "${MATERIALFY_KEEP_BUILD:-}" = "1" ] || [ "$IN_PLACE" = "1" ] || rm -rf "$DIR/target"

# --- Запуск: команда и значок в меню ----------------------------------------
# QML и ресурсы exe находит сам: $DIR/src/materialfy/qml — вверх от $DIR/bin

mkdir -p "$BIN" "$APPS" "$ICONS" "$ICONS_PNG"
{
    echo '#!/bin/sh'
    [ -n "$QT_PRIVATE" ] && echo "export LD_LIBRARY_PATH=\"$QT_PRIVATE/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\""
    echo "exec \"$DIR/bin/$APP\" \"\$@\""
} > "$BIN/$APP"
chmod +x "$BIN/$APP"
cp "$DIR/src/materialfy/assets/$APP.svg" "$ICONS/$APP.svg"
cp "$DIR/$APP.png" "$ICONS_PNG/$APP.png"
cat > "$APPS/$APP.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Materialfy
GenericName=Музыкальный плеер
Comment=Клиент Spotify в стиле Material 3 Expressive
Exec=$BIN/$APP %U
Icon=$APP
Terminal=false
Categories=AudioVideo;Audio;Player;
StartupWMClass=$APP
DESKTOP
have update-desktop-database && update-desktop-database "$APPS" >/dev/null 2>&1 || true

say "Готово. Запуск: значок Materialfy в меню приложений или команда: $APP"
case ":$PATH_ORIG:" in
    *":$BIN:"*) ;;
    *) echo "    Если команда $APP не находится — $BIN нет в PATH: запускайте $BIN/$APP или из меню." ;;
esac
echo "    При первом запуске войдите в Spotify: программа откроет браузер. Воспроизведение требует Premium."
