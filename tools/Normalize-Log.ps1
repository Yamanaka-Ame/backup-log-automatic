# Normalize-Log.ps1 —— 把历史日志条目统一成工具当前的输出格式
# 只改写法，不动时间块、顺序和内容；[Warn]/[Error] 之类的备注行原样保留。

param(
    [string]$Source = 'G:\Backup_Log.log',
    [string]$Target,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

$text = [System.IO.File]::ReadAllText($Source, [System.Text.Encoding]::UTF8)
$lines = $text -split "`r`n"

$stats = [ordered]@{
    'CREATE 旧式 -> 名字+AT'  = 0
    'DELETE FOLDER -> DELETE' = 0
    'UPDATE 目录 -> UPDATE FOLDER' = 0
    'RENAME 引号修复'          = 0
    'UPLOAD 补 TO'             = 0
    'UPLOAD 名字加引号'        = 0
    '空行规整'                 = 0
}
$unmatched = New-Object System.Collections.Generic.List[string]
$out = New-Object System.Collections.Generic.List[string]

function Get-Leaf([string]$p) {
    $t = $p.TrimEnd('\')
    $i = $t.LastIndexOf('\')
    if ($i -lt 0) { return $t }
    return $t.Substring($i + 1)
}

function Get-Parent([string]$p) {
    $t = $p.TrimEnd('\')
    $i = $t.LastIndexOf('\')
    if ($i -lt 0) { return '' }
    $parent = $t.Substring(0, $i)
    if (-not $parent.EndsWith('\')) { $parent += '\' }
    return $parent
}

foreach ($raw in $lines) {
    $line = $raw.TrimEnd()
    $s = $line.Trim()

    if ($s -eq '') { $out.Add(''); continue }
    if ($s -match '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}\]$') { $out.Add($s); continue }
    if ($s -match '^\[(Warn|Error|Info|debug)\]') { $out.Add($s); continue }
    if ($s -eq 'LOG RECORD STARTED') { $out.Add($s); continue }

    # 1) CREATE FOLDER "完整路径\" -> CREATE FOLDER "名" AT "父\"
    if ($s -match '^CREATE FOLDER\s+"(?<p>[^"]+)"$' -and $matches.p.EndsWith('\')) {
        $p = $matches.p
        $out.Add(('CREATE FOLDER "{0}" AT "{1}"' -f (Get-Leaf $p), (Get-Parent $p)))
        $stats['CREATE 旧式 -> 名字+AT']++
        continue
    }

    # 2) DELETE FOLDER "x" -> DELETE "x"
    if ($s -match '^DELETE FOLDER\s+(?<rest>.+)$') {
        $out.Add('DELETE ' + $matches.rest)
        $stats['DELETE FOLDER -> DELETE']++
        continue
    }

    # 3) UPDATE "目录\" -> UPDATE FOLDER "名" AT "父\"
    if ($s -match '^UPDATE\s+"(?<p>[^"]+)"$' -and $matches.p.EndsWith('\')) {
        $p = $matches.p
        $out.Add(('UPDATE FOLDER "{0}" AT "{1}"' -f (Get-Leaf $p), (Get-Parent $p)))
        $stats['UPDATE 目录 -> UPDATE FOLDER']++
        continue
    }

    # 4) RENAME FOLDER 引号缺失修复
    if ($s -match '^RENAME FOLDER\s+"(?<a>[^"]+?)\\?\s*TO\s*"?\\?(?<b>[^"]+?)"?$') {
        $a = $matches.a
        $b = $matches.b
        if (-not $a.EndsWith('\')) { $a += '\' }
        if (-not $b.StartsWith(':\')) { $b = ':\' + $b.TrimStart('\') }
        if (-not $b.EndsWith('\')) { $b += '\' }
        $out.Add(('RENAME FOLDER "{0}" TO "{1}"' -f $a, $b))
        $stats['RENAME 引号修复']++
        continue
    }


    # 6) UPLOAD 裸名 + TO + 路径 -> 名字加引号
    if ($s -match '^UPLOAD\s+(?<n>[^"]+?)\s+TO\s+(?<d>".*")$') {
        $name = $matches.n.Trim()
        if ($name -match '^\d+\s+image\(s\)$') { $out.Add($s); continue }
        $out.Add(('UPLOAD "{0}" TO {1}' -f $name, $matches.d))
        $stats['UPLOAD 名字加引号']++
        continue
    }
    # 5) UPLOAD 裸名 + 后面直接跟路径（缺 TO）
    if ($s -match '^UPLOAD\s+(?<n>[^"]+?)\s+(?<d>":\\[^"]*")$' -and $matches.n.Trim() -notmatch '\sTO$') {
        $out.Add(('UPLOAD "{0}" TO {1}' -f $matches.n.Trim(), $matches.d))
        $stats['UPLOAD 补 TO']++
        continue
    }

    # 6b) UPDATE 裸名 + TO + 路径 -> 名字加引号
    if ($s -match '^UPDATE\s+(?<n>[^"]+?)\s+TO\s+(?<d>".*")$') {
        $out.Add(('UPDATE "{0}" TO {1}' -f $matches.n.Trim(), $matches.d))
        $stats['UPLOAD 名字加引号']++
        continue
    }

    # 6c) UPDATE ... IN "路径" -> TO
    if ($s -match '^UPDATE\s+(?<n>[^"]+?)\s+IN\s+(?<d>".*")$') {
        $out.Add(('UPDATE "{0}" TO {1}' -f $matches.n.Trim(), $matches.d))
        $stats['UPLOAD 名字加引号']++
        continue
    }

    # 6d) UPLOAD image "名" TO "路径" -> 去掉多余的 image
    if ($s -match '^UPLOAD\s+image\s+(?<n>"[^"]+")\s+TO\s+(?<d>".*")$') {
        $out.Add(('UPLOAD {0} TO {1}' -f $matches.n, $matches.d))
        $stats['UPLOAD 名字加引号']++
        continue
    }

    # 其余（已是规范写法，或 ARCHIVE / COMPRESS / MOVE 等）原样保留
    if ($s -notmatch '^(CREATE FOLDER|UPLOAD|UPDATE|DELETE|RENAME FOLDER|RENAME|MOVE|COMPRESS FOLDER|ARCHIVE)\b') {
        $unmatched.Add($s)
    }
    $out.Add($s)
}

# 规整空行：块之间恰好一个空行，末尾不留空行
$clean = New-Object System.Collections.Generic.List[string]
foreach ($l in $out) {
    if ($l -eq '' -and $clean.Count -gt 0 -and $clean[$clean.Count - 1] -eq '') { $stats['空行规整']++; continue }
    $clean.Add($l)
}
while ($clean.Count -gt 0 -and $clean[$clean.Count - 1] -eq '') { $clean.RemoveAt($clean.Count - 1) }

$result = ($clean -join "`r`n")

if (-not $Target) { $Target = $Source }

if ($Apply) {
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $backupDir = Join-Path (Split-Path $Source -Parent) '.backup-log\backups'
    if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
    $backup = Join-Path $backupDir ('Backup_Log-before-normalize-' + $stamp + '.log')
    Copy-Item -LiteralPath $Source -Destination $backup -Force
    [System.IO.File]::WriteAllText($Target, $result, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ('已备份：' + $backup)
    Write-Host ('已写入：' + $Target)
}
else {
    [System.IO.File]::WriteAllText($Target, $result, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ('预览已写入：' + $Target)
}

Write-Host ''
Write-Host '--- 改动统计 ---'
foreach ($k in $stats.Keys) { Write-Host ('{0,4}  {1}' -f $stats[$k], $k) }
Write-Host ('{0,4}  {1}' -f $lines.Count, '原始行数')
Write-Host ('{0,4}  {1}' -f $clean.Count, '结果行数')
if ($unmatched.Count -gt 0) {
    Write-Host ''
    Write-Host ('--- 未能识别、原样保留的 {0} 行 ---' -f $unmatched.Count)
    $unmatched | Select-Object -First 20 | ForEach-Object { Write-Host ('  ' + $_) }
}
