# v1.0.4 — 补完 v1.0.3 的修复

## 一句话

v1.0.3 的修法只做对了一半，点「立即扫描并写入」还是会报 `执行失败：参数类型不匹配`。这个版本才是真正修好的。

## 发生了什么

v1.0.3 里我改了两处：

```powershell
return , $rows                          # 对：保住 List，避免单元素被解包
$ui.ChangeGrid.ItemsSource = @($rows)   # 错：@() 反而把它炸了
```

`@()` 对 `List[object]`（元素是 `PSObject`）做数组子表达式时，PowerShell 会抛
`ArgumentException: Argument types do not match`，中文即「参数类型不匹配」。

实测对照：

| 写法 | 结果 |
| --- | --- |
| `$dg.ItemsSource = $rows`（直接给 List） | 正常 |
| `$dg.ItemsSource = @($rows)` | ArgumentException |
| `$dg.ItemsSource = [ArrayList]@($rows)` | ArgumentException |

## 现在的做法

```powershell
return , $rows
$ui.ChangeGrid.ItemsSource = $rows
```

点击实测：

```
最近一次结果  22:29:52
没有检测到变化。
```

## 升级

不需要重装计划任务，**关掉界面重新打开**即可。

## 关于 v1.0.3

v1.0.3 的界面修复不完整，**建议直接使用 v1.0.4，跳过 v1.0.3**。

---

**完整变更**：https://github.com/Yamanaka-Ame/backup-log-automatic/compare/v1.0.3...v1.0.4
