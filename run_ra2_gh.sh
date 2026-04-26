#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -L)"
GAME_DIR="$SCRIPT_DIR/game"
PREFIX_DIR="$HOME/.wine-ra2-gh"
CONFIG_FILE="$SCRIPT_DIR/config.ini"
ASCII_MIRROR="$HOME/ra2gh_ascii"

if [ -z "${RA2_ASCII_REEXEC:-}" ] && printf '%s' "$SCRIPT_DIR" | LC_ALL=C grep -q '[^ -~]'; then
  if [ -x "$ASCII_MIRROR/$(basename "${BASH_SOURCE[0]}")" ]; then
    exec env RA2_ASCII_REEXEC=1 "$ASCII_MIRROR/$(basename "${BASH_SOURCE[0]}")" "$@"
  fi
fi

SCREEN_WIDTH=1024
SCREEN_HEIGHT=768
OUTPUT_WIDTH="$SCREEN_WIDTH"
OUTPUT_HEIGHT="$SCREEN_HEIGHT"
AUTO_DETECT=true

GHRA2_DIR="$GAME_DIR/GHra2"
RA2_INI="$GHRA2_DIR/Ra2.ini"
DDRAW_INI="$GHRA2_DIR/ddraw.ini"
PREFIX_SYSTEM32="$PREFIX_DIR/drive_c/windows/system32"
PREFIX_DDRAW_INI="$PREFIX_SYSTEM32/ddraw.ini"

load_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    return
  fi

  local value

  value="$(grep -E '^AUTO_DETECT=' "$CONFIG_FILE" | tail -n 1 | cut -d= -f2- | tr -d '[:space:]' || true)"
  if [ -n "$value" ]; then
    AUTO_DETECT="$value"
  fi

  value="$(grep -E '^SCREEN_WIDTH=' "$CONFIG_FILE" | tail -n 1 | cut -d= -f2- | tr -d '[:space:]' || true)"
  if [ -n "$value" ]; then
    SCREEN_WIDTH="$value"
  fi

  value="$(grep -E '^SCREEN_HEIGHT=' "$CONFIG_FILE" | tail -n 1 | cut -d= -f2- | tr -d '[:space:]' || true)"
  if [ -n "$value" ]; then
    SCREEN_HEIGHT="$value"
  fi
}

detect_display_resolution() {
  if ! command -v xrandr >/dev/null 2>&1; then
    return
  fi

  local mode=""
  mode="$(xrandr --current 2>/dev/null | awk '
    / connected primary / {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) {
          print $i
          exit
        }
      }
    }
  ' | head -n 1)"

  if [ -z "$mode" ]; then
    mode="$(xrandr --current 2>/dev/null | awk '
      / connected / {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$/) {
            print $i
            exit
          }
        }
      }
    ' | head -n 1)"
  fi

  if [ -n "$mode" ]; then
    mode="${mode%%+*}"
    OUTPUT_WIDTH="${mode%x*}"
    OUTPUT_HEIGHT="${mode#*x}"
  fi
}

find_cnc_ddraw_zip() {
  find "$HOME/.cache/winetricks/cnc_ddraw" -maxdepth 1 -type f -name 'cnc-ddraw-*.zip' 2>/dev/null | sort | tail -n 1
}

install_cnc_ddraw_to_prefix() {
  if ! command -v winetricks >/dev/null 2>&1; then
    return 1
  fi

  echo "正在安装 cnc-ddraw 兼容层..."
  WINEPREFIX="$PREFIX_DIR" winetricks -q cnc_ddraw
}

copy_cnc_ddraw_assets_from_prefix() {
  local copied=1

  mkdir -p "$GHRA2_DIR"

  if [ -f "$PREFIX_SYSTEM32/ddraw.dll" ]; then
    cp -f "$PREFIX_SYSTEM32/ddraw.dll" "$GHRA2_DIR/ddraw.dll"
    copied=0
  fi

  if [ -f "$PREFIX_SYSTEM32/cnc-ddraw config.exe" ]; then
    cp -f "$PREFIX_SYSTEM32/cnc-ddraw config.exe" "$GHRA2_DIR/cnc-ddraw config.exe"
    copied=0
  fi

  if [ -d "$PREFIX_SYSTEM32/Shaders" ]; then
    mkdir -p "$GHRA2_DIR/Shaders"
    cp -a "$PREFIX_SYSTEM32/Shaders/." "$GHRA2_DIR/Shaders/"
    copied=0
  fi

  return "$copied"
}

