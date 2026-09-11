# 服务器部署（M2）

## 1. 导出 Linux 无头服务器

1. Godot 编辑器 → 项目 → 导出 → 添加预设 **Linux Server**（需先下载对应的
   Export Templates，注意与编辑器版本一致）。
2. 产物命名 `tycoon_server.x86_64`，放到本 `deploy/` 目录。
3. 本机可以先验证：`./tycoon_server.x86_64 --server --port 24565`，
   看到 `[server] Tycoon 服务器已启动` 即正常。

## 2. VPS 上线

```bash
# 把 deploy/ 目录传到服务器后：
docker compose up -d --build
docker logs -f tycoon-server        # 查看日志
```

- 开放端口：UDP `24565`（对局）+ TCP `24566`（健康检查）。
- 更新版本：重新导出产物 → `docker compose up -d --build`。
- 客户端版本握手不匹配会被拒绝（`s_kicked/version`），客户端提示更新。

## 3. 安卓正式包（release 签名）

一次性准备：生成 release keystore（**已生成在 `D:\AndroidDev\keystore\`，
密码在同名 `RELEASE_PASSWORD.txt`，务必异地备份——丢了就无法更新应用**）。

日常构建（密码经环境变量注入，不落 git）：

```bash
bash tools/build_android_release.sh     # 产物 builds/Tycoon-release.apk
```

校验签名：`apksigner verify --print-certs builds/Tycoon-release.apk`
（build-tools 目录内有 apksigner）。

## 4. 下载页

`deploy/page/index.html` 单文件静态页（含玩法说明）。
上线：把该文件与 `Tycoon.exe`、`Tycoon-release.apk` 放到任意静态托管同目录即可。

## 5. 运维

| 事项 | 做法 |
|---|---|
| 健康检查 | `curl http://<ip>:24566/` → `{"status":"ok",...}`（UptimeRobot HTTP 探活可用） |
| 状态日志 | 服务器每 60s 打印 `rooms/players/uptime` |
| 对局状态 | 全内存态，重启即清空（房间作废，客户端提示重连） |
| 战绩持久化 | ✅ 已实现（`user://stats.json`，按客户端 ID 记录场数/胜场/积分） |
| 压测 | `--soak N` 全机器人房间模式：`godot --headless --path . --server --port 24565 --soak 20`
  （20 房 80 机器人座位，对局结束无缝续局）。健康端点含 `mem_mb/soak_matches`，日志每 60s 输出。
  实测 20 房 15 分钟内存平稳 ~29MB；8h 验收同命令后台跑一晚即可。
  客户端机器人压测（模拟真人连入）：`tests/stress_bot.gd` |

## 6. 客户端连接

- 大厅地址填 `服务器IP`，端口 `24565`。
- 公网部署建议后续加域名 + DTLS（ENet 支持 DTLS peer，v1 暂用明文 UDP）。
