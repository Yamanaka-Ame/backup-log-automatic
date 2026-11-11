# backup-log.ps1
# 备份盘动向追踪：自动识别备份盘，把新增 / 修改 / 删除 / 改名 / 移动 / 归档
# 按既有格式追加到 Backup_Log.log。

[CmdletBinding()]
param(
    [ValidateSet('detect', 'init', 'scan', 'status', 'watch', 'pause', 'resume', 'unlock')]
    [string]$Action = 'scan',

    [string]$Root,

    [string]$Config = '',

    [switch]$DryRun,
    [switch]$Force,

    [int]$Interval = 300,

    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrEmpty($Config)) { $Config = Join-Path $PSScriptRoot 'config.json' }

try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

. (Join-Path $PSScriptRoot 'lib\BackupLog.Core.ps1')

function Write-Info {
    param([string]$Text)
    if (-not $Quiet) { Write-Host $Text }
}

function Show-Detect {
    $cfg = Read-BackupLogConfig -Path $Config
    $target = Resolve-BackupRoot -Config $cfg -Root $Root
    Write-Info ('备份盘：{0}' -f $target.Drive)
    Write-Info ('根目录：{0}' -f $target.Root)
    Write-Info ('日志文件：{0}' -f (Get-LogPath -Config $cfg -Root $target.Root))
    Write-Info ('状态目录：{0}' -f (Get-StateDirectory -Config $cfg -Root $target.Root))
    $state = Read-BackupState -Config $cfg -Root $target.Root
    if ($null -eq $state) {
        Write-Info '状态：尚未建立基线（首次扫描会静默建立，不写日志）'
    }
    else {
        Write-Info ('状态：已建立，基线 {0} 个条目，采集于 {1}' -f $state.Entries.Count, $state.CapturedAt)
    }
}

function Show-Status {
    $cfg = Read-BackupLogConfig -Path $Config
    $target = Resolve-BackupRoot -Config $cfg -Root $Root
    $state = Read-BackupState -Config $cfg -Root $target.Root

    Write-Info ('备份盘：{0}  {1}' -f $target.Drive, $target.Root)
    if ($null -eq $state) {
        Write-Info '尚未建立基线。'
        return
    }
    $byDir = @{}
    foreach ($k in $state.Entries.Keys) {
        $top = $k
        $i = $k.IndexOf('\')
        if ($i -ge 0) { $top = $k.Substring(0, $i) }
        if (-not $byDir.ContainsKey($top)) { $byDir[$top] = 0 }
        $byDir[$top] = $byDir[$top] + 1
    }
    Write-Info ('基线时间：{0}' -f $state.CapturedAt)
    Write-Info ('条目总数：{0}' -f $state.Entries.Count)
    foreach ($k in ($byDir.Keys | Sort-Object)) {
        Write-Info ('  {0,-28} {1}' -f $k, $byDir[$k])
    }
}

function Show-ScanResult {
    param($Result)

    if ($Result.Mode -eq 'baseline') {
        Write-Info $Result.Message
        return
    }

    if ($Result.Mode -eq 'paused') {
        Write-Info $Result.Message
        return
    }

    if ($Result.ChangeCount -eq 0) {
        Write-Info $Result.Message
        return
    }

    Write-Info ('检测到变化：新建目录 {0}，新增文件 {1}，删除目录 {2}，删除文件 {3}，修改 {4}，目录改名 {5}，文件移动 {6}，归档 {7}' -f `
            $Result.AddedDirs, $Result.AddedFiles, $Result.RemovedDirs, $Result.RemovedFiles,
        $Result.UpdatedFiles, $Result.FolderMoves, $Result.FileMoves, $Result.Archives)

    foreach ($line in $Result.Lines) { Write-Info ('  ' + $line) }
    Write-Info $Result.Message
}

try {
    switch ($Action) {
        'detect' { Show-Detect }
        'status' { Show-Status }
        'init' {
            $r = Invoke-BackupLogScan -Root $Root -ConfigPath $Config -Reinit
            Write-Info $r.Message
        }
        'scan' {
            $r = Invoke-BackupLogScan -Root $Root -ConfigPath $Config -DryRun:$DryRun -Force:$Force
            Show-ScanResult -Result $r
        }
        'pause' {
            $cfg = Read-BackupLogConfig -Path $Config
            $target = Resolve-BackupRoot -Config $cfg -Root $Root
            $flag = Set-PauseFlag -Config $cfg -Root $target.Root -Paused $true
            Write-Info ('已暂停自动扫描：' + $flag)
        }
        'resume' {
            $cfg = Read-BackupLogConfig -Path $Config
            $target = Resolve-BackupRoot -Config $cfg -Root $Root
            $null = Set-PauseFlag -Config $cfg -Root $target.Root -Paused $false
            Write-Info '已恢复自动扫描。'
        }
        'unlock' {
            $cfg = Read-BackupLogConfig -Path $Config
            $target = Resolve-BackupRoot -Config $cfg -Root $Root
            $lock = Join-Path (Get-StateDirectory -Config $cfg -Root $target.Root) 'scan.lock'
            if (Test-Path -LiteralPath $lock) { Remove-Item -LiteralPath $lock -Force; Write-Info ('已删除锁文件：' + $lock) }
            else { Write-Info '没有锁文件，扫描并未被占用。' }
        }
        'watch' {
            Write-Info ('进入监视模式，每 {0} 秒扫描一次。按 Ctrl+C 结束。' -f $Interval)
            while ($true) {
                try {
                    $r = Invoke-BackupLogScan -Root $Root -ConfigPath $Config
                    Show-ScanResult -Result $r
                }
                catch {
                    Write-Info ('[{0}] 扫描失败：{1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $_.Exception.Message)
                }
                Start-Sleep -Seconds $Interval
            }
        }
    }
    exit 0
}
catch {
    Write-Host ('错误：' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
