@echo off
chcp 65001 >nul
sing-box.exe rule-set compile proxy.json
sing-box.exe rule-set compile direct.json
sing-box.exe rule-set compile pass-ip.json
sing-box.exe rule-set compile direct-ip.json
sing-box.exe rule-set compile pikpak-download.json

echo 所有JSON文件转换完成
pause