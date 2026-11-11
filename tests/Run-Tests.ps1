# Run-Tests.ps1
# 在 workspace 内的假备份盘上验证核心行为，不接触真实 G 盘。

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$script:Pass = 0
$script:Fail = 0

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:Pass++
        Write-Host ('  PASS  ' + $Name)
    }
    else {
        $script:Fail++
        Write-Host ('  FAIL  ' + $Name + $(if ($Detail) { ' -> ' + $Detail } else { '' })) -ForegroundColor Red
    }
}

$repo = Split-Path $PSScriptRoot -Parent
$cli = Join-Path $repo 'backup-log.ps1'
$cfg = Join-Path $repo 'config.json'
$sandbox = Join-Path $PSScriptRoot 'sandbox'

if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force }
New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $sandbox '网盘重要信息备份\Typecho网站备份') -Force | Out-Null

$log = Join-Path $sandbox 'Backup_Log.log'
[System.IO.File]::WriteAllText($log, "[2024-11-03 00:00]`r`nLOG RECORD STARTED", (New-Object System.Text.UTF8Encoding($false)))

function Start-Cli {
    param([string]$Action = 'scan', [string]$Target, [switch]$Force, [string]$Cfg = $cfg)
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $cli, '-Action', $Action, '-Root', $Target, '-Config', $Cfg, '-Quiet')
    if ($Force) { $argv += '-Force' }
    return (& powershell.exe @argv 2>&1 | Out-String)
}

function Invoke-Scan {
    param([switch]$Force)
    return (Start-Cli -Action scan -Target $sandbox -Force:$Force)
}

function Get-LogText {
    return [System.IO.File]::ReadAllText($log, [System.Text.Encoding]::UTF8)
}

Write-Host '== 1. 基线 =='
$r = Invoke-Scan
Assert-True '首次扫描建立基线且不写日志' ((Get-LogText) -eq "[2024-11-03 00:00]`r`nLOG RECORD STARTED")
Assert-True '状态文件已生成' (Test-Path (Join-Path $sandbox '.backup-log\state.json'))

Write-Host '== 2. 新建目录 + 上传文件 =='
$d1 = Join-Path $sandbox '网盘重要信息备份\Typecho网站备份\山雨的湖边小屋'
New-Item -ItemType Directory -Path $d1 -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $d1 'backup_2026-11-11.dat'), ('A' * 100))
[System.IO.File]::WriteAllText((Join-Path $d1 'mount-rain_2026-11-11.tar.gz'), ('B' * 200))
$r = Invoke-Scan
$t = Get-LogText
Assert-True '生成 CREATE FOLDER' ($t.Contains('CREATE FOLDER "山雨的湖边小屋" AT ":\网盘重要信息备份\Typecho网站备份\"'))
Assert-True '生成 UPLOAD' ($t.Contains('UPLOAD "backup_2026-11-11.dat" TO ":\网盘重要信息备份\Typecho网站备份\山雨的湖边小屋\"'))
Assert-True '时间块格式正确' ($t -match '\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}\]')

Write-Host '== 3. 修改文件 =='
[System.IO.File]::WriteAllText((Join-Path $d1 'backup_2026-11-11.dat'), ('A' * 150))
$r = Invoke-Scan
$t = Get-LogText
Assert-True '生成 UPDATE' ($t.Contains('UPDATE "backup_2026-11-11.dat" TO ":\网盘重要信息备份\Typecho网站备份\山雨的湖边小屋\"'))

Write-Host '== 4. 目录改名 =='
$d2 = Join-Path $sandbox '网盘重要信息备份\Typecho网站备份\山雨的湖边小屋-改名'
Move-Item -LiteralPath $d1 -Destination $d2
$r = Invoke-Scan
$t = Get-LogText
Assert-True '生成 RENAME FOLDER' ($t.Contains('RENAME FOLDER ":\网盘重要信息备份\Typecho网站备份\山雨的湖边小屋\" TO ":\网盘重要信息备份\Typecho网站备份\山雨的湖边小屋-改名\"'))
Assert-True '改名不误报 UPLOAD' (-not $t.Contains('山雨的湖边小屋-改名\"' + "`r`nUPLOAD"))
Assert-True '改名不误报 DELETE' (-not $t.Contains('DELETE ":\网盘重要信息备份\Typecho网站备份\山雨的湖边小屋\"'))

