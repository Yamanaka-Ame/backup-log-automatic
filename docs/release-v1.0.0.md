# 发布介绍 · v1.0.0

几份不同长度的文案，按场景取用：仓库 About、发帖、Release 正文。

---

## 一句话（仓库 About / 标题）

> 把备份盘里发生的每次新增、修改、删除、改名，自动记成一份能读的日志。

英文版：

> Auto-generate a human-readable change log for your backup drive.

---

## 三句话（发帖 / 朋友圈 / 群）

我有个习惯：重要东西往一块盘里备份，顺手记下「哪天传了什么」。记了两年，一忙就断更。

所以写了个小工具：它盯着这块盘，你只管往里面放东西，日志自己长出来——新增、修改、删除、改名、
打包归档，全按你原来的格式往后追加，历史一行不动。

Windows 原生的 PowerShell 加 WPF，不用装运行环境，双击就能用。

---

## 长版（博客开头 / README 引子）

**手写的备份日志，最后都会断更。**

不是因为懒。是因为这件事的性价比太低：备份本身只要拖一下文件，而记账要回忆、要打字、要统一格式，
真正有价值的时刻（半年后想找「那次到底删了什么」）又离得很远。

这个工具的想法很简单：**既然盘上的变化是客观存在的，那就别让人去记，让程序去比对。**

它会给备份盘拍一张快照，下次扫描时和上一张比：多了什么、少了什么、谁改了、谁改了名。
然后把结论按你原本的日志格式追加进去——你手写的那套 `[2026-11-11 22:08]` 加
`UPLOAD xxx TO ":\..."`，一行都不用改。

它甚至知道你「把文件夹改了名」而不是「删了 30 个文件又传了 30 个文件」，因为改名前后的子树内容是一样的；
也知道「这个目录被打包成 zip 了」而不是「删掉了」；同一批传进去的 50 张照片会合并成一条
`UPLOAD 50 image(s)`，不至于把日志刷爆。

不依赖任何云服务。日志就是一个文本文件，想改就改，想看就看。

---

## GitHub Release 正文（v1.0.0）

### 备份盘变动自动记账 v1.0.0

给备份盘自动生成人类可读的变更日志：扫描 → 对比快照 → 追加记录。历史日志原样保留，只往后写。

#### 它能记什么

- `CREATE FOLDER` / `UPLOAD` — 新目录、新文件
- `UPDATE` — 同名文件大小或时间变了
- `DELETE` — 目录消失只记一条，不再罗列里面的几十个文件
- `RENAME FOLDER` / `MOVE` / `RENAME` — 改名和搬家，靠子树内容指纹判断，不会误报成「删了又传」
- `ARCHIVE` — 目录消失且同目录出现体积对得上的压缩包
- `UPLOAD N image(s)` — 同目录同批图片达到阈值时合并成一条

#### 几个刻意的设计

- **不写死盘符**：盘根有 `Backup_Log.log` 的那块就是备份盘，换电脑换盘符不用改配置
- **首次静默**：第一次只建基线，不会把盘上现有几千个文件当成「新增」灌进日志
- **阈值保护**：单次变化超过基线 40% 就中止，防止认错盘或同步软件整盘重刷
- **写前备份**：每次追加前把日志复制到 `.backup-log\backups\`，留最近 10 份
- **真试运行**：`-DryRun` 只打印将写什么，不落盘
- **并发锁**：锁里记 PID，进程没了自动接管

#### 怎么用

```powershell
# 认盘（只读）
powershell -NoProfile -ExecutionPolicy Bypass -File .\backup-log.ps1 -Action detect

# 建基线（只跑一次）
powershell -NoProfile -ExecutionPolicy Bypass -File .\backup-log.ps1 -Action init

# 之后每 15 分钟自动跑
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-Schedule.ps1 -IntervalMinutes 15
```

图形界面：运行 `gui\BackupLog.Gui.ps1`，或先跑 `gui\install.ps1` 建快捷方式。

#### 环境要求

Windows 10 / 11，系统自带的 PowerShell 5.1。没有第三方依赖，不需要装 .NET SDK 或 Node。

#### 已知限制

- 改名同时改了内容，会退化成 `DELETE + UPLOAD`
- 内容变了但大小和时间戳都没变（某些同步客户端会保留时间戳）检测不到
- 文件夹只记创建、删除、改名，单独修改文件夹时间不写日志

#### 测试

假盘上的 31 项自动化测试，覆盖七类动向、格式（CRLF / 无 BOM / 块间空行）、幂等性、阈值保护：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

---

## 发布检查清单

- [ ] 仓库 About 填上面那句话，Topics：`backup` `powershell` `wpf` `windows` `automation` `logging`
- [ ] Releases → Draft a new release → tag `v1.0.0` → 粘贴上面的 Release 正文
- [ ] 可选：加 GitHub Actions，在 `windows-latest` 上跑 `tests\Run-Tests.ps1`
