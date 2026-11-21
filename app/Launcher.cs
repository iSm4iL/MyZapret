using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
static class Launcher {
    [STAThread] static void Main() {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "app", "builder-panel.ps1");
        if (!File.Exists(script)) script = Path.Combine(dir, "MyZapret", "app", "builder-panel.ps1");
        if (!File.Exists(script)) { MessageBox.Show("Не найден MyZapret/app/builder-panel.ps1", "MyZapret"); return; }
        var info = new ProcessStartInfo("powershell.exe", "-NoProfile -STA -ExecutionPolicy Bypass -File \"" + script + "\"");
        info.UseShellExecute = false; info.CreateNoWindow = true; info.RedirectStandardError = true;
        try { using (var process = Process.Start(info)) {
            string errors = process.StandardError.ReadToEnd(); process.WaitForExit();
            if (process.ExitCode != 0) {
                File.WriteAllText(Path.Combine(dir, "launcher-error.txt"), errors);
                MessageBox.Show(errors, "MyZapret — ошибка запуска");
            }
        } } catch (Exception e) { MessageBox.Show(e.Message, "MyZapret"); }
    }
}