Write-Host '== 5. 文件改名与移动 =='
[System.IO.File]::WriteAllText((Join-Path $d2 'rename-me.txt'), ('C' * 50))
$r = Invoke-Scan
$t = Get-LogText
Assert-True '新增文件确认' ($t.Contains('UPLOAD "rename-me.txt"'))
Move-Item -LiteralPath (Join-Path $d2 'rename-me.txt') -Destination (Join-Path $d2 'renamed.txt')
$r = Invoke-Scan
$t = Get-LogText
Assert-True '同目录改名 -> RENAME' ($t.Contains('RENAME ":\网盘重要信息备份\Typecho网站备份\山雨的湖边小屋-改名\rename-me.txt" TO ":\网盘重要信息备份\Typecho网站备份\山雨的湖边小屋-改名\renamed.txt"'))

New-Item -ItemType Directory -Path (Join-Path $sandbox '网盘重要信息备份\图片专区') -Force | Out-Null
$r = Invoke-Scan
Move-Item -LiteralPath (Join-Path $d2 'renamed.txt') -Destination (Join-Path $sandbox '网盘重要信息备份\图片专区\renamed.txt')
$r = Invoke-Scan
$t = Get-LogText
Assert-True '跨目录移动 -> MOVE' ($t.Contains('MOVE "renamed.txt" TO ":\网盘重要信息备份\图片专区\"'))

Write-Host '== 6. 删除目录只记一条 =='
$del = Join-Path $sandbox '网盘重要信息备份\待删除'
New-Item -ItemType Directory -Path (Join-Path $del '子目录') -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $del '子目录\a.txt'), 'x')
[System.IO.File]::WriteAllText((Join-Path $del 'b.txt'), 'y')
$r = Invoke-Scan
Remove-Item -LiteralPath $del -Recurse -Force
$r = Invoke-Scan
$t = Get-LogText
$deleteCount = ([regex]::Matches($t, [regex]::Escape('DELETE ":\网盘重要信息备份\待删除'))).Count
Assert-True '删除目录只写一条 DELETE' ($deleteCount -eq 1) ('实际 ' + $deleteCount)
Assert-True '不写子文件 DELETE' (-not $t.Contains('DELETE ":\网盘重要信息备份\待删除\b.txt"'))

Write-Host '== 7. 归档识别 =='
$arcDir = Join-Path $sandbox '网盘重要信息备份\图片专区\记录-测试'
New-Item -ItemType Directory -Path $arcDir -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $arcDir 'p1.jpg'), ('D' * 500))
[System.IO.File]::WriteAllText((Join-Path $arcDir 'p2.jpg'), ('E' * 400))
$r = Invoke-Scan
Remove-Item -LiteralPath $arcDir -Recurse -Force
[System.IO.File]::WriteAllText((Join-Path $sandbox '网盘重要信息备份\图片专区\ARC-202611112300.zip'), ('F' * 800))
$r = Invoke-Scan
$t = Get-LogText
Assert-True '归档写成 ARCHIVE' ($t.Contains('ARCHIVE ":\网盘重要信息备份\图片专区\记录-测试\" TO ARC-202611112300.zip'))
Assert-True '归档不再写 DELETE' (-not $t.Contains('DELETE ":\网盘重要信息备份\图片专区\记录-测试\"'))

Write-Host '== 8. 幂等性 =='
$before = Get-LogText
$r = Invoke-Scan
$after = Get-LogText
Assert-True '无变化时不追加任何内容' ($before -eq $after)

