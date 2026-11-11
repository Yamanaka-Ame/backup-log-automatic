# build-exe.ps1
# 用系统自带的 csc.exe 把启动器编译成单文件 BackupLog.exe（不需要安装 .NET SDK）。

[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$guiDir = $PSScriptRoot
$root = Split-Path $guiDir -Parent
if (-not $OutputPath) { $OutputPath = Join-Path $root 'BackupLog.exe' }

$csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) {
    $csc = Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path -LiteralPath $csc)) { throw '找不到 csc.exe（需要 .NET Framework 4.x）' }

# 生成图标
$ico = Join-Path $guiDir 'app.ico'
if (-not (Test-Path -LiteralPath $ico)) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 79, 140, 255))
    $g.FillEllipse($brush, 0, 0, 31, 31)
    $font = New-Object System.Drawing.Font('Microsoft YaHei UI', 14, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $g.DrawString('备', $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF(0, 1, 32, 31)), $fmt)
    $h = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($h)
    $fs = [System.IO.File]::Create($ico)
    $icon.Save($fs)
    $fs.Close()
    $g.Dispose(); $bmp.Dispose(); $brush.Dispose(); $font.Dispose()
}

$source = Join-Path $guiDir 'Launcher.cs'
if (Test-Path -LiteralPath $OutputPath) { Remove-Item -LiteralPath $OutputPath -Force }

$cscArgs = @(
    '/nologo'
    '/target:winexe'
    '/optimize+'
    ('/out:"{0}"' -f $OutputPath)
    ('/win32icon:"{0}"' -f $ico)
    '/r:System.dll'
    '/r:System.Windows.Forms.dll'
    '/r:System.Drawing.dll'
    ('"{0}"' -f $source)
)

& $csc $cscArgs
if ($LASTEXITCODE -ne 0) { throw "编译失败（csc 退出码 $LASTEXITCODE）" }

$exe = Get-Item $OutputPath
Write-Host ('已生成：{0}（{1} KB）' -f $exe.FullName, [math]::Round($exe.Length / 1KB, 1))
