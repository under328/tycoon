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

- 只开放 UDP 端口 `24565`（防火墙/安全组放行）。
- 更新版本：重新导出产物 → `docker compose up -d --build`。
- 客户端版本握手不匹配会被拒绝（`s_kicked/version`），客户端提示更新。

## 3. 运维

| 事项 | 做法 |
|---|---|
| 健康检查 | `show udp` 无 HTTP 端点；用日志 + `docker ps` / UptimeRobot ping 主域兜底 |
| 对局状态 | 全内存态，重启即清空（房间作废，客户端提示重连） |
| 战绩持久化 | M3 接入（JSON 落盘 `user://`） |
| 压测 | M5：机器人脚本挂 20 房 80 人 |

## 4. 客户端连接

- 大厅地址填 `服务器IP`，端口 `24565`。
- 公网部署建议后续加域名 + DTLS（ENet 支持 DTLS peer，v1 暂用明文 UDP）。
