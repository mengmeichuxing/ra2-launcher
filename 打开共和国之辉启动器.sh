#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -L)"
cd "$SCRIPT_DIR"

# 这是整合包自带的 XCC 启动器，会先弹出 Mod Launcher 窗口。
./run_ra2_gh.sh GHra2/glory.exe
