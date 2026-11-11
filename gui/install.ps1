# install.ps1 —— 安装 / 卸载桌面程序（开始菜单快捷方式 + 开机自启）

[CmdletBinding()]
param(
    [ValidateSet('install', 'uninstall', 'status')]
    [string]$Action = 'install',

    [switch]$AutoStart
)

$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $root 'BackupLog.exe'
$gui = Join-Path $PSScriptRoot 'BackupLog.Gui.ps1'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) '备份日志自动化.lnk'
$desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) '备份日志自动化.lnk'

function New-Shortcut {
    param([string]$Path)
    # 一律用签名的 powershell.exe 启动脚本，避开 SmartScreen 对未签名 exe 的拦截
    $shell = New-Object -ComObject WScript.Shell
    $sc = $shell.CreateShortcut($Path)
    $sc.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $sc.Arguments = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $gui
    $sc.WorkingDirectory = $root
    $ico = Join-Path $PSScriptRoot 'app.ico'
    if (Test-Path -LiteralPath $ico) { $sc.IconLocation = $ico }
    $sc.Description = '备份日志自动化'
    $sc.Save()
}

switch ($Action) {

    'status' {
        Write-Host ('程序：{0}' -f $(if (Test-Path -LiteralPath $exe) { $exe } else { '未编译（仍可用脚本运行）' }))
        Write-Host ('开始菜单快捷方式：{0}' -f $(if (Test-Path -LiteralPath $startMenu) { '已创建' } else { '未创建' }))
        $v = Get-ItemProperty $runKey -Name 'BackupLogAuto' -ErrorAction SilentlyContinue
        Write-Host ('开机自启：{0}' -f $(if ($v) { '已启用' } else { '未启用' }))
    }

    'install' {
        New-Shortcut -Path $startMenu
        New-Shortcut -Path $desktop
        Write-Host ('已创建快捷方式：{0}' -f $startMenu)

        if ($AutoStart) {
            $cmd = if (Test-Path -LiteralPath $exe) { '"{0}"' -f $exe }
            else { 'powershell.exe -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $gui }
            Set-ItemProperty -Path $runKey -Name 'BackupLogAuto' -Value $cmd
            Write-Host '已设置开机自启。'
        }
    }

    'uninstall' {
        foreach ($p in @($startMenu, $desktop)) {
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; Write-Host ('已删除：{0}' -f $p) }
        }
        Remove-ItemProperty -Path $runKey -Name 'BackupLogAuto' -ErrorAction SilentlyContinue
        Write-Host '已移除开机自启。程序文件未删除。'
    }
}
