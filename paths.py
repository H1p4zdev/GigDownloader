"""Universal download folders: Windows, macOS, Linux and Termux.

Videos are saved in  <Downloads>/GigVideos
Audio  is saved in   <Downloads>/GigAudios
"""

import os
import sys
from pathlib import Path

VIDEO_FOLDER = "GigVideos"
AUDIO_FOLDER = "GigAudios"
CONFIG_DIR = Path.home() / ".gigdownloader"


def is_termux() -> bool:
    return "com.termux" in os.environ.get("PREFIX", "") or "TERMUX_VERSION" in os.environ


def termux_storage_ready() -> bool:
    """True once `termux-setup-storage` has been run (shared storage linked)."""
    return (Path.home() / "storage" / "downloads").is_dir()


def _windows_downloads() -> Path:
    """The real Downloads folder (works even if the user moved it)."""
    try:
        import winreg  # only exists on Windows

        key = r"Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, key) as k:
            value, _ = winreg.QueryValueEx(k, "{374DE290-123F-4565-9164-39C4925E467B}")
        return Path(os.path.expandvars(value))
    except Exception:
        return Path.home() / "Downloads"


def _xdg_downloads() -> Path:
    """Linux: honour the XDG user-dirs setting (localized/moved Downloads)."""
    config_home = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    cfg = Path(config_home) / "user-dirs.dirs"
    try:
        for line in cfg.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("XDG_DOWNLOAD_DIR="):
                value = line.split("=", 1)[1].strip().strip('"').strip("'")
                value = value.replace("$HOME", str(Path.home()))
                if value:
                    return Path(value)
    except OSError:
        pass
    return Path.home() / "Downloads"


def default_download_base() -> Path:
    """The system's Downloads folder (GigVideos / GigAudios are created inside)."""
    override = os.environ.get("GIG_DOWNLOAD_DIR")
    if override:
        return Path(override).expanduser()

    if is_termux():
        shared = Path.home() / "storage" / "downloads"
        return shared if shared.is_dir() else Path.home() / "Downloads"
    if sys.platform.startswith("win"):
        return _windows_downloads()
    if sys.platform == "darwin":
        return Path.home() / "Downloads"
    return _xdg_downloads()


def _usable(path: Path) -> bool:
    try:
        path.mkdir(parents=True, exist_ok=True)
        return os.access(path, os.W_OK)
    except OSError:
        return False


def ensure_download_dirs(preferred=None):
    """Return (videos_dir, audios_dir) on the first base folder we can write to."""
    bases = []
    if preferred:
        bases.append(Path(preferred).expanduser())
    bases += [default_download_base(), Path.home(), Path.cwd()]
    for base in bases:
        videos, audios = base / VIDEO_FOLDER, base / AUDIO_FOLDER
        if _usable(videos) and _usable(audios):
            return videos, audios
    return Path.cwd() / VIDEO_FOLDER, Path.cwd() / AUDIO_FOLDER