Write-Host '== 9. 格式校验 =='
$t = Get-LogText
Assert-True '使用 CRLF' ($t.Contains("`r`n"))
Assert-True '不含孤立 LF' (-not ($t -match "(?<!`r)`n"))
$bytes = [System.IO.File]::ReadAllBytes($log)
Assert-True '无 BOM' (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
Assert-True '块之间只有一个空行' (-not ($t -match "`r`n`r`n`r`n"))
Assert-True '末尾无多余换行' (-not $t.EndsWith("`r`n"))
Assert-True '所有路径以 :\ 开头' (-not ($t -match '"G:\\'))

Write-Host '== 10. 变化过大保护 =='
$guardRoot = Join-Path $PSScriptRoot 'guard'
if (Test-Path -LiteralPath $guardRoot) { Remove-Item -LiteralPath $guardRoot -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $guardRoot '网盘重要信息备份') -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $guardRoot 'Backup_Log.log'), '', (New-Object System.Text.UTF8Encoding($false)))
$null = Start-Cli -Action scan -Target $guardRoot
for ($i = 0; $i -lt 30; $i++) {
    [System.IO.File]::WriteAllText((Join-Path $guardRoot ('网盘重要信息备份\f' + $i + '.txt')), 'x')
}
$out = Start-Cli -Action scan -Target $guardRoot
Assert-True '超过阈值时中止' ($LASTEXITCODE -ne 0)
Assert-True '提示需要 -Force' ($out.Contains('-Force'))

Write-Host ''
Write-Host '== 11. 图片合并 =='
$aggRoot = Join-Path $PSScriptRoot 'agg'
if (Test-Path -LiteralPath $aggRoot) { Remove-Item -LiteralPath $aggRoot -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $aggRoot '网盘重要信息备份') -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $aggRoot 'Backup_Log.log'), '', $utf8)

$aggCfg = Join-Path $PSScriptRoot 'agg.config.json'
$base = [System.IO.File]::ReadAllText($cfg, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$base.aggregateImages = 10
[System.IO.File]::WriteAllText($aggCfg, ($base | ConvertTo-Json -Depth 5), $utf8)

$null = Start-Cli -Action scan -Target $aggRoot -Cfg $aggCfg

$batch = Join-Path $aggRoot '网盘重要信息备份\图片专区\批次'
New-Item -ItemType Directory -Path $batch -Force | Out-Null
for ($i = 1; $i -le 12; $i++) {
    [System.IO.File]::WriteAllText((Join-Path $batch ('IMG{0:D2}.jpg' -f $i)), 'x')
}
[System.IO.File]::WriteAllText((Join-Path $batch '说明.txt'), 'note')
[System.IO.File]::WriteAllText((Join-Path $batch '清单.csv'), 'a,b')
$null = Start-Cli -Action scan -Target $aggRoot -Cfg $aggCfg
$at = [System.IO.File]::ReadAllText((Join-Path $aggRoot 'Backup_Log.log'), [System.Text.Encoding]::UTF8)
Assert-True '12 张图片合并成一条' ($at.Contains('UPLOAD 12 image(s) TO ":\网盘重要信息备份\图片专区\批次\"'))
Assert-True '非图片文件仍逐条记录' ($at.Contains('UPLOAD "说明.txt" TO ":\网盘重要信息备份\图片专区\批次\"'))
Assert-True '非图片文件（csv）仍逐条记录' ($at.Contains('UPLOAD "清单.csv" TO ":\网盘重要信息备份\图片专区\批次\"'))
Assert-True '不再逐张列出图片' (-not $at.Contains('UPLOAD "IMG01.jpg"'))

$small = Join-Path $aggRoot '网盘重要信息备份\图片专区\少于阈值'
New-Item -ItemType Directory -Path $small -Force | Out-Null
for ($i = 1; $i -le 3; $i++) {
    [System.IO.File]::WriteAllText((Join-Path $small ('a{0}.png' -f $i)), 'y')
}
$null = Start-Cli -Action scan -Target $aggRoot -Cfg $aggCfg
$at = [System.IO.File]::ReadAllText((Join-Path $aggRoot 'Backup_Log.log'), [System.Text.Encoding]::UTF8)
Assert-True '低于阈值时逐条记录' ($at.Contains('UPLOAD "a1.png" TO ":\网盘重要信息备份\图片专区\少于阈值\"'))
Assert-True '低于阈值时不出合并行' (-not $at.Contains('UPLOAD 3 image(s)'))

Write-Host ('结果：PASS={0}  FAIL={1}' -f $script:Pass, $script:Fail)
Write-Host ''
Write-Host '--- 生成的日志 ---'
Write-Host (Get-LogText)
exit $(if ($script:Fail -gt 0) { 1 } else { 0 })
