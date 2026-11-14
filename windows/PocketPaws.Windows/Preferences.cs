using System.Text.Json;
using System.Text.Json.Serialization;
using PocketPaws.Core;

namespace PocketPaws.Windows;

internal sealed class Preferences
{
    public string AnimalId { get; set; } = "mochi";
    public int PixelSize { get; set; } = 2;
    public bool Enabled { get; set; } = true;
    public bool Naps { get; set; } = true;
    public bool ReducedMotion { get; set; }
    public Dictionary<Gesture, Pose> Mappings { get; set; } = [];

    internal void Normalize(IReadOnlyList<Animal> animals)
    {
        if (AnimalId == "sprout" && animals.Any(animal => animal.Id == "maple")) AnimalId = "maple";
        if (!animals.Any(animal => animal.Id == AnimalId)) AnimalId = animals[0].Id;
        PixelSize = Math.Clamp(PixelSize, 1, 3);
        Mappings ??= [];
        Mappings = Enum.GetValues<Gesture>().ToDictionary(gesture => gesture, gesture =>
            Mappings.TryGetValue(gesture, out var pose) && Reactions.Choices.Contains(pose) ? pose : Reactions.Default(gesture));
    }
}

internal sealed class PreferencesStore(string path)
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };
    internal static string DefaultPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PocketPaws", "settings.json");

    internal Preferences Load(IReadOnlyList<Animal> animals)
    {
        Preferences preferences;
        try { preferences = File.Exists(path) ? JsonSerializer.Deserialize<Preferences>(File.ReadAllText(path), Options) ?? new() : new(); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException) { preferences = new(); }
        preferences.Normalize(animals);
        return preferences;
    }

    internal void Save(Preferences preferences)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(preferences, Options));
        File.Move(temporary, path, overwrite: true);
    }
}
