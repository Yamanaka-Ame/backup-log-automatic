# v1.0.3 — 修掉「只有一条变更就报错」

## 问题

变更只有一条时，点「立即扫描并写入」会弹错误：

```
执行失败：设置"ItemsSource"时发生异常:
无法将"System.Management.Automation.PSObject"类型的值转换为
"System.Collections.IEnumerable"类型。
```

多条变更时一切正常，只有一条时必现。

## 原因

PowerShell 的函数返回集合时会**逐元素输出**。返回一个只有 1 个元素的列表时，这个元素会被解包成单个对象，调用方拿到的不再是集合。

而 `DataGrid.ItemsSource` 需要一个 `IEnumerable`，传单个对象进去就炸了。

之前的测试里总是 3 条以上变更，所以一直没暴露。

## 修法

两处一起加固：

```powershell
return , $rows                          # 逗号阻止 PowerShell 解包
$ui.ChangeGrid.ItemsSource = @($rows)   # 赋值处再兜一层
```

对照验证：

| 写法 | 返回类型 | 赋给 DataGrid |
| --- | --- | --- |
| `return $l`（单元素） | `PSCustomObject` | 报错 |
| `return , $l` | `List<T>` | 正常 |
| `return $l` + `@()` | `Object[]` | 正常 |

## 升级

不需要重装计划任务，**关掉界面重新打开**就生效。

---

**完整变更**：https://github.com/Yamanaka-Ame/backup-log-automatic/compare/v1.0.2...v1.0.3
