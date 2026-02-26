#!/usr/bin/env python3
"""
Music Downloader TUI
Установка: sudo pacman -S yt-dlp python-textual
           pipx install spotdl   (для Spotify)
"""

import subprocess, sys, os, re, platform
from pathlib import Path

IS_WINDOWS = platform.system() == "Windows"

from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical, ScrollableContainer
from textual.widgets import Header, Footer, Input, Button, Label, Select, Static
from textual.reactive import reactive
from textual import work
from textual.binding import Binding


# ── Конфиг ────────────────────────────────────────────────────────────────────

PLATFORMS = {
    "auto":       "🔍 Авто",
    "youtube":    "🎬 YouTube",
    "soundcloud": "☁  SoundCloud",
    "spotify":    "🎵 Spotify",
    "yandex":     "🎧 Яндекс Музыка",
}

FORMATS = ["mp3 320k", "mp3 128k", "flac", "m4a", "opus", "wav", "оригинал"]
FORMAT_MAP = {
    "mp3 320k":  ("mp3",  "320"),
    "mp3 128k":  ("mp3",  "128"),
    "flac":      ("flac", None),
    "m4a":       ("m4a",  None),
    "opus":      ("opus", None),
    "wav":       ("wav",  None),
    "оригинал":  ("best", None),
}

OUTPUT_TEMPLATES = {
    "track":    "%(uploader,artist,channel|Неизвестный)s - %(title)s.%(ext)s",
    "album":    "%(uploader,artist,channel|Неизвестный)s - %(album,playlist_title|Альбом)s/%(track_number,playlist_index|00)02d - %(title)s.%(ext)s",
    "playlist": "%(playlist_uploader,uploader,channel|Плейлист)s - %(playlist_title,title|Без названия)s/%(playlist_index|00)02d - %(title)s.%(ext)s",
}

CT_ICONS = {"track": "♪", "album": "◉", "playlist": "≡", "?": "?"}

BASE_DIR = str(Path.home() / "Music" / "Downloads")

# Символы запрещённые в именах файлов/папок Windows
_WIN_BAD = re.compile(r'[<>:"/\\|?*]')

def win_safe(name: str) -> str:
    """Заменяет запрещённые символы Windows на безопасные."""
    if not IS_WINDOWS:
        return name
    return _WIN_BAD.sub("_", name).strip(". ")
BAR_W    = 44
FILL     = "█"
EMPTY    = "░"


# ── Определение по URL ────────────────────────────────────────────────────────

def detect_platform(url: str) -> str | None:
    u = url.lower()
    if "youtube.com" in u or "youtu.be" in u: return "youtube"
    if "soundcloud.com" in u:                 return "soundcloud"
    if "spotify.com" in u:                    return "spotify"
    if "music.yandex" in u:                   return "yandex"
    return None


def detect_ct(url: str) -> str:
    u = url.lower()
    if "/track/" in u:                                           return "track"
    if "/album/" in u and "/track/" not in u:                   return "album"
    if "/playlist/" in u or "/playlists/" in u or "list=" in u: return "playlist"
    if "watch?v=" in u or "youtu.be/" in u:                     return "track"
    if re.search(r"soundcloud\.com/[^/]+/sets/", u):            return "playlist"
    if re.search(r"soundcloud\.com/[^/]+/[^/?]+$", u):         return "track"
    return "track"   # fallback


# ── Команда ───────────────────────────────────────────────────────────────────

# Шаблон прогресса: все поля разделены | для надёжного парсинга
PROGRESS_TMPL = "%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress._total_bytes_str)s|%(progress._downloaded_bytes_str)s"

def build_cmd(platform, ct, url, fmt_str, out_dir):
    fmt, quality = FORMAT_MAP.get(fmt_str, ("mp3", "320"))

    if platform == "spotify":
        cmd = ["spotdl", url, "--output", out_dir]
        if fmt != "best": cmd += ["--format", fmt]
        if quality:       cmd += ["--bitrate", quality + "k"]
        return cmd

    cmd = [
        "yt-dlp", "--no-warnings", "--newline",
        "--progress-template", PROGRESS_TMPL,
        "--windows-filenames" if IS_WINDOWS else "--no-windows-filenames",
    ]

    if fmt == "best":
        cmd += ["-f", "bestaudio/best"]
    else:
        cmd += ["-f", "bestaudio/best", "--extract-audio", "--audio-format", fmt]
        if quality and fmt == "mp3":
            cmd += ["--audio-quality", quality + "k"]

    cmd += ["--embed-thumbnail", "--add-metadata"]
    cmd += ["--no-playlist"] if ct == "track" else ["--yes-playlist"]
    cmd += ["-o", os.path.join(out_dir, OUTPUT_TEMPLATES.get(ct, OUTPUT_TEMPLATES["track"]))]
    cmd.append(url)
    return cmd


