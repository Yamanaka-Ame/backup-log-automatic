# BackupLog.Gui.ps1
# 备份日志自动化 —— WPF 图形界面（状态、变更预览、设置、日志查看）
# 运行：powershell.exe -STA -ExecutionPolicy Bypass -File gui\BackupLog.Gui.ps1

param(
    [switch]$SelfTest,
    [switch]$NoTray
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:GuiLog = 'D:\hand-log-automatic\gui.log'
$projectRoot = Split-Path $PSScriptRoot -Parent
$libPath = Join-Path $projectRoot 'lib\BackupLog.Core.ps1'
$configPath = Join-Path $projectRoot 'config.json'
. $libPath

# ---------------------------------------------------------------- 基础工具

function Get-AppConfig {
    return (Read-BackupLogConfig -Path $configPath)
}

function Save-AppSetting {
    param([hashtable]$Values)
    $json = [System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8)
    $obj = $json | ConvertFrom-Json
    foreach ($k in $Values.Keys) {
        if ($obj.PSObject.Properties[$k]) { $obj.$k = $Values[$k] }
        else { $obj | Add-Member -NotePropertyName $k -NotePropertyValue $Values[$k] }
    }
    $out = $obj | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($configPath, $out, (New-Object System.Text.UTF8Encoding($false)))
}

function Test-AutoStart {
    $v = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'BackupLogAuto' -ErrorAction SilentlyContinue
    return ($null -ne $v)
}

function Set-AutoStart {
    param([bool]$Enabled)
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if ($Enabled) {
        $exe = Join-Path $projectRoot 'BackupLog.exe'
        $cmd = if (Test-Path -LiteralPath $exe) { '"{0}"' -f $exe }
        else { 'powershell.exe -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $PSScriptRoot 'BackupLog.Gui.ps1') }
        Set-ItemProperty -Path $key -Name 'BackupLogAuto' -Value $cmd
    }
    else {
        Remove-ItemProperty -Path $key -Name 'BackupLogAuto' -ErrorAction SilentlyContinue
    }
}

function Write-GuiLog {
    param([string]$Message)
    try {
        $line = ('{0} {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Message)
        Add-Content -LiteralPath $script:GuiLog -Value $line -Encoding UTF8
    }
    catch { }
}

# 启动自检：当前进程能不能写盘、能不能建锁
try {
    $cfgT = Get-AppConfig
    $tgtT = Resolve-BackupRoot -Config $cfgT
    $sd = Get-StateDirectory -Config $cfgT -Root $tgtT.Root
    $probe = Join-Path $sd '_probe.tmp'
    [System.IO.File]::WriteAllText($probe, 'x')
    Remove-Item -LiteralPath $probe -Force
    Write-GuiLog 'write-test: 磁盘 OK'
}
catch { Write-GuiLog ('write-test: 磁盘失败 ' + $_.Exception.Message) }
try {
    $lp = Join-Path $env:LOCALAPPDATA 'BackupLog'
    if (-not (Test-Path -LiteralPath $lp)) { New-Item -ItemType Directory -Path $lp -Force | Out-Null }
    [System.IO.File]::WriteAllText((Join-Path $lp '_probe.tmp'), 'x')
    Remove-Item -LiteralPath (Join-Path $lp '_probe.tmp') -Force
    Write-GuiLog 'write-test: LOCALAPPDATA OK'
}
catch { Write-GuiLog ('write-test: LOCALAPPDATA 失败 ' + $_.Exception.Message) }

Write-GuiLog ('boot pid=' + $PID + ' user=' + $env:USERNAME + ' session=' + [System.Diagnostics.Process]::GetCurrentProcess().SessionId + ' root=' + $env:SystemRoot + ' psmod=' + $(if ($env:PSModulePath) { 'yes' } else { 'no' }))

function Test-ScanPaused {
    try {
        $cfg = Get-AppConfig
        $target = Resolve-BackupRoot -Config $cfg
        return (Test-PauseFlag -Config $cfg -Root $target.Root)
    }
    catch { return $false }
}

function Get-ScanTask {
    # 不查询系统计划任务：GUI 只认「暂停标记」，避免受运行环境影响
    if (Test-ScanPaused) { return [pscustomobject]@{ State = 'Paused'; Paused = $true } }
    return [pscustomobject]@{ State = 'Ready'; Paused = $false }
}

function Set-ScanTask {
    param([bool]$Enabled, [int]$Minutes)
    $script = Join-Path $projectRoot 'tools\Install-Schedule.ps1'
    if ($Enabled) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -IntervalMinutes $Minutes | Out-Null
    }
    else {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Action uninstall | Out-Null
    }
}

function New-AppIcon {
    $icoFile = Join-Path $PSScriptRoot 'app.ico'
    if (Test-Path -LiteralPath $icoFile) {
        try { return (New-Object System.Drawing.Icon($icoFile)) }
        catch { Write-GuiLog ('载入 app.ico 失败：' + $_.Exception.Message) }
    }

    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.Clear([System.Drawing.Color]::Transparent)
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 79, 140, 255))
        $g.FillEllipse($brush, 0, 0, 31, 31)
        $font = New-Object System.Drawing.Font('Microsoft YaHei UI', 14, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment = [System.Drawing.StringAlignment]::Center
        $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
        $g.DrawString('备', $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF(0, 1, 32, 31)), $fmt)
        $brush.Dispose(); $font.Dispose()
        $h = $bmp.GetHicon()
        $icon = [System.Drawing.Icon]::FromHandle($h)
        return $icon.Clone()
    }
    finally { $g.Dispose(); $bmp.Dispose() }
}

