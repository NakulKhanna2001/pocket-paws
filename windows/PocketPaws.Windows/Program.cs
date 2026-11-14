using System.Text.Json;
using PocketPaws.Core;

namespace PocketPaws.Windows;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        var smoke = args.Contains("--smoke-test");
        var reportIndex = Array.IndexOf(args, "--report");
        var report = reportIndex >= 0 && reportIndex + 1 < args.Length ? Path.GetFullPath(args[reportIndex + 1]) : null;
        var screenshotIndex = Array.IndexOf(args, "--screenshot");
        var screenshot = screenshotIndex >= 0 && screenshotIndex + 1 < args.Length ? Path.GetFullPath(args[screenshotIndex + 1]) : null;
        var testDirectory = Path.Combine(Path.GetTempPath(), "PocketPaws-smoke-" + Guid.NewGuid());
        void Report(bool success, string message)
        {
            Console.WriteLine(message);
            if (report is null) return;
            Directory.CreateDirectory(Path.GetDirectoryName(report)!);
            File.WriteAllText(report, JsonSerializer.Serialize(new { success, message }, new JsonSerializerOptions { WriteIndented = true }));
        }
        try
        {
            Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            using var instance = new Mutex(true, @"Local\PocketPaws.Windows", out var firstInstance);
            if (!smoke && !firstInstance)
            {
                NativeMethods.PostMessage(new nint(0xFFFF), NativeMethods.ShowSettingsMessage, 0, 0);
                return 0;
            }
            var animals = Animal.LoadBundled();
            var store = new PreferencesStore(smoke ? Path.Combine(testDirectory, "settings.json") : PreferencesStore.DefaultPath);
            using var context = new PawsContext(animals, store, showSettings: !smoke);
            var result = 0;
            using var check = new System.Windows.Forms.Timer { Interval = 500 };
            if (smoke)
            {
                check.Tick += (_, _) =>
                {
                    check.Stop();
                    try
                    {
                        context.SmokeCheck(screenshot);
                        Report(true, "PASS: Windows overlay, tray, 12 portraits, settings, Sprout-to-Maple migration, pause, and resume");
                    }
                    catch (Exception error) { result = 1; Report(false, error.ToString()); }
                    finally { context.ExitThread(); }
                };
                check.Start();
            }
            Application.Run(context);
            return result;
        }
        catch (Exception error)
        {
            if (smoke) Report(false, error.ToString());
            else MessageBox.Show(error.Message, "Pocket Paws could not start", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            if (smoke && Directory.Exists(testDirectory)) Directory.Delete(testDirectory, recursive: true);
        }
    }
}
