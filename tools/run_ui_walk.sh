#!/usr/bin/env bash
# 一键 UI 遍历测试: 运行 walker 并生成报告(含脚本错误关联)
# 用法: bash tools/run_ui_walk.sh
GODOT="${GODOT:-/c/Users/Administrator/godot/bin/Godot_v4.7.2-stable_win64_console.exe}"
cd "$(dirname "$0")/.." || exit 1
"$GODOT" --headless --path . --script tests/ui_walk_test.gd > /tmp/ui_walk_full.log 2>&1
code=$?
{
  echo "=== UI 遍历报告 ==="
  echo "--- 概要 ---"
  grep -E "SUMMARY|报告已写入" /tmp/ui_walk_full.log
  echo "--- 发现问题(SKIP 之外的 ERR) ---"
  grep -E "walk\] !!" /tmp/ui_walk_full.log | grep -v "SKIP" || echo "(无)"
  echo "--- 脚本错误数 ---"
  grep -cE "SCRIPT ERROR" /tmp/ui_walk_full.log
} > builds/ui_walk_report.txt
cat builds/ui_walk_report.txt
exit $code
