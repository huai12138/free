@echo off
chcp 65001 >nul
echo 开始执行所有转换操作...

echo.
echo === 执行JSON到SRS格式转换 ===
sing-box.exe rule-set compile proxy.json
sing-box.exe rule-set compile direct.json
sing-box.exe rule-set compile pass-ip.json
sing-box.exe rule-set compile direct-ip.json
sing-box.exe rule-set compile pikpak-download.json
echo JSON文件转换完成

echo.
echo === 执行YAML到MRS格式转换 ===
mihomo convert-ruleset "domain" yaml "proxy.yaml" "proxy.mrs"
mihomo convert-ruleset "domain" yaml "direct.yaml" "direct.mrs"
mihomo convert-ruleset "ipcidr" yaml "direct-ip.yaml" "direct-ip.mrs"
echo YAML文件转换完成

echo.
echo 所有转换操作已完成！
pause