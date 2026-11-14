using System.Diagnostics;
using Microsoft.Win32;
using PocketPaws.Core;

namespace PocketPaws.Windows;

internal sealed class PawsContext : ApplicationContext
{
    private readonly IReadOnlyList<Animal> animals;
    private readonly PreferencesStore store;
    private readonly Preferences preferences;
    private readonly GestureEngine engine = new();
    private readonly Stopwatch clock = Stopwatch.StartNew();
    private readonly PetWindow pet = new();
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 16 };
    private readonly NotifyIcon tray;
    private readonly ContextMenuStrip menu = new();
    private readonly ToolStripMenuItem pause = new("Pause companion");
    private readonly ToolStripMenuItem steps = new("Preview steps");
    private readonly SettingsWindow settings;
    private MouseMonitor? monitor;
    private Icon trayIcon;
    private bool exiting;
    private bool sessionSuspended;
    private bool powerSuspended;
    private bool systemReducedMotion;
    private double nextMotionCheck;
    private int lastFrame = -1;
    private string lastAnimal = "";
    private Pose lastPose = Pose.Idle;
    private bool lastReduced;
    private Pose previewPose;
    private double previewUntil;
    internal Animal Animal => animals.First(a => a.Id == preferences.AnimalId);

    internal PawsContext(IReadOnlyList<Animal> animals, PreferencesStore store, bool showSettings)
    {
        this.animals = animals;
        this.store = store;
        preferences = store.Load(animals);
        trayIcon = SpriteImages.Icon(Animal);
        tray = new NotifyIcon { Icon = trayIcon, Text = "Pocket Paws", Visible = true, ContextMenuStrip = menu };
        settings = new SettingsWindow(animals, preferences, SavePreferences, Preview, ExitThread);
        menu.Items.Add("Choose your friend…", null, (_, _) => ShowSettings());
        menu.Items.Add(pause);
        pause.Click += (_, _) => { preferences.Enabled = !preferences.Enabled; SavePreferences(); settings.RefreshPreferences(); };
        menu.Items.Add(steps);
        steps.Click += (_, _) => Preview(Pose.Walk);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit Pocket Paws", null, (_, _) => ExitThread());
        tray.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) ShowSettings(); };
        pet.SettingsRequested += ShowSettings;
        timer.Tick += (_, _) => Tick();
        SystemEvents.SessionSwitch += SessionChanged;
        SystemEvents.PowerModeChanged += PowerChanged;
        ApplyPreferences();
        if (showSettings) ShowSettings();
    }

    private void ShowSettings()
    {
        settings.RefreshPreferences();
        settings.Show();
        settings.WindowState = FormWindowState.Normal;
        settings.Activate();
    }

    private void SavePreferences()
    {
        try { store.Save(preferences); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            tray.ShowBalloonTip(3000, "Pocket Paws", "Your selection works, but preferences could not be saved: " + error.Message, ToolTipIcon.Warning);
        }
        ApplyPreferences();
    }

    private void ApplyPreferences()
    {
        engine.Mappings = preferences.Mappings;
        engine.NapsEnabled = preferences.Naps;
        pause.Text = preferences.Enabled ? "Pause companion" : "Resume companion";
        steps.Enabled = preferences.Enabled;
        var tooltip = $"Pocket Paws — {Animal.Name}";
        tray.Text = tooltip[..Math.Min(tooltip.Length, 63)];
        var oldIcon = trayIcon;
        trayIcon = SpriteImages.Icon(Animal);
        tray.Icon = trayIcon;
        oldIcon.Dispose();
        UpdateTracking();
    }

    private void UpdateTracking()
    {
        if (exiting) return;
        if (preferences.Enabled && !sessionSuspended && !powerSuspended)
        {
            if (timer.Enabled) return;
            engine.Reset();
            Tick();
            monitor = new MouseMonitor(gesture => engine.ReactTo(gesture, clock.Elapsed.TotalSeconds));
            pet.Show();
            timer.Start();
        }
        else
        {
            timer.Stop();
            monitor?.Dispose();
            monitor = null;
            pet.Hide();
            engine.Reset();
            settings.SetActivity(Pose.Idle);
        }
    }

    private void Preview(Pose pose)
    {
        previewPose = pose;
        previewUntil = clock.Elapsed.TotalSeconds + 1.2;
    }

    private void Tick()
    {
        var now = clock.Elapsed.TotalSeconds;
        var pointer = Cursor.Position;
        if (now >= nextMotionCheck)
        {
            systemReducedMotion = NativeMethods.ReducedMotion;
            nextMotionCheck = now + 1;
        }
        var reduced = preferences.ReducedMotion || systemReducedMotion;
        var pose = engine.Update(new PointerSample(pointer.X, pointer.Y, NativeMethods.MouseButtons(), now));
        if (now < previewUntil) pose = previewPose;
        var frame = reduced ? 0 : (int)(now * 8);
        var animal = Animal;
        var scale = Math.Max(1, (int)Math.Round(preferences.PixelSize * NativeMethods.GetDpiForWindow(pet.Handle) / 96.0, MidpointRounding.AwayFromZero));
        var width = (animal.Width + 8) * scale;
        var height = (animal.Height + 10) * scale;
        var screen = Screen.FromPoint(pointer).Bounds;
        var origin = Placement.Origin(pointer.X, pointer.Y, width, height,
            new ScreenBounds(screen.X, screen.Y, screen.Width, screen.Height));
        pet.Place(origin, width, height);
        if (frame != lastFrame || pose != lastPose || animal.Id != lastAnimal || reduced != lastReduced)
        {
            pet.SetSprite(SpriteRenderer.Render(animal, pose, frame, reduced));
            settings.SetActivity(pose);
            lastFrame = frame;
            lastPose = pose;
            lastAnimal = animal.Id;
            lastReduced = reduced;
        }
    }

    private void OnUi(Action action)
    {
        if (!exiting && pet.IsHandleCreated)
        {
            try { pet.BeginInvoke(() => { if (!exiting) action(); }); }
            catch (InvalidOperationException) { /* The message loop is shutting down. */ }
        }
    }

    private void SessionChanged(object sender, SessionSwitchEventArgs e) => OnUi(() =>
    {
        if (e.Reason is SessionSwitchReason.SessionLock or SessionSwitchReason.ConsoleDisconnect or SessionSwitchReason.RemoteDisconnect)
            sessionSuspended = true;
        else if (e.Reason is SessionSwitchReason.SessionUnlock or SessionSwitchReason.ConsoleConnect or SessionSwitchReason.RemoteConnect)
            sessionSuspended = false;
        UpdateTracking();
    });

    private void PowerChanged(object sender, PowerModeChangedEventArgs e) => OnUi(() =>
    {
        if (e.Mode == PowerModes.Suspend) powerSuspended = true;
        else if (e.Mode == PowerModes.Resume) powerSuspended = false;
        UpdateTracking();
    });

    internal void SmokeCheck(string? screenshotPath)
    {
        void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
        var styles = NativeMethods.GetWindowLongPtr(pet.Handle, -20).ToInt64();
        Require((styles & NativeMethods.WsExTransparent) != 0 && (styles & NativeMethods.WsExNoActivate) != 0
            && (styles & NativeMethods.WsExLayered) != 0, "Overlay window styles are incorrect");
        Require(tray.Visible && pet.Visible && timer.Enabled, "Desktop companion did not start");
        ShowSettings();
        foreach (var animal in animals)
        {
            preferences.AnimalId = animal.Id;
            ApplyPreferences();
            Tick();
            using var bitmap = SpriteImages.Portrait(animal);
            Require(bitmap.Width > 0, "Could not render portrait");
        }
        preferences.AnimalId = "sprout";
        store.Save(preferences);
        Require(store.Load(animals).AnimalId == "maple", "Sprout selection did not migrate to Maple");
        preferences.AnimalId = "maple";
        preferences.PixelSize = 3;
        store.Save(preferences);
        var restored = store.Load(animals);
        Require(restored.AnimalId == "maple" && restored.PixelSize == 3, "Preferences did not round-trip");
        preferences.Enabled = false;
        ApplyPreferences();
        Require(!pet.Visible && !timer.Enabled && monitor is null, "Pause did not stop tracking");
        preferences.Enabled = true;
        ApplyPreferences();
        Require(pet.Visible && timer.Enabled, "Resume did not restart tracking");
        if (screenshotPath is not null)
        {
            settings.RefreshPreferences();
            settings.Update();
            Directory.CreateDirectory(Path.GetDirectoryName(screenshotPath)!);
            using var screenshot = new Bitmap(settings.Width, settings.Height);
            settings.DrawToBitmap(screenshot, new Rectangle(Point.Empty, settings.Size));
            screenshot.Save(screenshotPath, System.Drawing.Imaging.ImageFormat.Png);
        }
    }

    protected override void ExitThreadCore()
    {
        if (!exiting)
        {
            exiting = true;
            SystemEvents.SessionSwitch -= SessionChanged;
            SystemEvents.PowerModeChanged -= PowerChanged;
            timer.Stop();
            timer.Dispose();
            monitor?.Dispose();
            tray.Visible = false;
            tray.Dispose();
            menu.Dispose();
            trayIcon.Dispose();
            settings.Dispose();
            pet.Dispose();
        }
        base.ExitThreadCore();
    }
}