function Invoke-CoreAsync {
    param([string]$Code)
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($Code)
    $handle = $ps.BeginInvoke()
    while ($ps.InvocationStateInfo.State -eq 'Running' -or $ps.InvocationStateInfo.State -eq 'NotStarted') {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 60
    }
    $state = $ps.InvocationStateInfo.State
    $err = $null
    if ($ps.Streams.Error.Count -gt 0) { $err = $ps.Streams.Error[0].Exception.Message }
    $result = $null
    try { $result = @($ps.EndInvoke($handle)) } catch { $err = $_.Exception.Message }
    $ps.Dispose(); $rs.Close(); $rs.Dispose()
    if ($err) { throw $err }
    if ($state -ne 'Completed') { throw ('执行失败：' + $state) }
    return $result
}

function ConvertTo-ChangeRows {
    param([string[]]$Lines)
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($line in $Lines) {
        $m = [regex]::Match($line, '^(CREATE FOLDER|RENAME FOLDER|UPLOAD|UPDATE|DELETE|MOVE|RENAME|ARCHIVE)\s+(.*)$')
        if ($m.Success) {
            $rows.Add([pscustomobject]@{ Action = $m.Groups[1].Value; Detail = $m.Groups[2].Value })
        }
        else {
            $rows.Add([pscustomobject]@{ Action = '其它'; Detail = $line })
        }
    }
    return $rows
}

# ---------------------------------------------------------------- 自检模式

if ($SelfTest) {
    $cfg = Get-AppConfig
    $target = Resolve-BackupRoot -Config $cfg
    $state = Read-BackupState -Config $cfg -Root $target.Root
    Write-Host ('盘符：{0}' -f $target.Drive)
    Write-Host ('根目录：{0}' -f $target.Root)
    Write-Host ('条目：{0}' -f $(if ($state) { $state.Entries.Count } else { 0 }))
    Write-Host ('日志：{0}' -f (Get-LogPath -Config $cfg -Root $target.Root))
    $task = Get-ScanTask
    Write-Host ('计划任务：{0}' -f $(if ($task) { $task.State } else { '未安装' }))
    Write-Host ('开机自启：{0}' -f (Test-AutoStart))
    $icon = New-AppIcon
    Write-Host ('图标：{0}x{1}' -f $icon.Width, $icon.Height)
    $preview = Invoke-CoreAsync -Code (". '$libPath'; Invoke-BackupLogScan -ConfigPath '$configPath' -DryRun")
    Write-Host ('试运行：{0}' -f $preview.Message)
    Write-Host '自检通过。'
    exit 0
}

# ---------------------------------------------------------------- 单实例

$mutex = New-Object System.Threading.Mutex($false, 'Local\BackupLogUiSelf')
if (-not $mutex.WaitOne(0)) {
    [System.Windows.Forms.MessageBox]::Show('备份日志自动化已经在运行。', '备份日志自动化') | Out-Null
    exit 0
}