copy_cnc_ddraw_assets_from_cache() {
  local zip_file="$1"

  if [ -z "$zip_file" ] || [ ! -f "$zip_file" ] || ! command -v unzip >/dev/null 2>&1; then
    return 1
  fi

  mkdir -p "$GHRA2_DIR"
  unzip -oq "$zip_file" 'ddraw.dll' 'cnc-ddraw config.exe' 'Shaders/*' -d "$GHRA2_DIR" >/dev/null
}

ensure_cnc_ddraw_assets() {
  local zip_file=""
  local needs_assets=false

  if [ ! -d "$GHRA2_DIR" ]; then
    return
  fi

  if [ ! -f "$GHRA2_DIR/ddraw.dll" ] || [ ! -f "$GHRA2_DIR/cnc-ddraw config.exe" ] || [ ! -d "$GHRA2_DIR/Shaders" ]; then
    needs_assets=true
  fi

  if [ "$needs_assets" = false ]; then
    return
  fi

  zip_file="$(find_cnc_ddraw_zip || true)"
  if [ -z "$zip_file" ] && [ ! -f "$PREFIX_SYSTEM32/ddraw.dll" ]; then
    install_cnc_ddraw_to_prefix || true
    zip_file="$(find_cnc_ddraw_zip || true)"
  fi

  echo "正在同步 cnc-ddraw 到游戏目录..."
  copy_cnc_ddraw_assets_from_cache "$zip_file" || copy_cnc_ddraw_assets_from_prefix || true
}

ensure_section_key() {
  local file="$1"
  local section="$2"
  local key="$3"
  local value="$4"

  if ! grep -q "^\[$section\]" "$file"; then
    return
  fi

  if sed -n "/^\[$section\]/,/^\[/p" "$file" | grep -q "^$key="; then
    sed -i "/^\[$section\]/,/^\[/{s/^$key=.*/$key=$value/}" "$file"
  else
    sed -i "/^\[$section\]/a $key=$value" "$file"
  fi
}

delete_section_key() {
  local file="$1"
  local section="$2"
  local key="$3"

  if ! grep -q "^\[$section\]" "$file"; then
    return
  fi

  sed -i "/^\[$section\]/,/^\[/{/^$key=/d;}" "$file"
}

sync_game_config() {
  if [ -f "$RA2_INI" ]; then
    sed -i "s/^ScreenWidth=.*/ScreenWidth=${SCREEN_WIDTH}/" "$RA2_INI"
    sed -i "s/^ScreenHeight=.*/ScreenHeight=${SCREEN_HEIGHT}/" "$RA2_INI"
  fi

  sync_ddraw_config "$DDRAW_INI"
  sync_ddraw_config "$PREFIX_DDRAW_INI"
}

sync_ddraw_config() {
  local ddraw_file="$1"

  if [ ! -f "$ddraw_file" ]; then
    return
  fi

  sed -i "s/^width=.*/width=${OUTPUT_WIDTH}/" "$ddraw_file"
  sed -i "s/^height=.*/height=${OUTPUT_HEIGHT}/" "$ddraw_file"
  sed -i "s/^fullscreen=.*/fullscreen=true/" "$ddraw_file"
  sed -i "s/^windowed=.*/windowed=false/" "$ddraw_file"
  sed -i "s/^border=.*/border=false/" "$ddraw_file"
  sed -i "s/^renderer=.*/renderer=opengl/" "$ddraw_file"
  sed -i "s/^hook=.*/hook=4/" "$ddraw_file"
  sed -i "s/^nonexclusive=.*/nonexclusive=false/" "$ddraw_file"
  sed -i "s/^fixchilds=.*/fixchilds=0/" "$ddraw_file"
  sed -i "s/^minfps=.*/minfps=10/" "$ddraw_file"
  sed -i "s/^resolutions=.*/resolutions=2/" "$ddraw_file"
  sed -i "s/^savesettings=.*/savesettings=0/" "$ddraw_file"

  ensure_section_key "$ddraw_file" "game" "minfps" "10"
  ensure_section_key "$ddraw_file" "ra2" "resolutions" "2"
  ensure_section_key "$ddraw_file" "ra2" "minfps" "10"
  ensure_section_key "$ddraw_file" "Red Alert 2" "minfps" "10"

  delete_section_key "$ddraw_file" "game" "renderer"
  delete_section_key "$ddraw_file" "game" "hook"
  delete_section_key "$ddraw_file" "game" "fullscreen"
  delete_section_key "$ddraw_file" "game" "windowed"
  delete_section_key "$ddraw_file" "game" "nonexclusive"
  delete_section_key "$ddraw_file" "game" "fixchilds"

  delete_section_key "$ddraw_file" "ra2" "renderer"
  delete_section_key "$ddraw_file" "ra2" "hook"
  delete_section_key "$ddraw_file" "ra2" "fullscreen"
  delete_section_key "$ddraw_file" "ra2" "windowed"
  delete_section_key "$ddraw_file" "ra2" "nonexclusive"
  delete_section_key "$ddraw_file" "ra2" "fixchilds"

  delete_section_key "$ddraw_file" "Red Alert 2" "renderer"
  delete_section_key "$ddraw_file" "Red Alert 2" "hook"
  delete_section_key "$ddraw_file" "Red Alert 2" "fullscreen"
  delete_section_key "$ddraw_file" "Red Alert 2" "windowed"
  delete_section_key "$ddraw_file" "Red Alert 2" "nonexclusive"
  delete_section_key "$ddraw_file" "Red Alert 2" "fixchilds"
}

