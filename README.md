# Tycoon 大富豪

四人联机大富豪（Daifugō / President）纸牌游戏。Godot 4 原生应用：Windows + 安卓，
同一份工程导出无头专用服务器。当前处于 **M1（可玩核心）** 阶段：本地人机对战已可玩，
联机（M2）开发中。

## 现在就能玩（本地模式）

用 Godot 4.x 打开本工程直接 F5 运行；或命令行：

```
godot --path . 
```

你执座位 0，其余三家为 AI。规则含革命/階段/Joker 变体，3 局制计分，
规则细节见 [docs/规则规格.md](docs/规则规格.md)。

## 运行测试

零依赖，任何 Godot 4 binary 均可：

```
godot --headless --path . --script tests/run_tests.gd
```

覆盖：牌编码 / 牌型识别（革命·階段·王补位）/ 对局状态机 / AI 自打 200 场 fuzz。

## 目录

```
src/rules/     规则引擎（纯逻辑，客户端/服务器共用）
src/rules/ai/  AI 托管（本地模式与服务器托管同一实现）
src/protocol/  消息常量与按座位裁剪的可见信息
src/server/    房间/对局控制（M2 实现）
src/client/    牌桌 UI、入口
tests/         零依赖测试框架 + 套件
docs/          规则规格 / 网络协议 / 开发计划 / 美术风格指南
deploy/        服务器部署（M2）
```

## 里程碑

M0 地基 ✅ · M1 可玩核心 ✅ · M2 联机对战 · M3 完整体验 · M4 视听整合 · M5 发布

路线图与验收标准见 [docs/开发计划.md](docs/开发计划.md)。