# ---------------------------------------------------------------- 界面

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="备份日志自动化" Height="700" Width="1010" MinHeight="560" MinWidth="880"
        WindowStartupLocation="CenterScreen" Background="#F6F7F9"
        FontFamily="Microsoft YaHei UI" FontSize="13" Foreground="#1F2430">
  <Window.Resources>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="White"/>
      <Setter Property="BorderBrush" Value="#E3E6EB"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="10"/>
      <Setter Property="Padding" Value="18"/>
    </Style>
    <Style x:Key="PrimaryButton" TargetType="Button">
      <Setter Property="Background" Value="#4F8CFF"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="16,9"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="GhostButton" TargetType="Button" BasedOn="{StaticResource PrimaryButton}">
      <Setter Property="Background" Value="#EDF1F8"/>
      <Setter Property="Foreground" Value="#3B4658"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Padding" Value="8,6"/>
      <Setter Property="BorderBrush" Value="#D8DDE6"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Padding" Value="6,4"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="78"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="34"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="#1F2430">
      <Grid Margin="24,0">
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="备份日志自动化" Foreground="White" FontSize="20" FontWeight="SemiBold"/>
          <TextBlock Text="自动识别备份盘 · 追踪增删改移 · 追加写入 Backup_Log.log" Foreground="#98A2B3" FontSize="12" Margin="0,5,0,0"/>
        </StackPanel>
        <TextBlock x:Name="HeaderDrive" Text="" Foreground="#98A2B3" FontSize="12" HorizontalAlignment="Right" VerticalAlignment="Center"/>
      </Grid>
    </Border>

    <TabControl Grid.Row="1" Margin="14,12,14,10" Background="Transparent" BorderThickness="0">

      <TabItem Header="概览">
        <Grid Margin="6">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="360"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>

          <StackPanel Grid.Column="0" Margin="0,0,12,0">
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="当前备份盘" Foreground="#7A8494" FontSize="12"/>
                <TextBlock x:Name="DriveText" Text="识别中…" FontSize="26" FontWeight="SemiBold" Margin="0,2,0,14"/>
                <TextBlock x:Name="InfoText" Text="" Foreground="#4A5566" FontSize="12.5" LineHeight="24"/>
              </StackPanel>
            </Border>

            <Button x:Name="ScanBtn" Content="立即扫描并写入" Style="{StaticResource PrimaryButton}" Margin="0,12,0,0"/>
            <Button x:Name="PreviewBtn2" Content="只看会写什么（不写入）" Style="{StaticResource GhostButton}" Margin="0,8,0,0"/>
            <Button x:Name="TaskBtn" Content="暂停自动扫描" Style="{StaticResource GhostButton}" Margin="0,8,0,0"/>
          </StackPanel>

          <Border Grid.Column="1" Style="{StaticResource Card}">
            <DockPanel>
              <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,10">
                <TextBlock Text="最近一次结果" FontSize="14" FontWeight="SemiBold"/>
                <TextBlock x:Name="LastRunText" Text="" Foreground="#7A8494" FontSize="12" Margin="10,2,0,0"/>
              </StackPanel>
              <TextBox x:Name="ResultBox" IsReadOnly="True" TextWrapping="Wrap" VerticalContentAlignment="Top"
                       VerticalScrollBarVisibility="Auto" AcceptsReturn="True" FontFamily="Consolas" FontSize="12.5"
                       Background="#FAFBFD" BorderThickness="0" Padding="10"/>
            </DockPanel>
          </Border>
        </Grid>
      </TabItem>

      <TabItem Header="变更预览">
        <DockPanel Margin="6">
          <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,10">
            <Button x:Name="PreviewBtn" Content="预览变化" Style="{StaticResource PrimaryButton}"/>
            <Button x:Name="CommitBtn" Content="确认写入日志" Style="{StaticResource GhostButton}" Margin="8,0,0,0"/>
            <TextBlock x:Name="PreviewSummary" Text="" VerticalAlignment="Center" Margin="14,0,0,0" Foreground="#5A6472"/>
          </StackPanel>
          <Border Style="{StaticResource Card}" Padding="0">
            <DataGrid x:Name="ChangeGrid" AutoGenerateColumns="False" IsReadOnly="True" HeadersVisibility="Column"
                      GridLinesVisibility="Horizontal" HorizontalGridLinesBrush="#EFF2F6" BorderThickness="0"
                      RowHeaderWidth="0" Background="White" AlternatingRowBackground="#FAFBFD">
              <DataGrid.Columns>
                <DataGridTextColumn Header="动作" Binding="{Binding Action}" Width="150"/>
                <DataGridTextColumn Header="对象" Binding="{Binding Detail}" Width="*"/>
              </DataGrid.Columns>
            </DataGrid>
          </Border>
        </DockPanel>
      </TabItem>

      <TabItem Header="设置">
        <Border Style="{StaticResource Card}" Margin="6" Width="560" HorizontalAlignment="Left" VerticalAlignment="Top">
          <StackPanel>
            <TextBlock Text="自动扫描" FontSize="15" FontWeight="SemiBold" Margin="0,0,0,12"/>

            <CheckBox x:Name="AutoScanBox" Content="启用计划任务，定时自动扫描并写入" Margin="0,0,0,10"/>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,18">
              <TextBlock Text="扫描间隔（分钟）" VerticalAlignment="Center" Width="140"/>
              <TextBox x:Name="IntervalBox" Width="90"/>
            </StackPanel>

            <TextBlock Text="日志格式" FontSize="15" FontWeight="SemiBold" Margin="0,0,0,12"/>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
              <TextBlock Text="路径写法" VerticalAlignment="Center" Width="140"/>
              <ComboBox x:Name="PathStyleBox" Width="220">
                <ComboBoxItem Content="相对写法  :\网盘重要信息备份\…（与历史一致）" Tag="relative"/>
                <ComboBoxItem Content="绝对写法  G:\网盘重要信息备份\…" Tag="drive"/>
              </ComboBox>
            </StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
              <TextBlock Text="一次最多写入" VerticalAlignment="Center" Width="140"/>
              <TextBox x:Name="ThresholdBox" Width="90"/>
              <TextBlock Text="% 的条目，超出则中止" VerticalAlignment="Center" Margin="8,0,0,0" Foreground="#7A8494"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
              <TextBlock Text="识别压缩包归档" VerticalAlignment="Center" Width="140"/>
              <CheckBox x:Name="ArchiveBox" Content="开启（目录消失 + 出现压缩包时记 ARCHIVE）" VerticalAlignment="Center"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,18">
              <TextBlock Text="图片合并阈值" VerticalAlignment="Center" Width="140"/>
              <TextBox x:Name="AggregateBox" Width="90"/>
              <TextBlock Text="张：同一目录同批超过即合并为「UPLOAD N image(s)」，0 表示不合并" VerticalAlignment="Center" Margin="8,0,0,0" Foreground="#7A8494"/>
            </StackPanel>

            <TextBlock Text="启动" FontSize="15" FontWeight="SemiBold" Margin="0,0,0,12"/>
            <CheckBox x:Name="AutoStartBox" Content="开机时自动启动本程序" Margin="0,0,0,18"/>

            <StackPanel Orientation="Horizontal">
              <Button x:Name="SaveBtn" Content="保存设置" Style="{StaticResource PrimaryButton}"/>
              <TextBlock x:Name="SaveHint" Text="" VerticalAlignment="Center" Margin="12,0,0,0" Foreground="#2E9E5B"/>
            </StackPanel>
          </StackPanel>
        </Border>
      </TabItem>

      <TabItem Header="日志">
        <DockPanel Margin="6">
          <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,10">
            <Button x:Name="RefreshLogBtn" Content="刷新" Style="{StaticResource PrimaryButton}"/>
            <Button x:Name="OpenLogBtn" Content="用记事本打开" Style="{StaticResource GhostButton}" Margin="8,0,0,0"/>
            <TextBlock x:Name="LogPathText" Text="" VerticalAlignment="Center" Margin="14,0,0,0" Foreground="#7A8494" FontSize="12"/>
          </StackPanel>
          <Border Style="{StaticResource Card}" Padding="0">
            <TextBox x:Name="LogBox" IsReadOnly="True" TextWrapping="NoWrap" AcceptsReturn="True"
                     VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                     FontFamily="Consolas" FontSize="12.5" Background="White" BorderThickness="0" Padding="10"/>
          </Border>
        </DockPanel>
      </TabItem>
    </TabControl>

    <Border Grid.Row="2" Background="#EEF1F5" BorderBrush="#E1E5EC" BorderThickness="0,1,0,0">
      <Grid Margin="16,0">
        <TextBlock x:Name="StatusText" Text="就绪" VerticalAlignment="Center" Foreground="#5A6472" FontSize="12"/>
        <TextBlock x:Name="TaskStatusText" Text="" VerticalAlignment="Center" HorizontalAlignment="Right" Foreground="#7A8494" FontSize="12"/>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$ui = @{}
