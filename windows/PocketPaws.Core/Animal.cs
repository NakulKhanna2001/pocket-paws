using System.Globalization;
using System.Text.Json;

namespace PocketPaws.Core;

public sealed class Animal
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    public required string Species { get; init; }
    public required string Personality { get; init; }
    public required string Accent { get; init; }
    public required Dictionary<string, string> Palette { get; init; }
    public required string[] Pixels { get; init; }
    public string[]? SidePixels { get; init; }
    public int EyeRow { get; init; }
    public required int[] EyeColumns { get; init; }
    public int Width => Pixels.Length > 0 ? Pixels[0].Length : 0;
    public int Height => Pixels.Length;

    public void Validate()
    {
        void Require(bool condition, string message)
        {
            if (!condition) throw new InvalidDataException($"{Id}: {message}");
        }
        Require(!string.IsNullOrWhiteSpace(Id) && !string.IsNullOrWhiteSpace(Name)
            && !string.IsNullOrWhiteSpace(Species), "Missing identity");
        Require(Width is >= 8 and <= 48 && Height is >= 8 and <= 48
            && Pixels.All(row => row.Length == Width), "Invalid sprite dimensions");
        Require(Palette.Keys.All(key => key.Length == 1 && key != ".")
            && new[] { "o", "b", "e" }.All(Palette.ContainsKey), "Invalid palette");
        Require(Palette.Values.Append(Accent).All(hex => hex.Length == 6
            && uint.TryParse(hex, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out _)), "Invalid RGB color");
        if (SidePixels is not null)
            Require(SidePixels.Length == Height && SidePixels.All(row => row.Length == Width), "Invalid side profile");
        Require(Pixels.Concat(SidePixels ?? []).SelectMany(row => row)
            .All(pixel => pixel == '.' || Palette.ContainsKey(pixel.ToString())), "Missing pixel color");
        Require(EyeRow >= 0 && EyeRow < Height && EyeColumns.Length == 2
            && EyeColumns.Distinct().Count() == 2
            && EyeColumns.All(x => x >= 1 && x < Width - 1 && Pixels[EyeRow][x] == 'e'), "Invalid eye coordinates");
    }

    public static IReadOnlyList<Animal> LoadBundled()
    {
        var assembly = typeof(Animal).Assembly;
        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        var animals = new List<Animal>();
        var ids = new HashSet<string>(StringComparer.Ordinal);
        foreach (var name in assembly.GetManifestResourceNames()
                     .Where(name => name.StartsWith("Animals.") && name.EndsWith(".json"))
                     .Order(StringComparer.Ordinal))
        {
            using var stream = assembly.GetManifestResourceStream(name)!;
            var animal = JsonSerializer.Deserialize<Animal>(stream, options)
                ?? throw new InvalidDataException($"Empty animal: {name}");
            animal.Validate();
            if (!ids.Add(animal.Id)) throw new InvalidDataException($"Duplicate animal: {animal.Id}");
            animals.Add(animal);
        }
        if (animals.Count == 0) throw new InvalidDataException("Bundled animals are missing");
        return animals;
    }
}
