// Launcher.cs —— 备份日志自动化的单文件启动器
// 用系统自带 csc.exe 编译：/target:winexe /win32icon:app.ico
//
// 职责只有两件：单实例互斥（双击第二次时提示已在运行）、以无控制台窗口的方式
// 拉起 WPF 界面脚本。没有托盘图标——关闭窗口就是退出程序。

using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Windows.Forms;

static class Program
{
    [STAThread]
    static void Main()
    {
        bool created;
        using (var mutex = new Mutex(true, @"Local\BackupLogGui", out created))
        {
            if (!created)
            {
                MessageBox.Show("备份日志自动化已经在运行。", "备份日志自动化",
                    MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(baseDir, @"gui\BackupLog.Gui.ps1");
            if (!File.Exists(script)) script = Path.Combine(baseDir, "BackupLog.Gui.ps1");
            if (!File.Exists(script))
            {
                MessageBox.Show("找不到 gui\\BackupLog.Gui.ps1，请把程序放在项目根目录下运行。",
                    "启动失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            var psi = new ProcessStartInfo("powershell.exe",
                "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\"");
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WorkingDirectory = baseDir;

            try
            {
                using (var proc = Process.Start(psi))
                {
                    proc.WaitForExit();
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("启动失败：" + ex.Message, "备份日志自动化",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
            }

            GC.KeepAlive(mutex);
        }
    }
}