foreach ($name in @('DriveText', 'InfoText', 'HeaderDrive', 'ResultBox', 'LastRunText', 'StatusText', 'TaskStatusText',
        'ScanBtn', 'PreviewBtn', 'PreviewBtn2', 'CommitBtn', 'TaskBtn', 'ChangeGrid', 'PreviewSummary',
        'AutoScanBox', 'IntervalBox', 'PathStyleBox', 'ThresholdBox', 'ArchiveBox', 'AggregateBox', 'AutoStartBox', 'SaveBtn', 'SaveHint',
        'LogBox', 'LogPathText', 'RefreshLogBtn', 'OpenLogBtn')) {
    $ui[$name] = $window.FindName($name)
}

# ---------------------------------------------------------------- 状态刷新

function Update-Status {
    try {
        $cfg = Get-AppConfig
        $target = Resolve-BackupRoot -Config $cfg
        $state = Read-BackupState -Config $cfg -Root $target.Root
        $ui.DriveText.Text = $target.Drive
        $ui.HeaderDrive.Text = '备份盘 ' + $target.Drive + '   ' + $target.Root

        $lines = @()
        $lines += '根目录：' + $target.Root
        $lines += '日志：' + $cfg.logFile
        if ($state) {
            $lines += '基线时间：' + ([datetime]$state.CapturedAt).ToString('yyyy-MM-dd HH:mm')
            $lines += '基线条目：' + $state.Entries.Count
        }
        else {
            $lines += '基线：尚未建立（请点一次「立即扫描」）'
        }
        $task = Get-ScanTask
        $lines += '自动扫描：' + $(if ($task) { '已启用' } else { '已暂停' })
        $ui.InfoText.Text = ($lines -join "`n")
        $ui.TaskBtn.Content = $(if ($task) { '暂停自动扫描' } else { '恢复自动扫描' })
        $ui.TaskStatusText.Text = $(if ($task) { '计划任务运行中' } else { '计划任务已暂停' })
        Enable-Actions $true
    }
    catch {
        $ui.DriveText.Text = '未找到'
        $ui.InfoText.Text = $_.Exception.Message
        $ui.HeaderDrive.Text = ''
        $ui.TaskStatusText.Text = '未找到备份盘'
        Enable-Actions $false
    }
}

