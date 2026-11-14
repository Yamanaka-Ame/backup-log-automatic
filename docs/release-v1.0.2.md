# v1.0.2 — 静默运行，一键停用

## 修的问题

每次自动扫描都会闪一个 PowerShell 黑框，一分钟都不到，但一天几十次，很难忽略。

原因：计划任务直接用 `powershell.exe` 启动，而 Windows 在创建进程时就会先建控制台窗口，
`-WindowStyle Hidden` 只是事后把它藏起来，那一下闪烁躲不掉。

现在任务改成两级启动：

```
计划任务 → wscript.exe //B tools\RunScan.vbs → 隐藏窗口拉起 PowerShell
```

`wscript.exe` 本身是 GUI 子系统程序，不创建控制台，所以全程零闪烁。

## 加的功能

界面上的「停用自动扫描」原来只写一个 `paused` 标记——任务照常每 15 分钟醒来，看一眼标记再退出，
白白唤醒一次。

现在按钮直接操作计划任务：

- 点「停用」→ `schtasks /Change /DISABLE`，任务彻底不唤醒，零开销
- 点「启用」→ `/ENABLE` 恢复
- 状态从任务 XML 读取，不依赖系统语言

没有权限改计划任务的环境，会自动退回写标记的降级方案。

## 顺手修的判断错误

任务 XML 里**没有** `<Enabled>` 节点时表示「启用」，只有被停用才写 `<Enabled>false</Enabled>`。
之前的判断写反了，界面一打开就显示「已停用」。已修正。

## 升级

已有安装的计划任务还指向旧的启动方式，**需要重装一次**才能静默：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-Schedule.ps1 -IntervalMinutes 15
```

在图形界面「设置」页点一次保存，也会重新注册任务。数据与配置无需迁移。

---

**完整变更**：https://github.com/Yamanaka-Ame/backup-log-automatic/compare/v1.0.1...v1.0.2
