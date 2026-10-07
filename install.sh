#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════╗
# ║  GigDownloader - universal installer                  ║
# ║  Termux • Linux • macOS (no Homebrew needed)          ║
# ╚═══════════════════════════════════════════════════════╝
#
#   Install / update :  curl -fsSL https://raw.githubusercontent.com/xauusd25/GigDownloader/main/install.sh | bash
#   Uninstall        :  curl -fsSL https://raw.githubusercontent.com/xauusd25/GigDownloader/main/install.sh | bash -s -- uninstall
#
# Windows: use install.ps1 (PowerShell) instead.

set -e

ORIG_PATH="$PATH"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# ─────────────────────────── Settings ─────────────────────────
REPO="xauusd25/GigDownloader"
APP_ZIP="https://github.com/$REPO/archive/refs/heads/main.zip"
CONF_DIR="$HOME/.gigdownloader"
BIN_DIR="$CONF_DIR/bin"            # Deno lives here (cookies etc. stay in CONF_DIR)
PATH_MARK="# added by GigDownloader installer"

ACTION="install"
case "${1:-}" in
    update|--update)                ACTION="update" ;;
    uninstall|--uninstall|remove)   ACTION="uninstall" ;;
esac

# ─────────────────────────── Colors ───────────────────────────
N=$'\033[0m'
R=$'\033[1;38;5;196m'
G=$'\033[1;38;5;82m'
Y=$'\033[1;38;5;220m'
C=$'\033[1;38;5;51m'
W=$'\033[1;38;5;255m'
GRAY=$'\033[38;5;244m'
LAV=$'\033[1;38;5;183m'
SHADOW=$'\033[0;38;5;99m'
TEAL=$'\033[1;38;5;80m'

LOGO=(
" ██████╗ ██╗ ██████╗ "
"██╔════╝ ██║██╔════╝ "
"██║  ███╗██║██║  ███╗"
"██║   ██║██║██║   ██║"
"╚██████╔╝██║╚██████╔╝"
" ╚═════╝ ╚═╝ ╚═════╝ "
)

FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

TOTAL_STEPS=1
STEP=0
CUR_PID=""
OS=""
ARCH=""
NOTES=()
LINK_DONE=0
RC_FILE=""

# ─────────────────────────── Helpers ──────────────────────────
rule() {  # rule <width> <color>
    local s="" i
    for ((i = 0; i < $1; i++)); do s+="━"; done
    printf '%s%s%s\n' "$2" "$s" "$N"
}

mini_bar() {  # mini_bar <done>
    local s="" i
    for ((i = 1; i <= TOTAL_STEPS; i++)); do
        if [ "$i" -le "$1" ]; then s+="▰"; else s+="▱"; fi
    done
    printf '%s' "$s"
}

get_cols() {
    # Works even when piped (curl | bash) and no tty on stdin/stdout
    local c="" r
    r=$({ stty size < /dev/tty; } 2>/dev/null) || r=""
    set -- $r
    c="${2:-}"
    if [ -z "$c" ]; then c=$({ tput cols < /dev/tty; } 2>/dev/null || true); fi
    if [ -z "$c" ]; then c="${COLUMNS:-}"; fi
    case "$c" in ''|*[!0-9]*) c=80 ;; esac
    echo "$c"
}

has_tty() { ( : < /dev/tty ) 2>/dev/null; }

