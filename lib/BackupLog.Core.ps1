# BackupLog.Core.ps1
# 备份盘动向追踪核心：盘符识别、快照对比、日志条目生成与追加。
# 兼容 Windows PowerShell 5.1（文件需保存为 UTF-8 with BOM）。

function Read-BackupLogConfig {
    param([string]$Path)

    $cfg = [ordered]@{
        requiredMarkers  = @('Backup_Log.log', '网盘重要信息备份')
        logFile          = 'Backup_Log.log'
        stateDir         = '.backup-log'
        excludeTop       = @('$RECYCLE.BIN', 'System Volume Information', '.backup-log')
        excludeExact     = @('Backup_Log.log', 'Backup_log_README.txt')
        pathStyle        = 'relative'   # relative -> ":\网盘..."；drive -> "G:\网盘..."
        maxChangePercent = 40
        detectArchive    = $true
        aggregateImages  = 0            # >0 时，同一目录内同批图片超过该数量才合并成一条
    }

    if ($Path -and (Test-Path -LiteralPath $Path)) {
        $json = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path, [System.Text.Encoding]::UTF8)
        if ($json.Trim().Length -gt 0) {
            $user = $json | ConvertFrom-Json
            foreach ($p in $user.PSObject.Properties) { $cfg[$p.Name] = $p.Value }
        }
    }

    return [pscustomobject]$cfg
}

