# 版本更新分发文件夹

把新版安装包放到本文件夹(与服务器可执行文件同级的 download/ 目录):

- `Tycoon.apk` — Android 客户端
- `Tycoon.exe` — Windows 客户端

客户端联机时收到"发现新版本"提示后, 点按钮会自动打开
`http://主机IP:端口+1/download` 从这里下载(走 Tailscale/局域网, 国内直接可达)。
