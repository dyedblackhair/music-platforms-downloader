# ─────────────────────────────────────────────────────────────
#  Music Downloader — установщик зависимостей (Windows)
#  Запуск: правой кнопкой → "Запустить с PowerShell"
#       или: powershell -ExecutionPolicy Bypass -File install_windows.ps1
# ─────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"

# ── Цвета ────────────────────────────────────────────────────

function Info    { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Cyan    }
function Success { param($msg) Write-Host "[OK]    $msg" -ForegroundColor Green   }
function Warn    { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow  }
function Err     { param($msg) Write-Host "[ERR]   $msg" -ForegroundColor Red; exit 1 }
function Step    { param($msg) Write-Host "`n▶ $msg" -ForegroundColor White       }

# ── Шапка ────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "  ║   🎵 Music Downloader — Установка    ║" -ForegroundColor Magenta
Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""
Info "Будут установлены: Python, yt-dlp, ffmpeg, textual, spotdl"
Write-Host ""
$ans = Read-Host "Продолжить? [Y/n]"
if ($ans -match "^[Nn]") { Write-Host "Отмена."; exit 0 }

# ── Права администратора (для winget/scoop) ───────────────────

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Warn "Скрипт запущен без прав администратора."
    Warn "Некоторые компоненты (winget) могут потребовать UAC-запрос."
}

# ── Хелпер: проверить наличие команды ────────────────────────

function Has { param($cmd) return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

# ── Обновить PATH в текущей сессии ───────────────────────────

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
}

# ── winget ───────────────────────────────────────────────────

Step "Проверка winget"
if (-not (Has "winget")) {
    Warn "winget не найден."
    Info "Установите App Installer из Microsoft Store:"
    Info "https://apps.microsoft.com/store/detail/app-installer/9NBLGGH4NNS1"
    Info "Или обновите Windows 10/11 — winget входит в стандартную поставку."
    $skip_winget = $true
} else {
    Success "winget найден: $(winget --version)"
    $skip_winget = $false
}

# ── Python ───────────────────────────────────────────────────

Step "Проверка Python 3"
if (Has "python") {
    $pyver = python --version 2>&1
    Success "Уже установлен: $pyver"
} else {
    if ($skip_winget) {
        Warn "Установите Python вручную: https://www.python.org/downloads/"
        Warn "При установке отметьте галочку 'Add Python to PATH'!"
        Read-Host "Нажмите Enter после установки Python…"
        Refresh-Path
    } else {
        Info "Устанавливаю Python через winget…"
        winget install --id Python.Python.3.12 --source winget --accept-package-agreements --accept-source-agreements -e
        Refresh-Path
    }
    if (Has "python") { Success "Python установлен." } else { Err "Python не найден после установки." }
}

# Проверяем версию
$pyver_num = python -c "import sys; print(sys.version_info.major)" 2>$null
if ($pyver_num -ne "3") { Err "Требуется Python 3, найден: $pyver_num" }

# ── pip ──────────────────────────────────────────────────────

Step "Проверка pip"
if (-not (Has "pip")) {
    Info "Устанавливаю pip…"
    python -m ensurepip --upgrade
    Refresh-Path
}
python -m pip install --upgrade pip --quiet
Success "pip готов."

# ── yt-dlp ───────────────────────────────────────────────────

Step "Установка yt-dlp"
if (Has "yt-dlp") {
    Success "yt-dlp уже установлен: $(yt-dlp --version)"
} else {
    $installed = $false

    # Пробуем winget
    if (-not $skip_winget) {
        try {
            Info "Устанавливаю yt-dlp через winget…"
            winget install --id yt-dlp.yt-dlp --source winget --accept-package-agreements --accept-source-agreements -e
            Refresh-Path
            $installed = $true
        } catch {
            Warn "winget не смог установить yt-dlp, пробую pip…"
        }
    }

    # Fallback через pip
    if (-not $installed) {
        Info "Устанавливаю yt-dlp через pip…"
        python -m pip install yt-dlp --quiet
        $installed = $true
    }

    Refresh-Path
    if (Has "yt-dlp") { Success "yt-dlp установлен: $(yt-dlp --version)" }
    else { Warn "yt-dlp не найден в PATH, попробуйте перезапустить терминал." }
}

# ── ffmpeg ───────────────────────────────────────────────────

