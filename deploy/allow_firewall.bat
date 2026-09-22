@echo off
rem 大富豪联机防火墙放行脚本(右键"以管理员身份运行")
rem 本机开房后, 若同一 WiFi 的手机搜不到房间 / 直连 IP 超时,
rem 绝大多数是 Windows 防火墙拦截入站。本脚本按端口放行:
rem   24565 游戏UDP / 24566 健康检查TCP / 24567 局域网发现UDP
netsh advfirewall firewall delete rule name="Tycoon-Daifugo-Online" >nul 2>&1
netsh advfirewall firewall delete rule name="Tycoon-Daifugo-Online-TCP" >nul 2>&1
netsh advfirewall firewall add rule name="Tycoon-Daifugo-Online" dir=in action=allow protocol=UDP localport=24565-24567 profile=any
netsh advfirewall firewall add rule name="Tycoon-Daifugo-Online-TCP" dir=in action=allow protocol=TCP localport=24565-24567 profile=any
echo.
echo 完成。若上面出现"确定"字样即放行成功; 若提示"需要管理员"请右键本文件选择"以管理员身份运行"。
pause