print_header() {
    local cols pad line sub="Downloader Installer"
    cols=$(get_cols)
    clear
    echo
    if [ "$cols" -ge 22 ]; then
        pad=$(( (cols - 21) / 2 ))
        for line in "${LOGO[@]}"; do
            printf '%*s%s%s%s\n' "$pad" '' "$SHADOW" \
                "$(printf '%s' "$line" | sed "s/█/${LAV}█${SHADOW}/g")" "$N"
        done
        pad=$(( (cols - ${#sub}) / 2 ))
        if [ "$pad" -lt 0 ]; then pad=0; fi
        printf '%*s%s%s%s\n' "$pad" '' "$TEAL" "$sub" "$N"
    else
        printf '%sGigDownloader%s %sInstaller%s\n' "$LAV" "$N" "$TEAL" "$N"
    fi
    echo
}

fail_box() {  # fail_box <title> <line>...
    local title="$1" l
    shift
    printf ' %s┃ ⚠ %s%s\n' "$Y" "$title" "$N"
    printf ' %s┃%s\n' "$Y" "$N"
    for l in "$@"; do printf ' %s┃%s %s\n' "$Y" "$N" "$l"; done
    echo
    exit 1
}

cleanup() {
    tput cnorm 2>/dev/null || true
    if [ -n "$CUR_PID" ] && kill -0 "$CUR_PID" 2>/dev/null; then
        kill "$CUR_PID" 2>/dev/null || true
    fi
    rm -f "$LOG"
}
trap cleanup EXIT
trap 'echo; echo; echo " ${Y}⚠ Installation cancelled${N}"; exit 130' INT TERM

run_step() {
    STEP=$((STEP + 1))
    local msg="$1" cmd="$2" start=$SECONDS i=0 rc=0 secs

    : > "$LOG"
    bash -c "$cmd" > "$LOG" 2>&1 < /dev/null &
    CUR_PID=$!

    while kill -0 "$CUR_PID" 2>/dev/null; do
        printf '\r\033[K %s%s%s %s%s%s %s%s%s' \
            "$C" "${FRAMES[$((i % 10))]}" "$N" \
            "$GRAY" "$(mini_bar $((STEP - 1)))" "$N" \
            "$W" "$msg" "$N"
        i=$((i + 1))
        sleep 0.1
    done

    wait "$CUR_PID" || rc=$?
    CUR_PID=""
    secs=$((SECONDS - start))

    if [ "$rc" -eq 0 ]; then
        printf '\r\033[K %s✔%s %s%s%s %s %s%ss%s\n' \
            "$G" "$N" "$G" "$(mini_bar "$STEP")" "$N" "$msg" "$GRAY" "$secs" "$N"
    else
        printf '\r\033[K %s✘%s %s%s%s %s%s%s\n' \
            "$R" "$N" "$R" "$(mini_bar $((STEP - 1)))" "$N" "$R" "$msg" "$N"
        echo
        printf ' %s┏━ Error details ━━━━━━━━━━━━━━%s\n' "$R" "$N"
        tail -n 15 "$LOG" | while IFS= read -r l; do
            printf ' %s┃%s %s\n' "$R" "$N" "$l"
        done
        printf ' %s┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$R" "$N"
        cp "$LOG" "$HOME/gigdownloader_install_error.log" 2>/dev/null || true
        echo
        printf ' %sFull log saved:%s %s~/gigdownloader_install_error.log%s\n\n' "$Y" "$N" "$W" "$N"
        exit 1
    fi
}

done_line() {  # done_line <message>   (a finished step that ran in the foreground)
    STEP=$((STEP + 1))
    printf ' %s✔%s %s%s%s %s\n' "$G" "$N" "$G" "$(mini_bar "$STEP")" "$N" "$1"
}

skip_line() {  # skip_line <message>
    STEP=$((STEP + 1))
    printf ' %s⚠%s %s%s%s %s\n' "$Y" "$N" "$Y" "$(mini_bar "$STEP")" "$N" "$1"
}

# ───────────────────── System detection ───────────────────────
detect_os() {
    if [[ "${PREFIX:-}" == *com.termux* ]]; then
        OS="termux"
    else
        case "$(uname -s)" in
            Darwin) OS="macos" ;;
            Linux)  OS="linux" ;;
            *)      OS="" ;;
        esac
    fi
    case "$(uname -m)" in
        x86_64|amd64)  ARCH="x64" ;;
        arm64|aarch64) ARCH="arm64" ;;
        *)             ARCH="" ;;
    esac
}

installed_path() {
    PATH="$ORIG_PATH:$HOME/.local/bin" command -v gig 2>/dev/null || true
}

ask_action() {
    local found choice=1
    found="$(installed_path)"
    if [ -z "$found" ] || [ "$ACTION" != "install" ]; then
        return 0
    fi
    printf ' %s●%s GigDownloader is already installed at %s%s%s\n' "$GRAY" "$N" "$W" "$found" "$N"
    printf ' Choose an action: %s[1]%s Reinstall/Update  %s[2]%s Uninstall  %s[3]%s Exit: ' \
        "$C" "$N" "$C" "$N" "$C" "$N"
    if has_tty; then
        tput cnorm 2>/dev/null || true
        read -r choice < /dev/tty || choice=1
        tput civis 2>/dev/null || true
    else
        echo "1"
    fi
    case "$choice" in
        2) ACTION="uninstall" ;;
        3) echo; exit 0 ;;
        *) ACTION="update"; echo ;;
    esac
}

