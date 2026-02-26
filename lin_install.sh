#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Music Downloader — установщик зависимостей (Linux)
#  Поддерживает: Arch/CachyOS, Debian/Ubuntu, Fedora, openSUSE
# ─────────────────────────────────────────────────────────────

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERR]${RESET}   $*"; exit 1; }
step()    { echo -e "\n${BOLD}▶ $*${RESET}"; }

# ── Определение дистрибутива ─────────────────────────────────

detect_distro() {
    if command -v pacman &>/dev/null; then
        echo "arch"
    elif command -v apt-get &>/dev/null; then
        echo "debian"
    elif command -v dnf &>/dev/null; then
        echo "fedora"
    elif command -v zypper &>/dev/null; then
        echo "opensuse"
    else
        echo "unknown"
    fi
}

DISTRO=$(detect_distro)

echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║   🎵 Music Downloader — Установка    ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${RESET}"
info "Дистрибутив: $DISTRO"
info "Будут установлены: python, yt-dlp, textual, pipx, spotdl"
echo ""
read -r -p "Продолжить? [Y/n] " ans
[[ "${ans,,}" == "n" ]] && echo "Отмена." && exit 0

# ── Python ───────────────────────────────────────────────────

step "Проверка Python 3"
if command -v python3 &>/dev/null; then
    PY_VER=$(python3 --version)
    success "Уже установлен: $PY_VER"
else
    info "Устанавливаю Python 3…"
    case $DISTRO in
        arch)    sudo pacman -S --noconfirm python ;;
        debian)  sudo apt-get install -y python3 python3-pip ;;
        fedora)  sudo dnf install -y python3 python3-pip ;;
        opensuse)sudo zypper install -y python3 python3-pip ;;
        *)       error "Установите Python 3 вручную: https://python.org" ;;
    esac
    success "Python установлен."
fi

# ── yt-dlp ───────────────────────────────────────────────────

step "Установка yt-dlp"
if command -v yt-dlp &>/dev/null; then
    success "yt-dlp уже установлен: $(yt-dlp --version)"
else
    case $DISTRO in
        arch)
            sudo pacman -S --noconfirm yt-dlp
            ;;
        debian)
            # Системный пакет часто устаревший — ставим через pipx
            sudo apt-get install -y pipx 2>/dev/null || pip3 install --user pipx
            pipx install yt-dlp
            ;;
        fedora)
            sudo dnf install -y yt-dlp 2>/dev/null || pipx install yt-dlp
            ;;
        opensuse)
            sudo zypper install -y yt-dlp 2>/dev/null || pipx install yt-dlp
            ;;
        *)
            warn "Неизвестный дистрибутив, пробую через pip…"
            pip3 install --user yt-dlp
            ;;
    esac
    success "yt-dlp установлен."
fi

# ── textual ──────────────────────────────────────────────────

step "Установка textual (TUI фреймворк)"
if python3 -c "import textual" &>/dev/null; then
    success "textual уже установлен."
else
    case $DISTRO in
        arch)
            # Проверяем официальный репозиторий
            if pacman -Si python-textual &>/dev/null 2>&1; then
                sudo pacman -S --noconfirm python-textual
            else
                pipx install textual 2>/dev/null || pip3 install --user textual
            fi
            ;;
        debian)
            sudo apt-get install -y python3-textual 2>/dev/null \
                || pip3 install --user --break-system-packages textual \
                || pip3 install --user textual
            ;;
        *)
            pip3 install --user textual 2>/dev/null \
                || pip3 install --break-system-packages textual
            ;;
    esac
    success "textual установлен."
fi

# ── pipx ─────────────────────────────────────────────────────

step "Проверка pipx"
if ! command -v pipx &>/dev/null; then
    info "Устанавливаю pipx…"
    case $DISTRO in
        arch)    sudo pacman -S --noconfirm python-pipx ;;
        debian)  sudo apt-get install -y pipx ;;
        fedora)  sudo dnf install -y pipx ;;
        opensuse)sudo zypper install -y python3-pipx ;;
        *)       pip3 install --user pipx ;;
    esac
    # Добавить ~/.local/bin в PATH если нужно
    export PATH="$HOME/.local/bin:$PATH"
    success "pipx установлен."
else
    success "pipx уже есть: $(pipx --version)"
fi

# ── spotdl (Spotify) ─────────────────────────────────────────

step "Установка spotdl (поддержка Spotify)"
if command -v spotdl &>/dev/null; then
    success "spotdl уже установлен: $(spotdl --version 2>/dev/null || echo 'ok')"
else
    pipx install spotdl
    success "spotdl установлен."
fi

# ── ffmpeg (нужен yt-dlp для конвертации) ────────────────────

step "Проверка ffmpeg"
if command -v ffmpeg &>/dev/null; then
    success "ffmpeg уже установлен."
else
    info "Устанавливаю ffmpeg…"
    case $DISTRO in
        arch)    sudo pacman -S --noconfirm ffmpeg ;;
        debian)  sudo apt-get install -y ffmpeg ;;
        fedora)  sudo dnf install -y ffmpeg --allowerasing ;;
        opensuse)sudo zypper install -y ffmpeg ;;
        *)       warn "Установите ffmpeg вручную: https://ffmpeg.org/download.html" ;;
    esac
    command -v ffmpeg &>/dev/null && success "ffmpeg установлен." || warn "ffmpeg не найден, конвертация может не работать."
fi

# ── PATH ─────────────────────────────────────────────────────

step "Проверка PATH"
PIPX_BIN="$HOME/.local/bin"
SHELL_RC=""
case "$SHELL" in
    */bash) SHELL_RC="$HOME/.bashrc" ;;
    */zsh)  SHELL_RC="$HOME/.zshrc" ;;
    */fish) SHELL_RC="$HOME/.config/fish/config.fish" ;;
esac

if [[ ":$PATH:" != *":$PIPX_BIN:"* ]]; then
    warn "$PIPX_BIN не в PATH."
    if [[ -n "$SHELL_RC" ]]; then
        echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$SHELL_RC"
        info "Добавил в $SHELL_RC. Перезапустите терминал или выполните:"
        echo -e "  ${CYAN}source $SHELL_RC${RESET}"
    fi
else
    success "PATH настроен корректно."
fi

# ── Итог ─────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}${BOLD}✅ Все зависимости установлены!${RESET}"
echo ""
echo -e "  Запуск:  ${CYAN}python3 playlist_downloader.py${RESET}"
echo ""

# Проверка финальная
echo -e "${BOLD}Версии:${RESET}"
python3  --version       2>/dev/null && true
yt-dlp   --version       2>/dev/null | head -1 | sed 's/^/  yt-dlp  /'  || warn "yt-dlp не найден в PATH"
spotdl   --version       2>/dev/null | head -1 | sed 's/^/  spotdl  /'  || warn "spotdl не найден в PATH"
ffmpeg   -version        2>/dev/null | head -1 | sed 's/^/  ffmpeg  /'  || warn "ffmpeg не найден в PATH"
python3 -c "import textual; print(f'  textual  {textual.__version__}')" 2>/dev/null || warn "textual не найден"