function Enable-Actions {
    param([bool]$On)
    foreach ($b in @($ui.ScanBtn, $ui.PreviewBtn, $ui.PreviewBtn2, $ui.CommitBtn, $ui.TaskBtn)) {
        $b.IsEnabled = $On
    }
}

function Update-TaskText {
    $cfg = Get-AppConfig
    $minutes = 15
    if ($cfg.PSObject.Properties['scanIntervalMinutes']) { $minutes = [int]$cfg.scanIntervalMinutes }
    if (Test-ScanPaused) {
        $ui.TaskStatusText.Text = '自动扫描已暂停'
    }
    else {
        $ui.TaskStatusText.Text = ('计划任务每 {0} 分钟自动扫描' -f $minutes)
    }
}

function Refresh-LogTail {
    try {
        $cfg = Get-AppConfig
        $target = Resolve-BackupRoot -Config $cfg
        $logPath = Get-LogPath -Config $cfg -Root $target.Root
        $ui.LogPathText.Text = $logPath
        if (Test-Path -LiteralPath $logPath) {
            $text = [System.IO.File]::ReadAllText($logPath, [System.Text.Encoding]::UTF8)
            $blocks = $text -split "`r`n`r`n"
            $tail = @($blocks | Select-Object -Last 12)
            $ui.LogBox.Text = ($tail -join "`r`n`r`n")
            $ui.LogBox.ScrollToEnd()
        }
        else {
            $ui.LogBox.Text = '（日志文件还不存在）'
        }
    }
    catch {
        $ui.LogBox.Text = '读取失败：' + $_.Exception.Message
    }
}

