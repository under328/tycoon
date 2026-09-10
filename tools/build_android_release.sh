#!/usr/bin/env bash
# 安卓正式包构建（release 签名）。
# 依赖: D:\AndroidDev\keystore\{release.keystore, RELEASE_PASSWORD.txt}（仓库外）
set -e
PW=$(grep "storepass=" /d/AndroidDev/keystore/RELEASE_PASSWORD.txt | cut -d= -f2)
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="D:\AndroidDev\keystore\release.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="tycoon"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$PW"
GODOT="/d/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"$GODOT" --headless --path . --export-release "Android Release" builds/Tycoon-release.apk
echo "产物: builds/Tycoon-release.apk"
