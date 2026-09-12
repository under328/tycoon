# Tycoon 大富豪

四人联机大富豪（Daifugō / President）纸牌游戏。Godot 4 原生应用：Windows + 安卓，
同一份工程导出无头专用服务器。联机核心（ENet 权威服务器 / 房间码 / 快速匹配 /
私发手牌 / 断线重连 / AI 托管 / 本机开房）已通，双进程 E2E 与单进程本机开房
E2E 实测通过；待办：VPS 部署、安卓真机回归。

## 现在就能玩

**本地模式**（人 + 3AI）：Godot 4 打开工程 F5，或 `godot --path .`

**联机模式**（无 VPS 也能玩，三种方式）：

1. **和朋友联机（主方案：Tailscale + 本机开房）**
   - 准备（一次性）：每台设备安装 [Tailscale](https://tailscale.com)（免费），
     并用**同一个账号**登录，即可组成同一虚拟局域网，各自获得 100.x.x.x 专用地址
   - 房主：联机大厅 → 「🏠 本机开房」→ 大厅显示你的 100.x.x.x → 「创建房间」拿房间码
   - 朋友：右上「服务器」填房主的 100.x.x.x → 「连接」→ 房间码「加入」
   - 内嵌权威服务器，Windows/安卓都能当主机；游戏内「? 联机帮助」有四页图文说明

2. **专用服务器（PC）**：

```bash
# 终端 1：启动无头服务器（默认端口 24565，UDP；24565+1 为 HTTP 健康检查）
godot --headless --path . --server --port 24565

# 终端 2：客户端进大厅（可开多个实例互相对战）
godot --path . --client
```

3. **连远程服务器**：大厅右上「服务器」填服务器地址/端口（持久化保存）。
   官方 VPS 部署上线后，把 `src/autoload/settings.gd` 的 `DEFAULT_HOST`
   改为正式域名即可全端默认直连。

大厅里：创建房间（得到 6 位房间码）→ 房主调规则设置 → 空位加AI → 开始游戏；
朋友输入房间码加入。对局中可以发表情、掉线自动凭 session_token 重连回座
（离线期间 AI 托管）；打完自动回房间，房主可再来一局；服务器按游客 ID 记录
场数/胜场/累计积分（`user://stats.json`）。规则细节见 [docs/规则规格.md](docs/规则规格.md)。

## 构建发布

### Windows

```bash
godot --headless --path . --export-release "Windows Desktop" builds/Tycoon.exe
```

产物 `builds/Tycoon.exe`（内嵌全部资源）可直接双击进本地模式；也可当无头服务器：
`Tycoon.exe --headless --server --port 24565`。
发布产物已验证：用导出的 exe 当服务器完整跑通 E2E（含断线重连）。

### Android（debug APK，arm64）

本机工具链已装在 `D:\AndroidDev`（JDK 17 + Android SDK 34，绿色解压），
Godot 编辑器设置已指向上述路径，一键导出：

```bash
godot --headless --path . --export-debug "Android" builds/Tycoon.apk
```

真机安装（任选其一）：
- 手机传 `Tycoon.apk` 直接安装（需允许"安装未知应用"）；
- 或 USB 连接后 `D:\AndroidDev\sdk\platform-tools\adb.exe install -r builds/Tycoon.apk`。

要求：arm64 安卓（2016 年后几乎所有机型）。正式发布需换 release keystore
（`deploy/README.md` 待补章节）。

## 压测

```bash
# 起服务器后，开 N 个机器人持续打满指定秒数：
godot --headless --path . --server --port 24575 &
STRESS_SEC=150 godot --headless --path . --script tests/stress_bot.gd   # 每个进程一个机器人
```

已验证：6 机器人并发 150 秒完成 65 场完整对局，服务器零脚本错误，
压测后 E2E 全流程依旧通过。

## 运行测试

```bash
# 单元测试（零依赖，107,968 断言）
godot --headless --path . --script tests/run_tests.gd

# 双进程 E2E（连上→同步→中途断网→重连→打完）
godot --headless --path . --server --port 24575 --ai-delay 60 --phase-delay 250 &
sleep 3
godot --headless --path . --script tests/e2e_client.gd
```

## 目录

```
src/rules/     规则引擎（纯逻辑，客户端/服务器共用）
src/rules/ai/  AI 托管（本地模式与服务器托管同一实现）
src/protocol/  消息常量 / 按座位裁剪的可见信息 / 统一网络节点（两端共用）
src/server/    房间/对局控制（纯逻辑，可无网络单测）
src/client/    大厅、牌桌、入口
src/client/ui/ 程序化卡牌控件（card_view，无纹理依赖）
src/client/audio/ 程序化音频合成（synth）
src/autoload/  模式/设置/音频
tests/         零依赖测试框架 + 套件 + E2E 客户端
deploy/        VPS 部署（Docker）
docs/          规则规格 / 网络协议 / 开发计划
```

## 里程碑

M0 地基 ✅ · M1 可玩核心 ✅ · M2 联机核心 ✅（VPS 部署/安卓真机待外部资源）· M3 完整体验 ✅ · M4 视听核心 ✅（正式美术/音乐素材待替换）· M5 发布

路线图与验收标准见 [docs/开发计划.md](docs/开发计划.md)。
