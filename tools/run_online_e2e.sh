#!/usr/bin/env bash
# 联机三模式一键回归: 纯逻辑套件 + 真实 socket E2E 全家桶。
# 用法: bash tools/run_online_e2e.sh
# 覆盖:
#   1. tests/run_tests.gd            全部单元/逻辑套件(含 online_modes_test)
#   2. e2e_online_all                单进程内嵌服 + 3 客户端, 三模式综合
#   3. e2e_embedded_host             本机开房(局域网发现 + 完整对局)
#   4. 独立服务器 + e2e_client       断线 → token 重连 → 打完
#   5. e2e_fight_pvp2 (双实例并行)   双真人格斗完整一场
#   6. e2e_rogue_pvp2 (双实例并行)   双真人肉鸽完整一场
set -u
GODOT="${GODOT:-/c/Users/Administrator/godot/bin/Godot_v4.7.2-stable_win64_console.exe}"
cd "$(dirname "$0")/.." || exit 1
USER_DIR="$APPDATA/Godot/app_userdata/Tycoon 大富豪"
FAILS=()

note() { echo "=== $1 ==="; }

note "1/7 单元 + 纯逻辑套件"
"$GODOT" --headless --path . --script tests/run_tests.gd > /tmp/oe_unit.log 2>&1
[ $? -eq 0 ] || FAILS+=("unit suites")

note "2/7 三模式综合 E2E(单进程三客户端)"
timeout 330 "$GODOT" --headless --path . --script tests/e2e_online_all.gd > /tmp/oe_all.log 2>&1
[ $? -eq 0 ] || FAILS+=("e2e_online_all")

note "3/7 重连按钮 E2E"
timeout 200 "$GODOT" --headless --path . --script tests/e2e_reconnect.gd > /tmp/oe_rc.log 2>&1
[ $? -eq 0 ] || FAILS+=("e2e_reconnect")

note "4/7 本机开房 E2E"
timeout 120 "$GODOT" --headless --path . --script tests/e2e_embedded_host.gd > /tmp/oe_host.log 2>&1
[ $? -eq 0 ] || FAILS+=("e2e_embedded_host")

note "5/7 独立服务器 + 断线重连 E2E"
"$GODOT" --headless --path . --server --port 24575 --ai-delay 60 --phase-delay 250 \
        > /tmp/oe_server.log 2>&1 &
SERVER_PID=$!
sleep 12
timeout 240 "$GODOT" --headless --path . --script tests/e2e_client.gd > /tmp/oe_client.log 2>&1
[ $? -eq 0 ] || FAILS+=("e2e_client")
kill $SERVER_PID 2>/dev/null
sleep 1

note "6/7 双真人格斗 PvP(双实例)"
rm -f "$USER_DIR/fight2_code.txt"
"$GODOT" --headless --path . --script tests/e2e_fight_pvp2.gd -- host > /tmp/oe_fp2h.log 2>&1 &
H1=$!
sleep 2
"$GODOT" --headless --path . --script tests/e2e_fight_pvp2.gd -- join > /tmp/oe_fp2j.log 2>&1 &
J1=$!
sleep 150
kill $H1 $J1 2>/dev/null
grep -q "FIGHT2_OK" /tmp/oe_fp2h.log && grep -q "FIGHT2_OK" /tmp/oe_fp2j.log \
        || FAILS+=("e2e_fight_pvp2")

note "7/7 双真人肉鸽 PvP(双实例)"
rm -f "$USER_DIR/rogue2_code.txt"
"$GODOT" --headless --path . --script tests/e2e_rogue_pvp2.gd -- host > /tmp/oe_rp2h.log 2>&1 &
H2=$!
sleep 2
"$GODOT" --headless --path . --script tests/e2e_rogue_pvp2.gd -- join > /tmp/oe_rp2j.log 2>&1 &
J2=$!
sleep 170
kill $H2 $J2 2>/dev/null
grep -q "ROGUE2_OK" /tmp/oe_rp2h.log && grep -q "ROGUE2_OK" /tmp/oe_rp2j.log \
        || FAILS+=("e2e_rogue_pvp2")

echo "======================================="
if [ ${#FAILS[@]} -eq 0 ]; then
    echo "ONLINE E2E ALL GREEN"
    exit 0
fi
echo "FAILED: ${FAILS[*]}"
exit 1