def parse_progress(line: str) -> dict | None:
    parts = line.strip().split("|")
    if len(parts) != 5:
        return None
    pct_s, speed, eta, total, downloaded = [p.strip() for p in parts]
    try:
        pct = float(pct_s.replace("%", "").strip())
        return {"pct": pct, "speed": speed, "eta": eta,
                "total": total, "downloaded": downloaded}
    except ValueError:
        return None


# ── Карточка загрузки ─────────────────────────────────────────────────────────

class DownloadCard(Static):
    DEFAULT_CSS = """
    DownloadCard {
        height: auto;
        border: round $panel-lighten-1;
        margin: 0 0 1 0;
        padding: 0 1 1 1;
        background: $surface;
    }
    DownloadCard.running { border: round $warning; }
    DownloadCard.done    { border: round $success; }
    DownloadCard.error   { border: round $error;   }

    .card-head  { height: 1; margin-top: 1; }
    .card-ct    { width: 5;  color: $accent; text-style: bold; }
    .card-plat  { width: 18; color: $text-muted; }
    .card-url   { width: 1fr; }

    .card-bar   { height: 1; margin-top: 1; }

    .card-info  { height: 1; margin-top: 0; color: $text-muted; }
    .ci-pct     { width: 8;  text-style: bold; color: $accent; }
    .ci-speed   { width: 14; }
    .ci-eta     { width: 14; }
    .ci-size    { width: 22; }
    .ci-track   { width: 1fr; color: $success; }
    """

    def __init__(self, url, platform, ct, fmt, out_dir):
        super().__init__()
        self.url      = url
        self.platform = platform
        self.ct       = ct
        self.fmt      = fmt
        self.out_dir  = out_dir

    def compose(self) -> ComposeResult:
        short = (self.url[:60] + "…") if len(self.url) > 60 else self.url
        with Horizontal(classes="card-head"):
            yield Label(CT_ICONS.get(self.ct, "?"),          classes="card-ct")
            yield Label(f"[{self.platform.upper()}]",        classes="card-plat")
            yield Label(short,                               classes="card-url")

        yield Label(EMPTY * BAR_W, id="bar",  classes="card-bar")

        with Horizontal(classes="card-info"):
            yield Label("   0%",  id="ci_pct",   classes="ci-pct")
            yield Label("",       id="ci_speed", classes="ci-speed")
            yield Label("",       id="ci_eta",   classes="ci-eta")
            yield Label("",       id="ci_size",  classes="ci-size")
            yield Label("⏳ В очереди", id="ci_track", classes="ci-track")

    # helpers
    def _render_bar(self, pct: float, color: str = "green") -> str:
        n = min(BAR_W, int(BAR_W * pct / 100))
        return f"[{color}]{FILL * n}[/][dim]{EMPTY * (BAR_W - n)}[/]"

    def _lbl(self, id_: str) -> Label:
        return self.query_one(f"#{id_}", Label)

    # public
    def set_running(self):
        self.add_class("running")
        self._lbl("ci_track").update("⚡ Загружается…")

    def update_progress(self, p: dict):
        pct = p["pct"]
        self._lbl("bar").update(self._render_bar(pct))
        self._lbl("ci_pct").update(f"{pct:5.1f}%")
        speed = p["speed"] if p["speed"] not in ("N/A", "Unknown") else ""
        eta   = p["eta"]   if p["eta"]   not in ("N/A", "Unknown") else ""
        dl    = p["downloaded"]
        tot   = p["total"]
        self._lbl("ci_speed").update(f"⚡ {speed}" if speed else "")
        self._lbl("ci_eta").update(f"⏱ {eta}"      if eta   else "")
        size_str = f"💾 {dl} / {tot}" if tot not in ("N/A", "~0") else (f"💾 {dl}" if dl else "")
        self._lbl("ci_size").update(size_str)

    def update_track(self, now: int, total: int, title: str = ""):
        short = (title[:32] + "…") if len(title) > 32 else title
        label = f"[{now}/{total}]" + (f" {short}" if short else "")
        self._lbl("ci_track").update(label)
        # двигаем бар по треку, если yt-dlp ещё не дал % (между треками)
        if total > 0:
            pct = (now - 1) / total * 100
            self._lbl("bar").update(self._render_bar(pct))
            self._lbl("ci_pct").update(f"{pct:5.1f}%")

    def set_done(self, n_tracks: int = 0):
        self.remove_class("running")
        self.add_class("done")
        self._lbl("bar").update(f"[green]{FILL * BAR_W}[/]")
        self._lbl("ci_pct").update("[green]100.0%[/]")
        self._lbl("ci_speed").update("")
        self._lbl("ci_eta").update("")
        suffix = f" · {n_tracks} треков" if n_tracks > 1 else ""
        self._lbl("ci_track").update(f"[green]✅ Готово{suffix}[/]")

    def set_error(self, msg: str):
        self.remove_class("running")
        self.add_class("error")
        self._lbl("bar").update(f"[red]{'✗' * BAR_W}[/]")
        self._lbl("ci_pct").update("[red] ERR[/]")
        self._lbl("ci_track").update(f"[red]{msg[:55]}[/]")


