# 更新日志

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [v1.0.1] - 2026-11-11

让「陌生人下载下来就能用」成立的一次更新。核心逻辑没有改动，只是把第一次使用的门槛拆掉了。

### 新增

- **首次使用向导 `setup.cmd`**：双击即可，自动完成
  - 解除从 ZIP 解压出来的脚本「来自网络」锁定（不用手动 `Unblock-File`）
  - 列出所有可用磁盘（卷标、剩余空间、是否已有日志），选一块作为备份盘
  - 盘根没有 `Backup_Log.log` 就创建一个（带 `LOG RECORD STARTED` 起始块），已存在则原样保留
  - 写入 `config.json`、建立基线
  - 询问是否安装计划任务（默认 15 分钟）与桌面/开始菜单快捷方式
- 向导支持非交互调用：`setup.cmd -Drive G: -Yes -NoTask -NoShortcut`

### 改进

- README 顶部改成**三步开始**（下载 → 解压 → 双击），并补上 License / PowerShell / 平台 徽章
- 默认的盘符识别条件从「日志文件 + 特定目录名」放宽为只认 `Backup_Log.log`，别人拿到即可运行；想更严格可自行添加目录名

### 文档

- 新增 `docs/release-v1.0.0.md`：仓库 About、发帖用短文、博客引子、Release 正文四份文案

### 内部

- 新增 GitHub Actions 工作流 `.github/workflows/test.yml`：在 `windows-latest` 上跑 31 项自动化测试，失败时上传测试目录作为 artifact

### 升级说明

无破坏性改动。已有安装不需要迁移：配置文件与 `.backup-log\` 状态继续有效。
只想用新向导的话，把 `setup.cmd` 和 `tools\Setup.ps1` 拷过去即可。

---

## [v1.0.0] - 2026-11-11

首个版本。

- 自动识别备份盘（不写死盘符），快照对比后按既有格式追加日志
- 追踪新增 / 修改 / 删除 / 目录改名 / 文件移动 / 文件改名 / 归档七类动向
- 目录改名按子树内容指纹判断，不会误报成「删了又传」
- 同目录同批图片超过阈值合并为 `UPLOAD N image(s)`
- 安全设计：首次静默建基线、阈值保护、写前备份日志、并发锁（按 PID 判断僵尸锁）、真试运行
- WPF 图形界面（概览 / 变更预览 / 设置 / 日志）+ 命令行 + 计划任务
- 31 项假盘自动化测试

[v1.0.1]: https://github.com/Yamanaka-Ame/backup-log-automatic/releases/tag/v1.0.1
[v1.0.0]: https://github.com/Yamanaka-Ame/backup-log-automatic/releases/tag/v1.0.0