function Set-Busy {
    param([bool]$Busy, [string]$Text)
    $window.Cursor = if ($Busy) { [System.Windows.Input.Cursors]::Wait } else { [System.Windows.Input.Cursors]::Arrow }
    $ui.StatusText.Text = $Text
    $ui.ScanBtn.IsEnabled = -not $Busy
    $ui.PreviewBtn.IsEnabled = -not $Busy
    $ui.PreviewBtn2.IsEnabled = -not $Busy
    $ui.CommitBtn.IsEnabled = -not $Busy
    [System.Windows.Forms.Application]::DoEvents()
}

function Show-Balloon {
    param([string]$Title, [string]$Text)
    try {
        if ($script:notify -and $script:notify.Visible) {
            $script:notify.BalloonTipTitle = $Title
            $script:notify.BalloonTipText = $Text
            $script:notify.ShowBalloonTip(4000)
        }
    }
    catch { Write-GuiLog ('气泡提示失败：' + $_.Exception.Message) }
}

# ---------------------------------------------------------------- 动作

function Do-Scan {
    param([bool]$Dry)
    Set-Busy $true $(if ($Dry) { '正在比对变化…' } else { '正在扫描并写入…' })
    try {
    $code = ". '{0}'; Invoke-BackupLogScan -ConfigPath '{1}' -DryRun:`$$Dry -IgnorePause" -f $libPath, $configPath
        $r = Invoke-CoreAsync -Code $code
        $r = @($r)[0]

        $rows = ConvertTo-ChangeRows -Lines $r.Lines
        $ui.ChangeGrid.ItemsSource = $rows

        if ($Dry) {
            $ui.PreviewSummary.Text = $r.Message
            $ui.ResultBox.Text = (($r.Lines -join "`r`n") + "`r`n`r`n" + $r.Message)
            $ui.StatusText.Text = $r.Message
        }
        else {
            $ui.ResultBox.Text = (($r.Lines -join "`r`n") + "`r`n`r`n" + $r.Message)
            $ui.StatusText.Text = $r.Message
            $ui.LastRunText.Text = (Get-Date).ToString('HH:mm:ss')
            if ($r.Written) {
                Show-Balloon '备份日志已更新' ('已追加 ' + @($r.Lines).Count + ' 条记录')
            }
            Refresh-LogTail
            Update-Status
        }
    }
    catch {
        $ui.StatusText.Text = '失败：' + $_.Exception.Message
        $ui.ResultBox.Text = '执行失败：' + $_.Exception.Message
    }
    finally {
        Set-Busy $false $ui.StatusText.Text
        Update-TaskText
    }
}

$ui.ScanBtn.Add_Click({ Do-Scan -Dry $false })
$ui.PreviewBtn.Add_Click({ Do-Scan -Dry $true })
$ui.PreviewBtn2.Add_Click({ Do-Scan -Dry $true })

$ui.CommitBtn.Add_Click({
        try {
            Set-Busy $true '正在写入…'
            $code = ". '{0}'; Invoke-BackupLogScan -ConfigPath '{1}' -IgnorePause" -f $libPath, $configPath
            $r = @(Invoke-CoreAsync -Code $code)[0]
            $ui.ResultBox.Text = (($r.Lines -join "`r`n") + "`r`n`r`n" + $r.Message)
            $ui.StatusText.Text = $r.Message
            if ($r.Written) { Show-Balloon '备份日志已更新' ('已追加 ' + @($r.Lines).Count + ' 条记录') }
            $rows = ConvertTo-ChangeRows -Lines $r.Lines
            $ui.ChangeGrid.ItemsSource = $rows
            $ui.PreviewSummary.Text = $r.Message
            Refresh-LogTail
            Update-Status
        }
        catch { $ui.StatusText.Text = '失败：' + $_.Exception.Message }
        finally { Set-Busy $false $ui.StatusText.Text; Update-TaskText }
    })

$ui.TaskBtn.Add_Click({
        try {
            $cfg = Get-AppConfig
            $target = Resolve-BackupRoot -Config $cfg
            if (Test-ScanPaused) {
                $null = Set-PauseFlag -Config $cfg -Root $target.Root -Paused $false
                $ui.StatusText.Text = '已恢复自动扫描'
            }
            else {
                $null = Set-PauseFlag -Config $cfg -Root $target.Root -Paused $true
                $ui.StatusText.Text = '已暂停自动扫描'
            }
            Update-Status
            Update-TaskText
        }
        catch { $ui.StatusText.Text = '切换失败：' + $_.Exception.Message }
    })

