# v1.0.1 — 下载下来就能用

这次没有动核心逻辑，专门解决「第一次使用」的门槛。

## 之前的问题

陌生人拿到仓库，会卡在三件事上：

1. 不知道从哪下手——README 一上来就是 `-Action init`，但盘上没有 `Backup_Log.log`，认不出盘，直接报「未找到备份盘」
2. ZIP 下载的脚本带「来自网络」标记，执行策略可能拦下
3. 没有双击入口，`.ps1` 双击是用记事本打开的

## 现在

新增 **首次使用向导 `setup.cmd`**，双击就行：

- 自动解除所有脚本的下载锁定
- 列出机器上所有可用磁盘（卷标、剩余空间、是否已有日志）
- 选盘后：没有日志就创建一个（带 `LOG RECORD STARTED` 起始块），已存在则一个字节都不动
- 写配置、建基线
- 顺带问你要不要装计划任务（默认 15 分钟）和桌面快捷方式

整个流程三步：**下载 ZIP → 解压 → 双击 `setup.cmd`**。

也支持非交互，便于批处理：`setup.cmd -Drive G: -Yes -NoTask -NoShortcut`

## 顺带改的

- README 顶部换成三步图，加了 License / PowerShell / 平台 徽章
- 默认识别条件放宽为只认 `Backup_Log.log`，别人拿到能直接跑
- 新增 GitHub Actions：每次推送在 `windows-latest` 上跑 31 项测试
- 新增本仓库的文案集 `docs/release-v1.0.0.md`

## 升级

无破坏性改动。已有的配置和 `.backup-log\` 状态继续有效，不需要迁移。

只想用新向导：把 `setup.cmd` 和 `tools\Setup.ps1` 拷到现有目录即可。

---

**完整变更**：https://github.com/Yamanaka-Ame/backup-log-automatic/compare/v1.0.0...v1.0.1

区间内 3 个提交：

- `d9aa89f` 首次使用向导 setup.cmd（选盘 / 建日志 / 建基线 / 装任务）
- `85a5225` GitHub Actions 测试工作流、README 徽章与三步开始
- `f0f6996` CHANGELOG 与本次更新说明

逐版本明细见 [CHANGELOG.md](../CHANGELOG.md)。
