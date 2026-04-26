#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -L)"
cd "$SCRIPT_DIR"

# 直接启动游戏本体，避免先弹出 XCC 的整合包启动器。
./run_ra2_gh.sh GHra2/ra2.exe