# ───────────────── Deno (JavaScript runtime for YouTube) ──────────────
install_deno() {
    set -e
    local tmp
    tmp="$(mktemp -d)"
    curl -fsSL "$DENO_URL" -o "$tmp/deno.zip"
    mkdir -p "$BIN_DIR"
    if command -v unzip >/dev/null 2>&1; then
        unzip -o -q "$tmp/deno.zip" -d "$BIN_DIR"
    elif command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "$tmp/deno.zip" -C "$BIN_DIR"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import sys,zipfile;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$tmp/deno.zip" "$BIN_DIR"
    else
        uv run --no-project --python 3.12 python -c "import sys,zipfile;zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$tmp/deno.zip" "$BIN_DIR"
    fi
    chmod +x "$BIN_DIR/deno"
    "$BIN_DIR/deno" --version
    rm -rf "$tmp"
}
export -f install_deno

deno_target() {
    case "$OS-$ARCH" in
        linux-x64)   echo "x86_64-unknown-linux-gnu" ;;
        linux-arm64) echo "aarch64-unknown-linux-gnu" ;;
        macos-x64)   echo "x86_64-apple-darwin" ;;
        macos-arm64) echo "aarch64-apple-darwin" ;;
        *)           echo "" ;;
    esac
}

is_musl() {
    ldd --version 2>&1 | grep -qi musl
}

# ───────────────── Putting `gig` on the PATH (Linux / macOS) ─────────────
add_path_line() {  # add_path_line <dir>
    local dir="$1" rc
    case "${SHELL##*/}" in
        zsh)  rc="$HOME/.zshrc" ;;
        bash) if [ "$OS" = "macos" ]; then rc="$HOME/.bash_profile"; else rc="$HOME/.bashrc"; fi ;;
        fish) NOTES+=("fish shell: run  fish_add_path $dir") ; return 0 ;;
        *)    rc="$HOME/.profile" ;;
    esac
    if ! grep -qsF "$PATH_MARK" "$rc"; then
        printf '\n%s\nexport PATH="%s:$PATH"\n' "$PATH_MARK" "$dir" >> "$rc"
    fi
    RC_FILE="$rc"
}

link_command() {
    local src n linked=0
    src="$(uv tool dir --bin 2>/dev/null || true)"
    if [ -z "$src" ]; then src="$HOME/.local/bin"; fi

    if PATH="$ORIG_PATH" command -v gig >/dev/null 2>&1; then
        LINK_DONE=1
        done_line "Command ready: gig"
        return 0
    fi

    if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
        for n in gig gigdownloader; do ln -sf "$src/$n" "/usr/local/bin/$n"; done
        linked=1
    elif command -v sudo >/dev/null 2>&1; then
        printf '\r\033[K %s▸%s Adding the command to /usr/local/bin %s(may ask for your password)%s\n' \
            "$Y" "$N" "$GRAY" "$N"
        tput cnorm 2>/dev/null || true
        if sudo mkdir -p /usr/local/bin \
            && sudo ln -sf "$src/gig" /usr/local/bin/gig \
            && sudo ln -sf "$src/gigdownloader" /usr/local/bin/gigdownloader; then
            linked=1
        fi
        tput civis 2>/dev/null || true
    fi

    if [ "$linked" -eq 1 ]; then
        LINK_DONE=1
        done_line "Command added: gig"
    else
        add_path_line "$src"
        done_line "Command added to your PATH (open a new terminal)"
    fi
}

