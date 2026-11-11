# Setup.ps1 —— 首次使用向导
# 作用：解除下载锁定、选备份盘、必要时创建日志文件、建立基线、可选装计划任务和快捷方式。
# 由根目录的 setup.cmd 调用（双击即可），也可以手动跑。

[CmdletBinding()]
param(
    [string]$Drive,
    [int]$Interval = 15,
    [switch]$NoTask,
    [switch]$NoShortcut,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'lib\BackupLog.Core.ps1')
$configPath = Join-Path $root 'config.json'

function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host ('== ' + $Text) -ForegroundColor Cyan
}

function Ask-Yes {
    param([string]$Question, [bool]$Default = $true)
    if ($Yes) { return $Default }
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    $a = Read-Host ($Question + ' ' + $hint)
    if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
    return ($a -match '^[Yy]')
}

Write-Host ''
Write-Host '备份日志自动化 —— 首次使用向导' -ForegroundColor White -BackgroundColor DarkBlue
Write-Host ''

# 0. 解除「来自网络」锁定（从 ZIP 解压出来的脚本常带这个标记）
$unblocked = 0
foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -File -Include *.ps1, *.psm1, *.cmd)) {
    try { Unblock-File -LiteralPath $f.FullName -ErrorAction Stop; $unblocked++ } catch { }
}
if ($unblocked -gt 0) { Write-Host ('已解除 {0} 个脚本的下载锁定。' -f $unblocked) }

# 1. 选盘
Write-Step '选择备份盘'

$drives = @([System.IO.DriveInfo]::GetDrives() | Where-Object {
        $_.IsReady -and (@('Fixed', 'Removable', 'Network') -contains $_.DriveType.ToString())
    })

if ($drives.Count -eq 0) { throw '没有找到可用的磁盘。' }

$picked = $null

if ($Drive) {
    $letter = $Drive.TrimEnd('\')
    $picked = $drives | Where-Object { $_.Name.TrimEnd('\') -ieq $letter } | Select-Object -First 1
    if (-not $picked) { throw ("找不到盘：{0}" -f $Drive) }
}
else {
    # 已经有 Backup_Log.log 的盘优先
    $existing = @($drives | Where-Object { Test-Path -LiteralPath ($_.RootDirectory.FullName + 'Backup_Log.log') })
    if ($existing.Count -eq 1) {
        $picked = $existing[0]
        Write-Host ('发现已有日志的盘：{0}' -f $picked.Name)
    }
}

if (-not $picked) {
    Write-Host '可用磁盘：'
    for ($i = 0; $i -lt $drives.Count; $i++) {
        $d = $drives[$i]
        $label = $d.VolumeLabel
        $freeGB = [math]::Round($d.AvailableFreeSpace / 1GB, 1)
        $hasLog = if (Test-Path -LiteralPath ($d.RootDirectory.FullName + 'Backup_Log.log')) { ' [已有日志]' } else { '' }
        Write-Host ('  {0}. {1}  {2,-12} 剩余 {3} GB{4}' -f ($i + 1), $d.Name, $label, $freeGB, $hasLog)
    }
    if ($Yes) { throw '非交互模式下必须用 -Drive 指定盘符，例如 -Drive G:' }
    $sel = Read-Host ('请输入序号（1-{0}）' -f $drives.Count)
    $idx = 0
    if (-not [int]::TryParse($sel, [ref]$idx) -or $idx -lt 1 -or $idx -gt $drives.Count) { throw '序号无效。' }
    $picked = $drives[$idx - 1]
}

$driveRoot = $picked.RootDirectory.FullName
if (-not $driveRoot.EndsWith('\')) { $driveRoot += '\' }
Write-Host ('已选择：{0}  ({1})' -f $picked.Name, $driveRoot)

# 2. 必要时创建日志文件
Write-Step '准备日志文件'

$logPath = Join-Path $driveRoot 'Backup_Log.log'
if (Test-Path -LiteralPath $logPath) {
    $size = (Get-Item -LiteralPath $logPath).Length
    Write-Host ('已存在：{0}（{1} 字节），不会改动它。' -f $logPath, $size)
}
else {
    $head = ('[{0}]' -f (Get-Date).ToString('yyyy-MM-dd HH:mm')) + "`r`nLOG RECORD STARTED"
    try {
        [System.IO.File]::WriteAllText($logPath, $head, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host ('已创建：{0}' -f $logPath)
    }
    catch { throw ('无法在 {0} 创建日志文件：{1}' -f $driveRoot, $_.Exception.Message) }
}

# 3. 写配置
Write-Step '写入配置'

$cfg = if (Test-Path -LiteralPath $configPath) {
    [System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
}
else { [pscustomobject]@{} }

$cfg | Add-Member -NotePropertyName requiredMarkers -NotePropertyValue @('Backup_Log.log') -Force
$cfg | Add-Member -NotePropertyName logFile -NotePropertyValue 'Backup_Log.log' -Force
if (-not $cfg.PSObject.Properties['stateDir']) { $cfg | Add-Member -NotePropertyName stateDir -NotePropertyValue '.backup-log' }
if (-not $cfg.PSObject.Properties['scanIntervalMinutes']) { $cfg | Add-Member -NotePropertyName scanIntervalMinutes -NotePropertyValue $Interval }

[System.IO.File]::WriteAllText($configPath, ($cfg | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ('配置已更新：{0}' -f $configPath)

# 4. 建立基线
Write-Step '建立基线'
$scan = Invoke-BackupLogScan -Root $driveRoot -ConfigPath $configPath -Reinit
Write-Host $scan.Message

# 5. 计划任务
Write-Step '自动扫描'
if (-not $NoTask) {
    if (Ask-Yes ('安装计划任务，每 {0} 分钟自动扫描一次？' -f $Interval) $true) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\Install-Schedule.ps1') -IntervalMinutes $Interval | Out-Null
        Write-Host '计划任务已安装。'
    }
    else { Write-Host '已跳过。以后可运行 tools\Install-Schedule.ps1 安装。' }
}

# 6. 快捷方式
Write-Step '快捷方式'
if (-not $NoShortcut) {
    if (Ask-Yes '在桌面和开始菜单创建「备份日志自动化」快捷方式？' $true) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'gui\install.ps1') -Action install | Out-Null
        Write-Host '快捷方式已创建。'
    }
    else { Write-Host '已跳过。以后可运行 gui\install.ps1 创建。' }
}

Write-Host ''
Write-Host '完成。' -ForegroundColor Green
Write-Host '  · 日常：双击桌面「备份日志自动化」查看状态、预览变更、改设置'
Write-Host '  · 手动扫描一次：powershell -NoProfile -ExecutionPolicy Bypass -File .\backup-log.ps1 -Action scan'
Write-Host '  · 试运行（只看会写什么）：在上一步命令后加 -DryRun'
Write-Host ''
