# Install-Schedule.ps1
# 把「扫描备份盘并写日志」注册成 Windows 计划任务，实现真正的自动运行。
# 任务用 wscript.exe 启动 tools\RunScan.vbs，由它隐藏拉起 PowerShell —— 不会闪黑框。

[CmdletBinding()]
param(
    [ValidateSet('install', 'uninstall', 'status', 'enable', 'disable')]
    [string]$Action = 'install',

    [int]$IntervalMinutes = 15
)

$ErrorActionPreference = 'Stop'

$taskName = 'BackupLogAutoScan'
$root = Split-Path $PSScriptRoot -Parent
$cli = Join-Path $root 'backup-log.ps1'
$vbs = Join-Path $PSScriptRoot 'RunScan.vbs'
$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'

function Get-TaskState {
    # 用 XML 读，避开中英文系统的本地化差异
    $xml = & schtasks.exe /Query /TN $taskName /XML 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $xml) { return $null }
    $text = ($xml -join "`r`n")
    $enabled = -not ($text -match '<Enabled>\s*false\s*</Enabled>')
    return [pscustomobject]@{ Exists = $true; Enabled = $enabled; Xml = $text }
}

switch ($Action) {

    'status' {
        $st = Get-TaskState
        if (-not $st) {
            Write-Host '未安装计划任务。'
            return
        }
        Write-Host ('任务：{0}' -f $taskName)
        Write-Host ('状态：{0}' -f $(if ($st.Enabled) { '已启用' } else { '已停用' }))
        $info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
        if ($info) {
            Write-Host ('上次运行：{0}  上次结果：{1}' -f $info.LastRunTime, $info.LastTaskResult)
            Write-Host ('下次运行：{0}' -f $info.NextRunTime)
        }
    }

    'enable' {
        & schtasks.exe /Change /TN $taskName /ENABLE | Out-Null
        if ($LASTEXITCODE -ne 0) { throw '启用失败（任务可能不存在）' }
        Write-Host '已启用自动扫描。'
    }

    'disable' {
        & schtasks.exe /Change /TN $taskName /DISABLE | Out-Null
        if ($LASTEXITCODE -ne 0) { throw '停用失败（任务可能不存在）' }
        Write-Host '已停用自动扫描。'
    }

    'uninstall' {
        & schtasks.exe /Delete /TN $taskName /F 2>$null | Out-Null
        Write-Host ('已移除计划任务：{0}' -f $taskName)
    }

    'install' {
        if (-not (Test-Path -LiteralPath $cli)) { throw "找不到 $cli" }
        if (-not (Test-Path -LiteralPath $vbs)) { throw "找不到 $vbs" }
        if (-not (Test-Path -LiteralPath $wscript)) { throw "找不到 wscript.exe" }

        # 命令：wscript.exe //B "<项目>\tools\RunScan.vbs"
        $taskRun = '"{0}" //B "{1}"' -f $wscript, $vbs

        & schtasks.exe /Create /TN $taskName /TR $taskRun /SC MINUTE /MO $IntervalMinutes /F | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "schtasks 创建失败（退出码 $LASTEXITCODE）" }

        Write-Host ('已注册计划任务：{0}，每 {1} 分钟静默运行一次。' -f $taskName, $IntervalMinutes)
        $info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
        if ($info) { Write-Host ('下次运行时间：{0}' -f $info.NextRunTime) }
        Write-Host '提示：可先用 backup-log.ps1 -Action scan 手动跑一次建立基线。'
    }
}