Step "Установка ffmpeg (нужен для конвертации аудио)"
if (Has "ffmpeg") {
    Success "ffmpeg уже установлен."
} else {
    $installed = $false

    if (-not $skip_winget) {
        try {
            Info "Устанавливаю ffmpeg через winget…"
            winget install --id Gyan.FFmpeg --source winget --accept-package-agreements --accept-source-agreements -e
            Refresh-Path
            $installed = $true
        } catch {
            Warn "winget не смог установить ffmpeg."
        }
    }

    if (-not $installed) {
        Warn "Установите ffmpeg вручную: https://ffmpeg.org/download.html#build-windows"
        Warn "Скачайте 'ffmpeg-release-essentials.zip', распакуйте и добавьте папку bin в PATH."
    }

    Refresh-Path
    if (Has "ffmpeg") { Success "ffmpeg установлен." }
    else              { Warn "ffmpeg не найден — конвертация в mp3/flac/wav может не работать." }
}

# ── textual ──────────────────────────────────────────────────

Step "Установка textual (TUI фреймворк)"
$textual_check = python -c "import textual; print(textual.__version__)" 2>$null
if ($textual_check) {
    Success "textual уже установлен: $textual_check"
} else {
    Info "Устанавливаю textual через pip…"
    python -m pip install textual --quiet
    $textual_check = python -c "import textual; print(textual.__version__)" 2>$null
    if ($textual_check) { Success "textual установлен: $textual_check" }
    else                { Err "Не удалось установить textual." }
}

# ── pipx ─────────────────────────────────────────────────────

Step "Установка pipx (для spotdl)"
if (Has "pipx") {
    Success "pipx уже установлен."
} else {
    Info "Устанавливаю pipx…"
    python -m pip install pipx --quiet
    python -m pipx ensurepath
    Refresh-Path
    if (Has "pipx") { Success "pipx установлен." }
    else {
        Warn "pipx не найден в PATH — spotdl будет установлен через pip."
    }
}

# ── spotdl ───────────────────────────────────────────────────

Step "Установка spotdl (поддержка Spotify)"
if (Has "spotdl") {
    Success "spotdl уже установлен."
} else {
    if (Has "pipx") {
        Info "Устанавливаю spotdl через pipx…"
        pipx install spotdl
    } else {
        Info "Устанавливаю spotdl через pip…"
        python -m pip install spotdl --quiet
    }
    Refresh-Path
    if (Has "spotdl") { Success "spotdl установлен." }
    else              { Warn "spotdl не найден в PATH, перезапустите терминал." }
}

# ── Windows Terminal (рекомендация) ──────────────────────────

Step "Проверка Windows Terminal"
if (Has "wt") {
    Success "Windows Terminal найден."
} else {
    Warn "Windows Terminal не найден."
    if (-not $skip_winget) {
        $wt_ans = Read-Host "Установить Windows Terminal? (рекомендуется для TUI) [Y/n]"
        if ($wt_ans -notmatch "^[Nn]") {
            winget install --id Microsoft.WindowsTerminal --source winget --accept-package-agreements --accept-source-agreements -e
            Success "Windows Terminal установлен."
        }
    } else {
        Info "Установите из Microsoft Store: https://aka.ms/terminal"
    }
}

# ── Итог ─────────────────────────────────────────────────────

Write-Host ""
Write-Host "✅ Установка завершена!" -ForegroundColor Green
Write-Host ""
Write-Host "Версии:" -ForegroundColor White

python   --version 2>$null | ForEach-Object { Write-Host "  $_" }
try { $v = yt-dlp  --version 2>$null; Write-Host "  yt-dlp  $v" } catch { Warn "  yt-dlp  — не в PATH" }
try { ffmpeg -version 2>$null | Select-Object -First 1 | ForEach-Object { Write-Host "  $_" } } catch { Warn "  ffmpeg  — не в PATH" }
try { $v = spotdl  --version 2>$null; Write-Host "  spotdl  $v" } catch { Warn "  spotdl  — не в PATH" }
python -c "import textual; print(f'  textual  {textual.__version__}')" 2>$null

Write-Host ""
Write-Host "Запуск:" -ForegroundColor White
Write-Host "  python playlist_downloader.py" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠  Если команды не найдены — перезапустите терминал и попробуйте снова." -ForegroundColor Yellow
Write-Host ""

Read-Host "Нажмите Enter для выхода"