$ui.SaveBtn.Add_Click({
        try {
            $minutes = [int]$ui.IntervalBox.Text
            $threshold = [int]$ui.ThresholdBox.Text
            if ($minutes -lt 1) { $minutes = 1 }
            if ($threshold -lt 1) { $threshold = 1 }

            $style = 'relative'
            if ($ui.PathStyleBox.SelectedItem -and $ui.PathStyleBox.SelectedItem.Tag) {
                $style = [string]$ui.PathStyleBox.SelectedItem.Tag
            }

            Save-AppSetting -Values @{
                scanIntervalMinutes = $minutes
                pathStyle           = $style
                maxChangePercent    = $threshold
                detectArchive       = [bool]$ui.ArchiveBox.IsChecked
                aggregateImages     = [int]$ui.AggregateBox.Text
                autoScan            = [bool]$ui.AutoScanBox.IsChecked
            }

            Set-AutoStart -Enabled ([bool]$ui.AutoStartBox.IsChecked)
            Set-ScanTask -Enabled ([bool]$ui.AutoScanBox.IsChecked) -Minutes $minutes

            $ui.SaveHint.Text = '已保存并生效 ' + (Get-Date).ToString('HH:mm:ss')
            $ui.StatusText.Text = '设置已保存'
            Update-Status
            Update-TaskText
        }
        catch {
            $ui.SaveHint.Foreground = [System.Windows.Media.Brushes]::IndianRed
            $ui.SaveHint.Text = '保存失败：' + $_.Exception.Message
        }
    })

$ui.RefreshLogBtn.Add_Click({ Refresh-LogTail })
$ui.OpenLogBtn.Add_Click({
        try {
            $cfg = Get-AppConfig
            $target = Resolve-BackupRoot -Config $cfg
            Start-Process notepad.exe -ArgumentList ('"' + (Get-LogPath -Config $cfg -Root $target.Root) + '"')
        }
        catch { $ui.StatusText.Text = '打开失败：' + $_.Exception.Message }
    })

# ---------------------------------------------------------------- 关闭行为
# 托盘已移除：点窗口右上角的 × 就是退出程序。
$script:notify = $null
# ---------------------------------------------------------------- 初始化

$cfg0 = Get-AppConfig
$ui.IntervalBox.Text = $(if ($cfg0.PSObject.Properties['scanIntervalMinutes']) { $cfg0.scanIntervalMinutes } else { 15 })
$ui.ThresholdBox.Text = [string]$cfg0.maxChangePercent
$ui.ArchiveBox.IsChecked = [bool]$cfg0.detectArchive
$ui.AggregateBox.Text = $(if ($cfg0.PSObject.Properties['aggregateImages']) { $cfg0.aggregateImages } else { 10 })
$ui.AutoScanBox.IsChecked = [bool](Get-ScanTask)
$ui.AutoStartBox.IsChecked = Test-AutoStart
if ($cfg0.pathStyle -eq 'drive') { $ui.PathStyleBox.SelectedIndex = 1 } else { $ui.PathStyleBox.SelectedIndex = 0 }

Write-GuiLog ("启动：user=" + $env:USERNAME + " session=" + [System.Diagnostics.Process]::GetCurrentProcess().SessionId + " task=" + [string]([bool](Get-ScanTask)))
Update-Status
Update-TaskText
Refresh-LogTail

$window.Add_Loaded({
        Write-GuiLog '主窗口已加载'
    })

$window.Dispatcher.Add_UnhandledException({
        param($sender, $args)
        Write-GuiLog ('界面异常：' + $args.Exception.Message)
        $args.Handled = $true
    })

# Show + Dispatcher.Run：窗口关闭时触发 Closed -> 结束调度器 -> 程序退出。
$window.Add_Closed({
        try { [System.Windows.Threading.Dispatcher]::CurrentDispatcher.InvokeShutdown() } catch { }
    })

$window.Show()
Write-GuiLog '窗口已显示'
[System.Windows.Threading.Dispatcher]::Run()
Write-GuiLog '调度器结束，程序退出'

if ($script:notify) { $script:notify.Visible = $false; $script:notify.Dispose() }
$mutex.ReleaseMutex()
$mutex.Dispose()
