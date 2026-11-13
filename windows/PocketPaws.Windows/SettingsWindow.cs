using PocketPaws.Core;

namespace PocketPaws.Windows;

internal sealed class SettingsWindow : Form
{
    private static readonly Color Ink = Color.FromArgb(53, 72, 62);
    private static readonly Color Green = Color.FromArgb(85, 122, 91);
    private readonly Preferences preferences;
    private readonly IReadOnlyList<Animal> animals;
    private readonly Action changed;
    private readonly Dictionary<string, Button> cards = [];
    private readonly Dictionary<Gesture, ComboBox> mappings = [];
    private readonly List<Bitmap> portraits = [];
    private readonly List<Button> previewButtons = [];
    private readonly CheckBox enabled = new() { Text = "Show my desktop friend", AutoSize = true };
    private readonly CheckBox naps = new() { Text = "Sleepy when idle", AutoSize = true };
    private readonly CheckBox calm = new() { Text = "Calmer animations", AutoSize = true };
    private readonly ComboBox size = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 130 };
    private readonly Label personality = new() { AutoSize = true, MaximumSize = new Size(420, 0) };
    private readonly Label activity = new() { AutoSize = true, ForeColor = Green };
    private bool refreshing;

    internal SettingsWindow(IReadOnlyList<Animal> animals, Preferences preferences, Action changed,
                            Action<Pose> preview, Action quit)
    {
        this.animals = animals;
        this.preferences = preferences;
        this.changed = changed;
        Text = "Pocket Paws";
        AutoScaleDimensions = new SizeF(96, 96);
        AutoScaleMode = AutoScaleMode.Dpi;
        Font = new Font("Segoe UI", 10);
        BackColor = Color.FromArgb(251, 250, 245);
        ForeColor = Ink;
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(480, 790);
        Icon = SpriteImages.Icon(animals[0]);

        var root = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill, AutoScroll = true, FlowDirection = FlowDirection.TopDown,
            WrapContents = false, Padding = new Padding(20)
        };
        Controls.Add(root);
        void Add(Control control) { control.Margin = new Padding(0, 0, 0, 12); root.Controls.Add(control); }
        Add(new Label { Text = "pocket paws", AutoSize = true, Font = new Font("Segoe UI", 26, FontStyle.Bold), ForeColor = Green });
        Add(new Label { Text = "LITTLE FRIEND. EVERYWHERE YOU GO.  /  WINDOWS", AutoSize = true, Font = new Font("Segoe UI", 8) });
        Add(enabled);
        Add(new Label { Text = "Choose your little friend", AutoSize = true, Font = new Font(Font, FontStyle.Bold) });

        var animalGrid = new FlowLayoutPanel { Width = 420, AutoSize = true, MaximumSize = new Size(420, 0), WrapContents = true };
        foreach (var animal in animals)
        {
            var image = SpriteImages.Portrait(animal);
            portraits.Add(image);
            var button = new Button
            {
                Width = 96, Height = 118, Margin = new Padding(4), FlatStyle = FlatStyle.Flat,
                Image = image, Text = $"{animal.Name}\n{animal.Species}",
                TextImageRelation = TextImageRelation.ImageAboveText,
                AccessibleName = $"Choose {animal.Name} the {animal.Species}", Cursor = Cursors.Hand
            };
            button.FlatAppearance.BorderSize = 1;
            button.Click += (_, _) => { preferences.AnimalId = animal.Id; Commit(); preview(Pose.Hop); };
            cards[animal.Id] = button;
            animalGrid.Controls.Add(button);
        }
        Add(animalGrid);
        Add(personality);

        var sizeRow = new FlowLayoutPanel { Width = 420, Height = 36, WrapContents = false };
        size.Items.AddRange(["Small", "Medium", "Large"]);
        sizeRow.Controls.Add(new Label { Text = "Little, or a little bigger?", Width = 180, AutoSize = false, Height = 30, TextAlign = ContentAlignment.MiddleLeft });
        sizeRow.Controls.Add(size);
        var steps = new Button { Text = "Preview steps", AutoSize = true, FlatStyle = FlatStyle.Flat };
        steps.Click += (_, _) => preview(Pose.Walk);
        previewButtons.Add(steps);
        Add(sizeRow);
        Add(steps);
        Add(new Label { Text = "A little personality", AutoSize = true, Font = new Font(Font, FontStyle.Bold) });

        foreach (var gesture in Enum.GetValues<Gesture>())
        {
            var row = new FlowLayoutPanel { Width = 420, Height = 36, WrapContents = false };
            row.Controls.Add(new Label { Text = gesture.Title(), Width = 150, Height = 30, TextAlign = ContentAlignment.MiddleLeft });
            var choices = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 140, FormattingEnabled = true };
            choices.Format += (_, e) => { if (e.ListItem is Pose pose) e.Value = pose.Title(); };
            choices.DataSource = Reactions.Choices.ToArray();
            choices.AccessibleName = $"{gesture.Title()} reaction";
            choices.SelectedIndexChanged += (_, _) =>
            {
                if (refreshing || choices.SelectedItem is not Pose pose) return;
                preferences.Mappings[gesture] = pose;
                Commit();
                preview(pose);
            };
            mappings[gesture] = choices;
            row.Controls.Add(choices);
            var play = new Button { Text = "Preview", Width = 84, Height = 30, AccessibleName = $"Preview {gesture.Title()}" };
            play.Click += (_, _) => preview(preferences.Mappings[gesture]);
            previewButtons.Add(play);
            row.Controls.Add(play);
            Add(row);
        }
        var reset = new Button { Text = "Reset reactions", AutoSize = true };
        reset.Click += (_, _) => { preferences.Mappings = Enum.GetValues<Gesture>().ToDictionary(g => g, Reactions.Default); Commit(); };
        Add(reset);
        Add(naps);
        Add(calm);
        Add(new Label { Text = "A quiet companion beside your pointer.\nHold for 0.45 seconds to crouch; idle for 6 seconds to nap.", AutoSize = true, MaximumSize = new Size(420, 0) });
        Add(activity);
        var quitButton = new Button { Text = "Quit Pocket Paws", AutoSize = true };
        quitButton.Click += (_, _) => quit();
        Add(quitButton);

        enabled.CheckedChanged += (_, _) => { if (!refreshing) { preferences.Enabled = enabled.Checked; Commit(); } };
        naps.CheckedChanged += (_, _) => { if (!refreshing) { preferences.Naps = naps.Checked; Commit(); } };
        calm.CheckedChanged += (_, _) => { if (!refreshing) { preferences.ReducedMotion = calm.Checked; Commit(); } };
        size.SelectedIndexChanged += (_, _) => { if (!refreshing && size.SelectedIndex >= 0) { preferences.PixelSize = size.SelectedIndex + 1; Commit(); } };
        FormClosing += (_, e) => { if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); } };
        Shown += (_, _) =>
        {
            var area = Screen.FromControl(this).WorkingArea;
            Height = Math.Min(Height, area.Height - 32);
            Top = Math.Clamp(Top, area.Top, Math.Max(area.Top, area.Bottom - Height));
        };
        RefreshPreferences();
    }

    private void Commit() { changed(); RefreshPreferences(); }

    internal void RefreshPreferences()
    {
        refreshing = true;
        try
        {
            enabled.Checked = preferences.Enabled;
            naps.Checked = preferences.Naps;
            calm.Checked = preferences.ReducedMotion;
            size.SelectedIndex = preferences.PixelSize - 1;
            foreach (var (id, card) in cards)
            {
                card.BackColor = id == preferences.AnimalId ? Color.FromArgb(237, 242, 230) : Color.White;
                card.FlatAppearance.BorderColor = id == preferences.AnimalId ? Green : Color.FromArgb(229, 232, 222);
            }
            foreach (var (gesture, choices) in mappings) choices.SelectedItem = preferences.Mappings[gesture];
            foreach (var button in previewButtons) button.Enabled = preferences.Enabled;
            var animal = animals.First(a => a.Id == preferences.AnimalId);
            personality.Text = $"{animal.Name} — {animal.Personality}";
        }
        finally { refreshing = false; }
    }

    internal void SetActivity(Pose pose) => activity.Text = preferences.Enabled ? $"Right beside your pointer · {pose.Title()}" : "Taking a break";

    protected override bool ProcessCmdKey(ref Message message, Keys keyData)
    {
        if (keyData == Keys.Escape) { Hide(); return true; }
        return base.ProcessCmdKey(ref message, keyData);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { foreach (var portrait in portraits) portrait.Dispose(); Icon?.Dispose(); }
        base.Dispose(disposing);
    }
}
