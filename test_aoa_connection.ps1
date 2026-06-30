# 简易 AOA 连接测试脚本
# 帮助用户诊断 Windows 上的 USB AOA 连接问题

Write-Host "=== NexusPad USB AOA 连接测试 ===" -ForegroundColor Cyan
Write-Host "此脚本帮助诊断 USB AOA 连接问题`n" -ForegroundColor Cyan

# 检查 libusb 是否可用
Write-Host "1. 检查 libusb..." -ForegroundColor Yellow
try {
    Add-Type -Path (Join-Path $PSScriptRoot "src-tauri\target\debug\nexuspad.dll") -ErrorAction SilentlyContinue
    Write-Host "   ✓ libusb 可用" -ForegroundColor Green
} catch {
    Write-Host "   ✗ libusb 不可用或未编译" -ForegroundColor Red
    Write-Host "   请先编译项目: cd src-tauri && cargo build" -ForegroundColor Yellow
    exit 1
}

# 列出 USB 设备
Write-Host "`n2. 扫描 USB 设备..." -ForegroundColor Yellow

$devicePatterns = @{
    "18D1:2D00" = "AOA 设备 (无 ADB)"
    "18D1:2D01" = "AOA 设备 (有 ADB)"
    "22D9:2765" = "OnePlus/OPPO 设备"
}

$foundDevices = @()

# 使用系统信息命令获取 USB 设备
Write-Host "   使用 Get-PnpDevice 扫描..." -ForegroundColor Gray
$usbDevices = Get-PnpDevice -Class USB -Status OK -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'VID_' }

foreach ($device in $usbDevices) {
    foreach ($pattern in $devicePatterns.Keys) {
        if ($device.InstanceId -match $pattern.Replace(":", "&PID_")) {
            $deviceInfo = @{
                InstanceId = $device.InstanceId
                FriendlyName = $device.FriendlyName
                Type = $devicePatterns[$pattern]
                Status = $device.Status
            }
            $foundDevices += $deviceInfo
            Write-Host "   - 发现 $($devicePatterns[$pattern]): $($device.FriendlyName)" -ForegroundColor Green
        }
    }
}

if ($foundDevices.Count -eq 0) {
    Write-Host "   ✗ 未发现已知的 Android/AOA 设备" -ForegroundColor Red
    Write-Host "`n建议:" -ForegroundColor Yellow
    Write-Host "1. 确保手机已通过 USB 连接" -ForegroundColor White
    Write-Host "2. 在手机上切换 USB 模式（尝试不同模式）" -ForegroundColor White
    Write-Host "3. 确保已开启 USB 调试" -ForegroundColor White
} else {
    Write-Host "`n3. 发现设备详情:" -ForegroundColor Yellow
    foreach ($dev in $foundDevices) {
        Write-Host "   - 设备: $($dev.FriendlyName)" -ForegroundColor Cyan
        Write-Host "     ID: $($dev.InstanceId)" -ForegroundColor Gray
        Write-Host "     类型: $($dev.Type)" -ForegroundColor Gray
        Write-Host "     状态: $($dev.Status)" -ForegroundColor Gray
        
        # 检查是否需要 WinUSB 驱动
        if ($dev.InstanceId -match "18D1&PID_2D") {
            Write-Host "     ⚠ 可能需要 WinUSB 驱动" -ForegroundColor Yellow
        }
    }
}

# 提供解决方案
Write-Host "`n4. 解决方案:" -ForegroundColor Cyan

Write-Host "A. 如果设备是 18D1:2D01 (AOA模式) 但无法连接:" -ForegroundColor Yellow
Write-Host "   1. 下载 Zadig: https://zadig.akeo.ie/" -ForegroundColor White
Write-Host "   2. 运行 Zadig → Options → List All Devices" -ForegroundColor White
Write-Host "   3. 找到 Android 或 NexusPad 设备" -ForegroundColor White
Write-Host "   4. 选择 WinUSB (libusb-win32) 驱动" -ForegroundColor White
Write-Host "   5. 点击 Replace Driver" -ForegroundColor White
Write-Host "   6. 完成后可能需要拔插 USB 线`n" -ForegroundColor White

Write-Host "B. 如果设备是 22D9:2765 (Android模式) 但权限不足:" -ForegroundColor Yellow
Write-Host "   1. 在手机上切换 USB 模式：" -ForegroundColor White
Write-Host "      - '仅充电' (推荐先试)" -ForegroundColor White
Write-Host "      - '文件传输'" -ForegroundColor White
Write-Host "      - 'Android Auto'" -ForegroundColor White
Write-Host "   2. 切换后重试连接`n" -ForegroundColor White

Write-Host "C. 通用调试步骤:" -ForegroundColor Yellow
Write-Host "   1. 在 NexusPad 桌面端:" -ForegroundColor White
Write-Host "      - 打开设置 → 通用 → USB 连接" -ForegroundColor White
Write-Host "      - 点击 '驱动检测' 按钮" -ForegroundColor White
Write-Host "      - 点击 '详细调试' 按钮生成日志" -ForegroundColor White
Write-Host "   2. 在手机上:" -ForegroundColor White
Write-Host "      - 确保 NexusPad app 已启动" -ForegroundColor White
Write-Host "      - 选择 USB 连接方式" -ForegroundColor White
Write-Host "      - 点击 START" -ForegroundColor White

Write-Host "`n5. 关键提示:" -ForegroundColor Magenta
Write-Host "   - 不同手机/系统可能需要不同的 USB 模式" -ForegroundColor White
Write-Host "   - 建议逐个尝试所有可用的 USB 模式" -ForegroundColor White
Write-Host "   - '仅充电' 模式通常最容易成功" -ForegroundColor White
Write-Host "   - 某些手机需要在开发者选项中开启 'USB 调试 (安全设置)'" -ForegroundColor White

Write-Host "`n测试完成。请根据上述建议操作。" -ForegroundColor Cyan