find_default_exe() {
  # 优先尝试子目录中的游戏主程序（共和国之辉通常是 glory.exe 或 ra2.exe）
  local subdirs=("" "GHra2/" "game/" "ra2/" "Red Alert 2/" "Yuri's Revenge/")
  local priority=(
    "ra2.exe"
    "Ra2.exe"
    "RA2.EXE"
    "glory.exe"
    "Glory.exe"
    "gamemd.exe"
    "Gamemd.exe"
    "yuri.exe"
    "YURI.exe"
    "game.exe"
    "Game.exe"
    "setup.exe"
    "Setup.exe"
    "SETUP.EXE"
  )

  local dir name
  for dir in "${subdirs[@]}"; do
    for name in "${priority[@]}"; do
      local path="$GAME_DIR/${dir}${name}"
      if [ -f "$path" ]; then
        printf '%s\n' "$path"
        return 0
      fi
    done
  done

  # fallback：自动搜索，但排除非游戏程序
  find "$GAME_DIR" -maxdepth 2 -type f \( -iname "*.exe" -o -iname "*.EXE" \) | grep -ivE "(PServer|trainer|RegSetup|uninst|uninstll|Mph)" | head -n 1
}

if ! command -v wine >/dev/null 2>&1; then
  echo "没有检测到 Wine。先运行：./setup_ra2_gh.sh"
  exit 1
fi

if [ ! -d "$PREFIX_DIR" ]; then
  echo "还没有初始化 Wine 前缀。先运行：./setup_ra2_gh.sh"
  exit 1
fi

mkdir -p "$GAME_DIR"

load_config
detect_display_resolution
if [ "${AUTO_DETECT,,}" = "true" ]; then
  SCREEN_WIDTH="$OUTPUT_WIDTH"
  SCREEN_HEIGHT="$OUTPUT_HEIGHT"
fi
ensure_cnc_ddraw_assets
sync_game_config

TARGET=""
if [ "${1:-}" != "" ]; then
  if [ -f "$1" ]; then
    TARGET="$(cd "$(dirname "$1")" && pwd -L)/$(basename "$1")"
  elif [ -f "$GAME_DIR/$1" ]; then
    TARGET="$GAME_DIR/$1"
  else
    echo "没找到文件：$1"
    exit 1
  fi
else
  TARGET="$(find_default_exe || true)"
fi

if [ -z "$TARGET" ]; then
  cat <<EOF
没有找到可运行的 exe 文件。

请把“共和国之辉”的安装包或完整游戏目录放到：
  $GAME_DIR

然后重新运行：
  ./run_ra2_gh.sh

或者显式指定 exe：
  ./run_ra2_gh.sh setup.exe
EOF
  exit 1
fi

TARGET_DIR="$(cd "$(dirname "$TARGET")" && pwd -L)"
TARGET_NAME="$(basename "$TARGET")"

echo "正在启动：$TARGET_NAME (游戏分辨率 ${SCREEN_WIDTH}x${SCREEN_HEIGHT}，输出分辨率 ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT})"
echo "目录：$TARGET_DIR"

cd "$TARGET_DIR"
DLL_OVERRIDES="ddraw=n,b"
if [ -n "${WINEDLLOVERRIDES:-}" ]; then
  DLL_OVERRIDES="${DLL_OVERRIDES};${WINEDLLOVERRIDES}"
fi
WINEDLLOVERRIDES="$DLL_OVERRIDES" WINEPREFIX="$PREFIX_DIR" wine "$TARGET_NAME"
