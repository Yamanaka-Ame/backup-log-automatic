# Install-Schedule.ps1
# 把「扫描备份盘并写日志」注册成 Windows 计划任务，实现真正的自动运行。

[CmdletBinding()]
param(
    [ValidateSet('install', 'uninstall', 'status')]
    [string]$Action = 'install',

    [int]$IntervalMinutes = 15
)

$ErrorActionPreference = 'Stop'

$taskName = 'BackupLogAutoScan'
$cli = Join-Path (Split-Path $PSScriptRoot -Parent) 'backup-log.ps1'

switch ($Action) {
    'status' {
        $t = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($null -eq $t) {
            Write-Host '未安装计划任务。'
        }
        else {
            $info = Get-ScheduledTaskInfo -TaskName $taskName
            Write-Host ('任务：{0}  状态：{1}' -f $taskName, $t.State)
            Write-Host ('上次运行：{0}  结果：{1}' -f $info.LastRunTime, $info.LastTaskResult)
            Write-Host ('下次运行：{0}' -f $info.NextRunTime)
        }
    }

    'uninstall' {
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-Host ('已移除计划任务：{0}' -f $taskName)
        }
        else {
            Write-Host '没有需要移除的任务。'
        }
    }

    'install' {
        if (-not (Test-Path -LiteralPath $cli)) { throw "找不到 $cli" }

        $taskRun = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File {0} -Action scan' -f $cli
        & schtasks.exe /Create /TN $taskName /TR $taskRun /SC MINUTE /MO $IntervalMinutes /F | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "schtasks 创建失败（退出码 $LASTEXITCODE）" }

        Write-Host ('已注册计划任务：{0}，每 {1} 分钟运行一次（登录状态下运行）。' -f $taskName, $IntervalMinutes)
        $next = (Get-ScheduledTaskInfo -TaskName $taskName).NextRunTime
        Write-Host ('下次运行时间：{0}' -f $next)
        Write-Host '提示：可先用 backup-log.ps1 -Action scan 手动跑一次建立基线。'
    }
}