remove_links() {
    local n target
    for n in gig gigdownloader; do
        target="$(readlink "/usr/local/bin/$n" 2>/dev/null || true)"
        case "$target" in
            */.local/bin/"$n"|*/uv/tools/*|*gigdownloader*)
                if [ -w /usr/local/bin ]; then
                    rm -f "/usr/local/bin/$n"
                elif command -v sudo >/dev/null 2>&1; then
                    tput cnorm 2>/dev/null || true
                    sudo rm -f "/usr/local/bin/$n" || true
                    tput civis 2>/dev/null || true
                fi
                ;;
        esac
    done
    local rc tmp line skip
    for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
        if [ -f "$rc" ] && grep -qF "$PATH_MARK" "$rc"; then
            tmp="$(mktemp)"
            skip=0
            while IFS= read -r line || [ -n "$line" ]; do
                if [ "$line" = "$PATH_MARK" ]; then skip=1; continue; fi
                if [ "$skip" -eq 1 ]; then skip=0; continue; fi
                printf '%s\n' "$line"
            done < "$rc" > "$tmp"
            cat "$tmp" > "$rc"
            rm -f "$tmp"
        fi
    done
    rm -rf "$BIN_DIR"
}

# ──────────────────────────── Actions ────────────────────────────
do_install() {
    local deno_t

    if [ "$OS" = "termux" ]; then
        TOTAL_STEPS=5
        run_step "Updating system packages" \
            "yes | apt --fix-broken install && yes | apt update && yes | apt upgrade"
        run_step "Installing Python"   "yes | pkg install python"
        run_step "Installing FFmpeg"   "yes | pkg install ffmpeg"
        run_step "Installing Node.js"  "yes | pkg install nodejs"
        run_step "Installing GigDownloader" \
            "{ pip install -U yt-dlp yt-dlp-threads && pip install --force-reinstall --no-deps \"$APP_ZIP\"; } || { pip install -U --break-system-packages yt-dlp yt-dlp-threads && pip install --force-reinstall --no-deps --break-system-packages \"$APP_ZIP\"; }"
        return 0
    fi

    TOTAL_STEPS=4
    run_step "Installing uv (Python manager)" \
        "if command -v uv >/dev/null 2>&1; then uv --version; else curl -LsSf https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh; fi"

    run_step "Installing GigDownloader" \
        "uv tool install --force --reinstall --python 3.12 --with 'yt-dlp[default]' --with imageio-ffmpeg 'gigdownloader @ $APP_ZIP'"

    deno_t="$(deno_target)"
    if [ -x "$BIN_DIR/deno" ] || command -v deno >/dev/null 2>&1; then
        done_line "Deno already installed"
    elif [ -z "$deno_t" ] || { [ "$OS" = "linux" ] && is_musl; }; then
        skip_line "Deno skipped (unsupported system) - YouTube needs Node.js 22+"
        NOTES+=("No Deno build for this system. For full YouTube quality install Node.js 22 or newer.")
    else
        export DENO_URL="https://github.com/denoland/deno/releases/latest/download/deno-${deno_t}.zip"
        export BIN_DIR
        run_step "Installing Deno (YouTube engine)" "install_deno"
    fi

    link_command
}

do_uninstall() {
    if [ "$OS" = "termux" ]; then
        TOTAL_STEPS=1
        run_step "Removing GigDownloader" "pip uninstall -y gigdownloader"
        return 0
    fi
    TOTAL_STEPS=2
    run_step "Removing GigDownloader" \
        "if command -v uv >/dev/null 2>&1; then uv tool uninstall gigdownloader; fi"
    remove_links
    done_line "Removed command links and Deno"
}

finish_install() {
    local cols rw
    cols=$(get_cols)
    rw=45
    if [ "$cols" -lt "$rw" ]; then rw="$cols"; fi
    echo
    rule "$rw" "$G"
    printf ' %s✔ Installation completed successfully%s  %s(%ss)%s\n' "$G" "$N" "$GRAY" "$SECONDS" "$N"
    rule "$rw" "$G"
    echo
    printf ' %s▶ Start it by typing:%s\n' "$Y" "$N"
    printf '   %sgig%s\n\n' "$C" "$N"
    printf ' %sAlso available:%s gigdownloader · gig --check · gig --help\n' "$GRAY" "$N"

    if [ -n "$RC_FILE" ]; then
        printf '\n %s▸%s Open a new terminal first (or run: %ssource %s%s)\n' "$Y" "$N" "$C" "$RC_FILE" "$N"
    fi
    if [ "$OS" = "termux" ] && [ ! -d "$HOME/storage" ]; then
        printf '\n %s▸%s Tip: run %stermux-setup-storage%s to save into your phone'"'"'s Downloads folder\n' \
            "$Y" "$N" "$C" "$N"
    fi
    local note
    for note in "${NOTES[@]}"; do
        printf '\n %s▸%s %s\n' "$Y" "$N" "$note"
    done
    echo
}

finish_uninstall() {
    echo
    rule 45 "$G"
    printf ' %s✔ GigDownloader removed%s\n' "$G" "$N"
    rule 45 "$G"
    echo
    printf ' %sYour downloads (GigVideos / GigAudios) and ~/.gigdownloader/cookies.txt were left untouched.%s\n\n' "$GRAY" "$N"
}

# ──────────────────────────── Start ───────────────────────────
detect_os

if [ "$OS" = "termux" ]; then
    LOG_DIR="${PREFIX}/tmp"
else
    LOG_DIR="${TMPDIR:-/tmp}"
fi
LOG="$(mktemp "${LOG_DIR%/}/gigdownloader_install.XXXXXX")"

tput civis 2>/dev/null || true
print_header

if [ -z "$OS" ]; then
    fail_box "Unsupported system" \
        "This installer supports Termux, Linux and macOS." \
        "On Windows, use PowerShell and run install.ps1 instead."
fi

if [ "$OS" != "termux" ] && ! command -v curl >/dev/null 2>&1; then
    fail_box "curl is required" "Install curl with your package manager, then run this installer again."
fi

ask_action

if [ "$ACTION" = "uninstall" ]; then
    do_uninstall
    finish_uninstall
else
    do_install
    finish_install
fi
