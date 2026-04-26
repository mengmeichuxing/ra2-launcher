#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_DIR="$SCRIPT_DIR/game"
PREFIX_DIR="$HOME/.wine-ra2-gh"

echo "== 红色警戒2 共和国之辉 Ubuntu 启动器 =="
echo

if ! command -v wine >/dev/null 2>&1; then
  echo "没有检测到 Wine，接下来会安装 wine 和 winetricks。"
  echo "这一步需要输入你的 sudo 密码。"
  sudo apt update
  sudo apt install -y wine winetricks
fi

mkdir -p "$GAME_DIR"

if [ ! -d "$PREFIX_DIR" ]; then
  echo
  echo "正在创建 32 位 Wine 环境：$PREFIX_DIR"
  WINEARCH=win32 WINEPREFIX="$PREFIX_DIR" wineboot -i
fi

if command -v winetricks >/dev/null 2>&1 && [ ! -f "$PREFIX_DIR/drive_c/windows/system32/ddraw.dll" ]; then
  echo
  echo "正在安装 cnc-ddraw 兼容层（修复全屏黑边/小画面问题）..."
  WINEPREFIX="$PREFIX_DIR" winetricks -q cnc_ddraw
fi

cat <<EOF

准备完成。

下一步：
1. 把“共和国之辉”的安装包或完整游戏目录放进：
   $GAME_DIR
2. 如果你放的是安装包，运行：
   ./run_ra2_gh.sh setup.exe
3. 如果你放的是已经解压好的游戏目录，直接运行：
   ./run_ra2_gh.sh

提示：
- 首次运行 Wine 可能会弹出一些初始化窗口，正常点确认即可。
- 如果你已经有单独的启动文件，也可以：
  ./run_ra2_gh.sh 你的启动文件.exe
EOF