# ── Приложение ────────────────────────────────────────────────────────────────

class MusicDownloader(App):

    TITLE = "🎵 Music Downloader"

    CSS = """
    Screen { background: $background; }

    /* панель ввода */
    #topbar {
        height: auto;
        background: $panel;
        border-bottom: solid $primary;
        padding: 1 2;
    }
    #row-url   { height: 3; }
    #row-opts  { height: 3; margin-top: 1; }
    #row-hint  { height: 1; }

    #url_input   { width: 1fr; }
    #dl_btn      { width: 18; margin-left: 1; }
    #platform_sel{ width: 1fr; }
    #format_sel  { width: 1fr; margin-left: 1; }
    #outdir_input{ width: 1fr; margin-left: 1; }

    #hint { color: $success; }

    /* очередь */
    #queue { height: 1fr; padding: 1 2; overflow-y: auto; }

    /* нет элементов */
    #empty { color: $text-muted; content-align: center middle; height: 1fr; }
    """

    BINDINGS = [
        Binding("ctrl+d", "dl",    "Скачать"),
        Binding("ctrl+x", "clear", "Очистить"),
        Binding("ctrl+q", "quit",  "Выход"),
    ]

    _count: reactive[int] = reactive(0)

    def compose(self) -> ComposeResult:
        yield Header()

        with Vertical(id="topbar"):
            with Horizontal(id="row-url"):
                yield Input(placeholder="Вставьте URL трека / альбома / плейлиста…", id="url_input")
                yield Button("⬇  Скачать [^D]", id="dl_btn", variant="primary")

            with Horizontal(id="row-opts"):
                yield Select([(v, k) for k, v in PLATFORMS.items()], value="auto", id="platform_sel")
                yield Select([(f, f) for f in FORMATS], value="mp3 320k", id="format_sel")
                yield Input(value=BASE_DIR, placeholder="Папка сохранения…", id="outdir_input")

            with Horizontal(id="row-hint"):
                yield Label("", id="hint")

        with ScrollableContainer(id="queue"):
            yield Static("Добавьте URL выше ↑", id="empty")

        yield Footer()

    # ── события ──────────────────────────────────────────────────────────────

    def on_input_changed(self, e: Input.Changed):
        if e.input.id != "url_input":
            return
        url = e.value.strip()
        platform = detect_platform(url)
        ct       = detect_ct(url) if url else None
        parts = []
        if platform:
            self.query_one("#platform_sel", Select).value = platform
            parts.append(PLATFORMS[platform])
        if ct:
            parts.append(f"{CT_ICONS.get(ct,'?')} {ct.capitalize()}")
        hint = self.query_one("#hint", Label)
        hint.update(("🔍 " + "  ·  ".join(parts)) if parts else "")

    def on_button_pressed(self, e: Button.Pressed):
        if e.button.id == "dl_btn":
            self.action_dl()

    def action_dl(self):
        url = self.query_one("#url_input", Input).value.strip()
        if not url:
            return

        p = str(self.query_one("#platform_sel", Select).value)
        if p == "auto":
            p = detect_platform(url) or "youtube"

        ct      = detect_ct(url)
        fmt     = str(self.query_one("#format_sel", Select).value)
        out_dir = self.query_one("#outdir_input", Input).value.strip() or BASE_DIR
        Path(out_dir).mkdir(parents=True, exist_ok=True)

        # убрать заглушку
        empty = self.query("#empty")
        if empty:
            empty.first().remove()

        card = DownloadCard(url, p, ct, fmt, out_dir)
        self.query_one("#queue").mount(card)
        self._count += 1

        self.query_one("#url_input", Input).clear()
        self.query_one("#hint", Label).update("")
        self._do_download(card, p, ct, url, fmt, out_dir)

    def action_clear(self):
        q = self.query_one("#queue")
        for c in list(q.children):
            c.remove()
        q.mount(Static("Добавьте URL выше ↑", id="empty"))
        self._count = 0

    # ── воркер ───────────────────────────────────────────────────────────────

    @work(exclusive=False, thread=True)
    def _do_download(self, card: DownloadCard, platform, ct, url, fmt, out_dir):
        self.call_from_thread(card.set_running)

        cmd = build_cmd(platform, ct, url, fmt, out_dir)

        try:
            proc = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, bufsize=1,
            )

            n_tracks     = 0
            track_total  = 0
            cur_title    = ""

            for raw in iter(proc.stdout.readline, ""):
                line = raw.rstrip()
                if not line:
                    continue

                # прогресс yt-dlp (кастомный шаблон)
                p = parse_progress(line)
                if p:
                    self.call_from_thread(card.update_progress, p)
                    continue

                # "Downloading item X of Y" (плейлист/альбом)
                m = re.search(r"Downloading item (\d+) of (\d+)", line)
                if m:
                    now, total = int(m.group(1)), int(m.group(2))
                    track_total = total
                    self.call_from_thread(card.update_track, now, total, cur_title)
                    cur_title = ""
                    continue

                # "Downloading video X of Y"
                m = re.search(r"Downloading video (\d+) of (\d+)", line)
                if m:
                    now, total = int(m.group(1)), int(m.group(2))
                    track_total = total
                    self.call_from_thread(card.update_track, now, total, cur_title)
                    cur_title = ""
                    continue

                # название из строки Destination
                m = re.search(r"Destination:.*?([^/\\]+)\.\w{1,5}$", line)
                if m:
                    cur_title = m.group(1)
                    n_tracks += 1

                # [ExtractAudio] — трек извлечён
                if "[ExtractAudio]" in line:
                    n_tracks += 1

                # spotdl "X/Y songs"
                m = re.search(r"(\d+)/(\d+)\s+song", line)
                if m:
                    now, total = int(m.group(1)), int(m.group(2))
                    track_total = total
                    n_tracks    = now
                    pct = now / total * 100 if total else 0
                    fake = {"pct": pct, "speed": "", "eta": "",
                            "total": str(total), "downloaded": str(now)}
                    self.call_from_thread(card.update_progress, fake)
                    self.call_from_thread(card.update_track, now, total)

            proc.wait()
            final = max(n_tracks, track_total)

            if proc.returncode == 0:
                self.call_from_thread(card.set_done, final)
            else:
                self.call_from_thread(card.set_error, f"Ошибка (код {proc.returncode})")

        except FileNotFoundError:
            tool = "spotdl" if platform == "spotify" else "yt-dlp"
            self.call_from_thread(card.set_error, f"'{tool}' не найден")
        except Exception as ex:
            self.call_from_thread(card.set_error, str(ex)[:80])


# ── Запуск ────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    check_cmd = ["where", "yt-dlp"] if IS_WINDOWS else ["which", "yt-dlp"]
    if subprocess.run(check_cmd, capture_output=True).returncode != 0:
        print("⚠  yt-dlp не найден.")
        if IS_WINDOWS:
            print("   Установите: winget install yt-dlp")
        else:
            print("   Установите: sudo pacman -S yt-dlp")
    try:
        MusicDownloader().run()
    except ImportError:
        print("❌ Установите textual: sudo pacman -S python-textual")
        sys.exit(1)