function Resolve-BackupRoot {
    param($Config, [string]$Root)

    if ($Root) {
        $r = [System.IO.Path]::GetFullPath($Root)
        if (-not $r.EndsWith('\')) { $r += '\' }
        if (-not (Test-Path -LiteralPath $r)) { throw "指定的根路径不存在：$r" }
        return [pscustomobject]@{ Root = $r; Drive = $r.Substring(0, 2) }
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if (-not $d.IsReady) { continue }
        $type = $d.DriveType.ToString()
        if (@('Fixed', 'Removable', 'Network') -notcontains $type) { continue }

        $root = $d.RootDirectory.FullName
        if (-not $root.EndsWith('\')) { $root += '\' }

        $missing = @()
        foreach ($m in $Config.requiredMarkers) {
            if (-not (Test-Path -LiteralPath ($root + $m))) { $missing += $m }
        }
        if ($missing.Count -eq 0) {
            $candidates.Add([pscustomobject]@{ Root = $root; Drive = $d.Name.TrimEnd('\') })
        }
    }

    if ($candidates.Count -eq 0) {
        throw ("未找到备份盘（盘根需同时包含：" + ($Config.requiredMarkers -join '、') + "）。可用 -Root 手动指定。")
    }
    if ($candidates.Count -gt 1) {
        $list = ($candidates | ForEach-Object { $_.Drive }) -join '、'
        throw "找到多个符合条件的盘：$list。请用 -Root 指定其中一块。"
    }
    return $candidates[0]
}

function Get-LeafName {
    param([string]$Rel)
    if ([string]::IsNullOrEmpty($Rel)) { return '' }
    $i = $Rel.LastIndexOf('\')
    if ($i -lt 0) { return $Rel }
    return $Rel.Substring($i + 1)
}

function Get-ParentRel {
    param([string]$Rel)
    $i = $Rel.LastIndexOf('\')
    if ($i -lt 0) { return '' }
    return $Rel.Substring(0, $i)
}

function Format-LogPath {
    param([string]$Rel, [bool]$IsDir, [string]$Style, [string]$Drive)

    $prefix = ':'
    if ($Style -eq 'drive' -and $Drive) { $prefix = $Drive }

    if ([string]::IsNullOrEmpty($Rel)) {
        if ($IsDir) { return ($prefix + '\') }
        return $prefix
    }

    $p = $Rel -replace '/', '\'
    if ($IsDir) { return ($prefix + '\' + $p + '\') }
    return ($prefix + '\' + $p)
}

function Get-BackupSnapshot {
    param($Config, [string]$Root)

    $entries = @{}
    $len = $Root.Length

    $items = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue -Attributes !ReparsePoint)

    foreach ($it in $items) {
        $full = $it.FullName
        if ($full.Length -le $len) { continue }
        $rel = $full.Substring($len).Trim('\')
        if ($rel.Length -eq 0) { continue }

        $top = $rel
        $slash = $rel.IndexOf('\')
        if ($slash -ge 0) { $top = $rel.Substring(0, $slash) }

        if ($Config.excludeTop -contains $top) { continue }
        if ($Config.excludeExact -contains $rel) { continue }

        if ($it.PSIsContainer) {
            $entries[$rel] = @{ T = 'D'; S = [int64]0; M = [int64]$it.LastWriteTimeUtc.Ticks; K = [int64]0; Z = [int64]0 }
        }
        else {
            $entries[$rel] = @{ T = 'F'; S = [int64]$it.Length; M = [int64]$it.LastWriteTimeUtc.Ticks }
        }
    }

    # 目录聚合：文件数 K 与总字节 Z，用于改名/移动的指纹匹配
    foreach ($rel in @($entries.Keys)) {
        $e = $entries[$rel]
        if ($e.T -ne 'F') { continue }
        $p = $rel
        while ($true) {
            $i = $p.LastIndexOf('\')
            if ($i -lt 0) { break }
            $p = $p.Substring(0, $i)
            if ($entries.ContainsKey($p)) {
                $entries[$p].K = [int64]$entries[$p].K + 1
                $entries[$p].Z = [int64]$entries[$p].Z + [int64]$e.S
            }
        }
    }

    return $entries
}

function Get-DirFingerprint {
    param($Entries, [string]$Rel)

    $prefix = $Rel + '\'
    $parts = New-Object System.Collections.Generic.List[string]

    foreach ($k in $Entries.Keys) {
        if ($Entries[$k].T -ne 'F') { continue }
        if ($k.Length -le $prefix.Length) { continue }
        if (-not $k.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $parts.Add($k.Substring($prefix.Length) + '|' + $Entries[$k].S)
    }

    $parts.Sort([System.StringComparer]::Ordinal)
    $joined = [string]::Join("`n", $parts.ToArray())
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($joined)
        return [System.BitConverter]::ToString($sha.ComputeHash($bytes))
    }
    finally { $sha.Dispose() }
}

function Get-StateDirectory {
    param($Config, [string]$Root)
    if ([System.IO.Path]::IsPathRooted([string]$Config.stateDir)) { return [string]$Config.stateDir }
    return (Join-Path $Root $Config.stateDir)
}

function Get-StatePath {
    param($Config, [string]$Root)
    return (Join-Path (Get-StateDirectory -Config $Config -Root $Root) 'state.json')
}

function Get-LogPath {
    param($Config, [string]$Root)
    return (Join-Path $Root $Config.logFile)
}

function Save-BackupState {
    param($Config, [string]$Root, $Entries)

    $dir = Get-StateDirectory -Config $Config -Root $Root
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $obj = [ordered]@{
        version    = 1
        root       = $Root
        capturedAt = (Get-Date).ToString('o')
        count      = $Entries.Count
        entries    = $Entries
    }
    $json = $obj | ConvertTo-Json -Depth 6 -Compress

    $target = Get-StatePath -Config $Config -Root $Root
    $tmp = $target + '.tmp'
    [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $target -Force
}

function Read-BackupState {
    param($Config, [string]$Root)

    $p = Get-StatePath -Config $Config -Root $Root
    if (-not (Test-Path -LiteralPath $p)) { return $null }

    $json = [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
    $o = $json | ConvertFrom-Json

    $map = @{}
    foreach ($pr in $o.entries.PSObject.Properties) {
        $v = $pr.Value
        $map[$pr.Name] = @{
            T = [string]$v.T
            S = [int64]$v.S
            M = [int64]$v.M
            K = [int64]$v.K
            Z = [int64]$v.Z
        }
    }

    return [pscustomobject]@{ CapturedAt = $o.capturedAt; Root = $o.root; Entries = $map }
}

function New-ChangeSet {
    return [pscustomobject]@{
        AddedDirs    = New-Object System.Collections.Generic.List[string]
        AddedFiles   = New-Object System.Collections.Generic.List[string]
        RemovedDirs  = New-Object System.Collections.Generic.List[string]
        RemovedFiles = New-Object System.Collections.Generic.List[string]
        UpdatedFiles = New-Object System.Collections.Generic.List[string]
        FolderMoves  = New-Object System.Collections.Generic.List[object]
        FileMoves    = New-Object System.Collections.Generic.List[object]
        Archives     = New-Object System.Collections.Generic.List[object]
        TotalBefore  = 0
        TotalAfter   = 0
    }
}

function Test-ImageName {
    param([string]$Name)
    $n = $Name.ToLowerInvariant()
    foreach ($ext in @('.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.heif', '.tif', '.tiff', '.svg', '.avif')) {
        if ($n.EndsWith($ext)) { return $true }
    }
    return $false
}

function Test-ArchiveName {
    param([string]$Name)
    $n = $Name.ToLowerInvariant()
    foreach ($ext in @('.zip', '.rar', '.7z', '.tar', '.gz', '.tgz', '.bz2', '.xz')) {
        if ($n.EndsWith($ext)) { return $true }
    }
    return $false
}

function Compare-BackupSnapshot {
    param($Old, $New, $Config)

    $result = New-ChangeSet
    $result.TotalBefore = $Old.Count
    $result.TotalAfter = $New.Count

    $removed = New-Object System.Collections.Generic.List[string]
    $added = New-Object System.Collections.Generic.List[string]

    foreach ($k in $Old.Keys) {
        if (-not $New.ContainsKey($k)) { $removed.Add($k) }
    }
    foreach ($k in $New.Keys) {
        if (-not $Old.ContainsKey($k)) { $added.Add($k) }
        elseif ($Old[$k].T -eq 'F' -and ([int64]$Old[$k].S -ne [int64]$New[$k].S -or [int64]$Old[$k].M -ne [int64]$New[$k].M)) {
            $result.UpdatedFiles.Add($k)
        }
    }

    # ---------- 1. 文件夹改名 / 移动 ----------
    $removedDirs = @($removed | Where-Object { $Old[$_].T -eq 'D' })
    $addedDirs = @($added | Where-Object { $New[$_].T -eq 'D' })

    if ($removedDirs.Count -gt 0 -and $addedDirs.Count -gt 0) {
        $oldFp = @{}
        foreach ($d in $removedDirs) { $oldFp[$d] = Get-DirFingerprint -Entries $Old -Rel $d }
        $newFp = @{}
        foreach ($d in $addedDirs) { $newFp[$d] = Get-DirFingerprint -Entries $New -Rel $d }

        $byFp = @{}
        foreach ($d in $addedDirs) {
            $fp = $newFp[$d]
            if (-not $byFp.ContainsKey($fp)) { $byFp[$fp] = New-Object System.Collections.Generic.List[string] }
            $byFp[$fp].Add($d)
        }

        $pairs = New-Object System.Collections.Generic.List[object]
        foreach ($od in $removedDirs) {
            $fp = $oldFp[$od]
            if (-not $byFp.ContainsKey($fp)) { continue }
            $cands = $byFp[$fp]
            if ($cands.Count -eq 0) { continue }

            $leaf = Get-LeafName $od
            $pick = $null
            foreach ($c in $cands) {
                if ((Get-LeafName $c) -ieq $leaf) { $pick = $c; break }
            }
            if ($null -eq $pick -and $cands.Count -eq 1) { $pick = $cands[0] }
            if ($null -eq $pick) { continue }

            [void]$cands.Remove($pick)
            $pairs.Add([pscustomobject]@{ Old = $od; New = $pick })
        }

        foreach ($p in $pairs) {
            $result.FolderMoves.Add($p)

            $keepRemoved = New-Object System.Collections.Generic.List[string]
            foreach ($x in $removed) {
                if ($x -ieq $p.Old) { continue }
                if ($x.StartsWith($p.Old + '\', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                $keepRemoved.Add($x)
            }
            $removed = $keepRemoved

            $keepAdded = New-Object System.Collections.Generic.List[string]
            foreach ($x in $added) {
                if ($x -ieq $p.New) { continue }
                if ($x.StartsWith($p.New + '\', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                $keepAdded.Add($x)
            }
            $added = $keepAdded

            # 整棵树搬过去后，内部被修改的文件仍需记 UPDATE
            $prefNew = $p.New + '\'
            foreach ($k in $New.Keys) {
                if (-not $k.StartsWith($prefNew, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                if ($New[$k].T -ne 'F') { continue }
                $suffix = $k.Substring($prefNew.Length)
                $oldK = $p.Old + '\' + $suffix
                if (-not $Old.ContainsKey($oldK)) { continue }
                if ([int64]$Old[$oldK].S -ne [int64]$New[$k].S -or [int64]$Old[$oldK].M -ne [int64]$New[$k].M) {
                    $result.UpdatedFiles.Add($k)
                }
            }
        }
    }

    # 嵌套改名只保留最外层一条（父目录改名时子目录会各自命中一次）
    if ($result.FolderMoves.Count -gt 1) {
        $topMoves = New-Object System.Collections.Generic.List[object]
        foreach ($m in $result.FolderMoves) {
            $nested = $false
            foreach ($o in $result.FolderMoves) {
                if ([object]::ReferenceEquals($o, $m)) { continue }
                if ($m.Old.StartsWith($o.Old + '\', [System.StringComparison]::OrdinalIgnoreCase)) { $nested = $true; break }
            }
            if (-not $nested) { $topMoves.Add($m) }
        }
        $result.FolderMoves = $topMoves
    }

    # ---------- 2. 文件改名 / 移动（同名同大小同时间）----------
    $removedFiles = @($removed | Where-Object { $Old[$_].T -eq 'F' })
    $addedFiles = @($added | Where-Object { $New[$_].T -eq 'F' })

    $consumedRemoved = New-Object System.Collections.Generic.List[string]
    $consumedAdded = New-Object System.Collections.Generic.List[string]

    if ($removedFiles.Count -gt 0 -and $addedFiles.Count -gt 0) {
        $index = @{}
        foreach ($a in $addedFiles) {
            $key = ('{0}|{1}' -f $New[$a].S, $New[$a].M)
            if (-not $index.ContainsKey($key)) { $index[$key] = New-Object System.Collections.Generic.List[string] }
            $index[$key].Add($a)
        }

        foreach ($r in $removedFiles) {
            $key = ('{0}|{1}' -f $Old[$r].S, $Old[$r].M)
            if (-not $index.ContainsKey($key)) { continue }
            $cands = $index[$key]
            if ($cands.Count -eq 0) { continue }

            $leaf = Get-LeafName $r
            $pick = $null
            foreach ($c in $cands) {
                if ((Get-LeafName $c) -ieq $leaf) { $pick = $c; break }
            }
            if ($null -eq $pick -and $cands.Count -eq 1) { $pick = $cands[0] }
            if ($null -eq $pick) { continue }

            [void]$cands.Remove($pick)
            $result.FileMoves.Add([pscustomobject]@{ Old = $r; New = $pick })
            $consumedRemoved.Add($r)
            $consumedAdded.Add($pick)
        }
    }

    $keptRemoved = New-Object System.Collections.Generic.List[string]
    foreach ($x in $removed) {
        if ($consumedRemoved -contains $x) { continue }
        $keptRemoved.Add($x)
    }
    $removed = $keptRemoved

    $keptAdded = New-Object System.Collections.Generic.List[string]
    foreach ($x in $added) {
        if ($consumedAdded -contains $x) { continue }
        $keptAdded.Add($x)
    }
    $added = $keptAdded

    # ---------- 3. 归档识别：目录消失 + 同目录出现同名压缩包 ----------
    if ($Config.detectArchive) {
        $archivedDirs = New-Object System.Collections.Generic.List[string]
        foreach ($d in @($removed | Where-Object { $Old.ContainsKey($_) -and $Old[$_].T -eq 'D' })) {
            $parent = Get-ParentRel $d
            $dirSize = [int64]$Old[$d].Z
            $best = $null
            foreach ($a in @($added | Where-Object { $New.ContainsKey($_) -and $New[$_].T -eq 'F' })) {
                if ((Get-ParentRel $a) -ine $parent) { continue }
                $name = Get-LeafName $a
                if (-not (Test-ArchiveName $name)) { continue }
                $size = [int64]$New[$a].S
                $ok = $false
                if ($dirSize -le 0) { $ok = $true }
                elseif ($size -ge ($dirSize * 0.15) -and $size -le ($dirSize * 1.35)) { $ok = $true }
                if ($ok) { $best = $a; break }
            }
            if ($null -ne $best) {
                $result.Archives.Add([pscustomobject]@{ Dir = $d; File = $best; Size = [int64]$New[$best].S })
                $archivedDirs.Add($d)
                [void]$added.Remove($best)
            }
        }
        if ($archivedDirs.Count -gt 0) {
            $keep = New-Object System.Collections.Generic.List[string]
            foreach ($x in $removed) {
                $skip = $false
                foreach ($d in $archivedDirs) {
                    if ($x -ieq $d -or $x.StartsWith($d + '\', [System.StringComparison]::OrdinalIgnoreCase)) { $skip = $true; break }
                }
                if (-not $skip) { $keep.Add($x) }
            }
            $removed = $keep
        }
    }

    # ---------- 4. 归位：顶层目录删除只记一条 ----------
    $removedDirSet = @($removed | Where-Object { $Old[$_].T -eq 'D' })
    foreach ($d in $removedDirSet) {
        $isNested = $false
        $p = Get-ParentRel $d
        while ($p.Length -gt 0) {
            if ($Old.ContainsKey($p) -and -not $New.ContainsKey($p)) { $isNested = $true; break }
            $p = Get-ParentRel $p
        }
        if (-not $isNested) { $result.RemovedDirs.Add($d) }
    }

    foreach ($f in @($removed | Where-Object { $Old[$_].T -eq 'F' })) {
        $underDeleted = $false
        foreach ($d in $result.RemovedDirs) {
            if ($f.StartsWith($d + '\', [System.StringComparison]::OrdinalIgnoreCase)) { $underDeleted = $true; break }
        }
        if (-not $underDeleted) { $result.RemovedFiles.Add($f) }
    }

    foreach ($d in @($added | Where-Object { $New[$_].T -eq 'D' })) { $result.AddedDirs.Add($d) }
    foreach ($f in @($added | Where-Object { $New[$_].T -eq 'F' })) { $result.AddedFiles.Add($f) }

    return $result
}

function Get-ChangeCount {
    param($ChangeSet)
    $n = $ChangeSet.AddedDirs.Count + $ChangeSet.AddedFiles.Count +
         $ChangeSet.RemovedDirs.Count + $ChangeSet.RemovedFiles.Count +
         $ChangeSet.UpdatedFiles.Count + $ChangeSet.FolderMoves.Count +
         $ChangeSet.FileMoves.Count + $ChangeSet.Archives.Count
    return $n
}

function ConvertTo-LogLines {
    param($ChangeSet, $Config, [string]$Drive)

    $lines = New-Object System.Collections.Generic.List[string]
    $style = [string]$Config.pathStyle

    # 1) 新建目录（父目录先于子目录）
    $dirs = @($ChangeSet.AddedDirs | Sort-Object @{ Expression = { ($_ -split '\\').Count } }, @{ Expression = { $_ } })
    foreach ($d in $dirs) {
        $parent = Get-ParentRel $d
        $line = 'CREATE FOLDER "{0}" AT "{1}"' -f (Get-LeafName $d), (Format-LogPath -Rel $parent -IsDir $true -Style $style -Drive $Drive)
        $lines.Add($line)
    }

    # 2) 目录改名/移动
    foreach ($m in $ChangeSet.FolderMoves) {
        $line = 'RENAME FOLDER "{0}" TO "{1}"' -f (Format-LogPath -Rel $m.Old -IsDir $true -Style $style -Drive $Drive),
                                              (Format-LogPath -Rel $m.New -IsDir $true -Style $style -Drive $Drive)
        $lines.Add($line)
    }

    # 3) 归档
    foreach ($a in $ChangeSet.Archives) {
        $line = 'ARCHIVE "{0}" TO {1}' -f (Format-LogPath -Rel $a.Dir -IsDir $true -Style $style -Drive $Drive), (Get-LeafName $a.File)
        $lines.Add($line)
    }

    # 4) 删除（目录在前，文件在后）
    foreach ($d in @($ChangeSet.RemovedDirs | Sort-Object)) {
        $lines.Add(('DELETE "{0}"' -f (Format-LogPath -Rel $d -IsDir $true -Style $style -Drive $Drive)))
    }
    foreach ($f in @($ChangeSet.RemovedFiles | Sort-Object)) {
        $lines.Add(('DELETE "{0}"' -f (Format-LogPath -Rel $f -IsDir $false -Style $style -Drive $Drive)))
    }

    # 5) 文件移动 / 改名
    foreach ($m in $ChangeSet.FileMoves) {
        $oldParent = Get-ParentRel $m.Old
        $newParent = Get-ParentRel $m.New
        if ($oldParent -ieq $newParent) {
            $line = 'RENAME "{0}" TO "{1}"' -f (Format-LogPath -Rel $m.Old -IsDir $false -Style $style -Drive $Drive),
                                              (Format-LogPath -Rel $m.New -IsDir $false -Style $style -Drive $Drive)
        }
        else {
            $line = 'MOVE "{0}" TO "{1}"' -f (Get-LeafName $m.Old), (Format-LogPath -Rel $newParent -IsDir $true -Style $style -Drive $Drive)
        }
        $lines.Add($line)
    }

    # 6) 上传（按目标目录分组；同目录同批图片达到阈值时合并成一条）
    $threshold = 0
    if ($Config.PSObject.Properties['aggregateImages']) { $threshold = [int]$Config.aggregateImages }

    $byDir = @{}
    foreach ($f in $ChangeSet.AddedFiles) {
        $parent = Get-ParentRel $f
        if (-not $byDir.ContainsKey($parent)) { $byDir[$parent] = New-Object System.Collections.Generic.List[string] }
        $byDir[$parent].Add($f)
    }

    foreach ($parent in ($byDir.Keys | Sort-Object)) {
        $files = $byDir[$parent]
        $images = @($files | Where-Object { Test-ImageName (Get-LeafName $_) })
        $others = @($files | Where-Object { -not (Test-ImageName (Get-LeafName $_)) })

        if ($threshold -gt 0 -and $images.Count -ge $threshold) {
            foreach ($f in ($others | Sort-Object)) {
                $lines.Add(('UPLOAD "{0}" TO "{1}"' -f (Get-LeafName $f), (Format-LogPath -Rel $parent -IsDir $true -Style $style -Drive $Drive)))
            }
            $lines.Add(('UPLOAD {0} image(s) TO "{1}"' -f $images.Count, (Format-LogPath -Rel $parent -IsDir $true -Style $style -Drive $Drive)))
        }
        else {
            foreach ($f in ($files | Sort-Object)) {
                $lines.Add(('UPLOAD "{0}" TO "{1}"' -f (Get-LeafName $f), (Format-LogPath -Rel $parent -IsDir $true -Style $style -Drive $Drive)))
            }
        }
    }

    $updates = @($ChangeSet.UpdatedFiles | Sort-Object @{ Expression = { Get-ParentRel $_ } }, @{ Expression = { $_ } })
    foreach ($f in $updates) {
        $parent = Get-ParentRel $f
        $lines.Add(('UPDATE "{0}" TO "{1}"' -f (Get-LeafName $f), (Format-LogPath -Rel $parent -IsDir $true -Style $style -Drive $Drive)))
    }

    return $lines
}

function Write-BackupLogBlock {
    param([string]$LogPath, [datetime]$When, [string]$Text)

    $stamp = $When.ToString('yyyy-MM-dd HH:mm')

    if (-not (Test-Path -LiteralPath $LogPath)) {
        $content = ('[{0}]' -f $stamp) + "`r`n" + $Text
        [System.IO.File]::WriteAllText($LogPath, $content, (New-Object System.Text.UTF8Encoding($false)))
        return
    }

    $existing = [System.IO.File]::ReadAllText($LogPath, [System.Text.Encoding]::UTF8)
    $lastHeader = ''
    $m = [regex]::Matches($existing, '\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2})\]')
    if ($m.Count -gt 0) { $lastHeader = $m[$m.Count - 1].Groups[1].Value }

    $sb = New-Object System.Text.StringBuilder
    if ($lastHeader -eq $stamp) {
        # 同一分钟内的多次扫描并入同一时间块，避免碎块
        [void]$sb.Append("`r`n")
        [void]$sb.Append($Text)
    }
    else {
        [void]$sb.Append("`r`n`r`n")
        [void]$sb.Append('[' + $stamp + ']')
        [void]$sb.Append("`r`n")
        [void]$sb.Append($Text)
    }

    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($sb.ToString())
    $fs = [System.IO.File]::Open($LogPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
    try { $fs.Write($bytes, 0, $bytes.Length) }
    finally { $fs.Close() }
}

function Backup-LogFile {
    param($Config, [string]$Root, [string]$LogPath)

    if (-not (Test-Path -LiteralPath $LogPath)) { return $null }

    $dir = Join-Path (Get-StateDirectory -Config $Config -Root $Root) 'backups'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $dest = Join-Path $dir ('Backup_Log-' + $stamp + '.log')
    Copy-Item -LiteralPath $LogPath -Destination $dest -Force

    $old = @(Get-ChildItem -LiteralPath $dir -Filter 'Backup_Log-*.log' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 10)
    foreach ($f in $old) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }

    return $dest
}

function Get-LocalStateDir {
    $d = Join-Path $env:LOCALAPPDATA 'BackupLog'
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    return $d
}

function Get-PauseFlagPaths {
    param($Config, [string]$Root)
    $driveFlag = Join-Path (Get-StateDirectory -Config $Config -Root $Root) 'paused'
    $localFlag = Join-Path (Get-LocalStateDir) 'paused'
    return @($driveFlag, $localFlag)
}

function Test-PauseFlag {
    param($Config, [string]$Root)
    foreach ($p in (Get-PauseFlagPaths -Config $Config -Root $Root)) {
        if (Test-Path -LiteralPath $p) { return $true }
    }
    return $false
}

function Set-PauseFlag {
    param($Config, [string]$Root, [bool]$Paused)
    $paths = Get-PauseFlagPaths -Config $Config -Root $Root
    if (-not $Paused) {
        foreach ($p in $paths) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } }
        return 'removed'
    }

    $stamp = (Get-Date).ToString('o')
    foreach ($p in $paths) {
        try {
            $dir = Split-Path $p -Parent
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [System.IO.File]::WriteAllText($p, $stamp, (New-Object System.Text.UTF8Encoding($false)))
            return $p
        }
        catch { continue }
    }
    throw '暂停标记写不进去（盘上和本机都被拒绝）'
}

function Enter-BackupLock {
    param($Config, [string]$Root)

    $dir = Get-StateDirectory -Config $Config -Root $Root
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $lock = Join-Path $dir 'scan.lock'

    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        try {
            $fs = [System.IO.File]::Open($lock, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $bytes = [System.Text.Encoding]::UTF8.GetBytes(('{0}|{1}' -f $PID, (Get-Date).ToString('o')))
            $fs.Write($bytes, 0, $bytes.Length)
            $fs.Close()
            return $lock
        }
        catch {
            $stale = $false
            $fi = Get-Item -LiteralPath $lock -ErrorAction SilentlyContinue
            if ($null -eq $fi) { continue }

            # 锁里记了 PID：那个进程已经不存在，说明是上次异常退出留下的，直接接管
            try {
                $content = [System.IO.File]::ReadAllText($lock, [System.Text.Encoding]::UTF8)
                $otherPid = [int](($content -split '\|')[0])
                if (-not (Get-Process -Id $otherPid -ErrorAction SilentlyContinue)) { $stale = $true }
            }
            catch { $stale = $true }

            if (-not $stale -and ((Get-Date) - $fi.LastWriteTime).TotalMinutes -gt 30) { $stale = $true }

            if ($stale) {
                Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
                continue
            }
            throw "另一个备份日志扫描正在运行（$lock）。若确认没有，用 -Action unlock 清理。"
        }
    }
    throw "无法获取扫描锁（$lock）"
}

function Exit-BackupLock {
    param([string]$LockPath)
    if ($LockPath -and (Test-Path -LiteralPath $LockPath)) {
        Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-BackupLogScan {
    param(
        [string]$Root,
        [string]$ConfigPath,
        [switch]$DryRun,
        [switch]$Force,
        [switch]$Reinit,
        [switch]$IgnorePause
    )

    $cfg = Read-BackupLogConfig -Path $ConfigPath
    $target = Resolve-BackupRoot -Config $cfg -Root $Root
    $drive = $target.Drive

    $logPath = Get-LogPath -Config $cfg -Root $target.Root

    # 暂停标记：GUI 写入 <盘>\.backup-log\paused，计划任务照常唤醒但什么都不做
    if (-not $IgnorePause -and -not $DryRun -and (Test-PauseFlag -Config $cfg -Root $target.Root)) {
        return [pscustomobject]@{
            Mode = 'paused'; Root = $target.Root; Drive = $drive; LogPath = $logPath
            Entries = 0; ChangeCount = 0; Lines = @(); Written = $false
            Message = '自动扫描已暂停（存在 paused 标记），本次未做任何事。'
        }
    }
    $state = $null
    if (-not $Reinit) { $state = Read-BackupState -Config $cfg -Root $target.Root }

    $lock = $null
    if (-not $DryRun) { $lock = Enter-BackupLock -Config $cfg -Root $target.Root }

    try {
        $now = Get-BackupSnapshot -Config $cfg -Root $target.Root

        if ($null -eq $state) {
            if ($DryRun) {
                return [pscustomobject]@{
                    Mode = 'baseline'; Root = $target.Root; Drive = $drive; LogPath = $logPath
                    Entries = $now.Count; Lines = @(); Written = $false; Message = '未建立基线（试运行不写入）'
                }
            }
            Save-BackupState -Config $cfg -Root $target.Root -Entries $now
            return [pscustomobject]@{
                Mode = 'baseline'; Root = $target.Root; Drive = $drive; LogPath = $logPath
                Entries = $now.Count; Lines = @(); Written = $false
                Message = ('已建立基线快照：{0} 个条目。之后再发生变化才会写入日志。' -f $now.Count)
            }
        }

        $changes = Compare-BackupSnapshot -Old $state.Entries -New $now -Config $cfg
        $changeCount = Get-ChangeCount -ChangeSet $changes

        $summary = [pscustomobject]@{
            Mode = 'scan'; Root = $target.Root; Drive = $drive; LogPath = $logPath
            Entries = $now.Count; ChangeCount = $changeCount
            AddedDirs = $changes.AddedDirs.Count; AddedFiles = $changes.AddedFiles.Count
            RemovedDirs = $changes.RemovedDirs.Count; RemovedFiles = $changes.RemovedFiles.Count
            UpdatedFiles = $changes.UpdatedFiles.Count; FolderMoves = $changes.FolderMoves.Count
            FileMoves = $changes.FileMoves.Count; Archives = $changes.Archives.Count
            Lines = @(); Written = $false; LogBackup = $null; Message = ''
        }

        if ($changeCount -eq 0) {
            if (-not $DryRun) { Save-BackupState -Config $cfg -Root $target.Root -Entries $now }
            $summary.Message = '没有检测到变化。'
            return $summary
        }

        $total = [Math]::Max(1, $state.Entries.Count)
        $percent = [Math]::Round(100.0 * $changeCount / $total, 1)
        $threshold = [Math]::Max(20, [int]($total * [double]$cfg.maxChangePercent / 100.0))
        if (-not $Force -and $changeCount -gt $threshold) {
            throw ("本次变化过大（{0} 项，占基线 {1}%，阈值 {2} 项），已中止以防误判。确认无误请加 -Force。" -f $changeCount, $percent, $threshold)
        }

        $lines = @(ConvertTo-LogLines -ChangeSet $changes -Config $cfg -Drive $drive)
        $summary.Lines = $lines
        $summary.ChangeCount = $changeCount

        if ($DryRun) {
            $summary.Message = ('试运行：将追加 {0} 条记录（未写入）。' -f $lines.Count)
            return $summary
        }

        $backup = Backup-LogFile -Config $cfg -Root $target.Root -LogPath $logPath
        Write-BackupLogBlock -LogPath $logPath -When (Get-Date) -Text ($lines -join "`r`n")
        Save-BackupState -Config $cfg -Root $target.Root -Entries $now

        $summary.Written = $true
        $summary.LogBackup = $backup
        $summary.Message = ('已追加 {0} 条记录到 {1}' -f $lines.Count, $logPath)
        return $summary
    }
    finally {
        if ($lock) { Exit-BackupLock -LockPath $lock }
    }
}
