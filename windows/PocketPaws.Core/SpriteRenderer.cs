using System.Globalization;

namespace PocketPaws.Core;

public sealed record SpriteFrame(int Width, int Height, uint[] Argb);

/// <summary>Integer-pixel rasterizer. No platform graphics APIs or image dependencies.</summary>
public static class SpriteRenderer
{
    private readonly record struct Foot(int Left, int Right, int Top, int Bottom)
    {
        public bool Contains(int x, int y) => x >= Left && x <= Right && y >= Top && y <= Bottom;
    }

    private static Foot[] Feet(string[] pixels)
    {
        var ground = Array.FindLastIndex(pixels, row => row.Any(c => c != '.'));
        if (ground < 0) return [];
        var spans = new List<(int Left, int Right)>();
        int? start = null;
        var row = pixels[ground];
        for (var x = 0; x <= row.Length; x++)
        {
            if (x < row.Length && row[x] != '.') start ??= x;
            else if (start is { } first) { spans.Add((first, x - 1)); start = null; }
        }
        if (spans.Count != 2) return [];
        var middle = (spans[0].Right + spans[1].Left) / 2;
        return [
            new(Math.Max(0, spans[0].Left - 1), Math.Min(middle, spans[0].Right + 1), Math.Max(0, ground - 1), ground),
            new(Math.Max(middle + 1, spans[1].Left - 1), Math.Min(row.Length - 1, spans[1].Right + 1), Math.Max(0, ground - 1), ground)
        ];
    }

    public static SpriteFrame Render(Animal animal, Pose pose, int frame, bool reducedMotion = false)
    {
        var tick = reducedMotion ? 0 : Math.Abs(frame % 40_000);
        var walking = pose == Pose.Walk && !reducedMotion;
        var feet = walking ? Feet(animal.Pixels) : [];
        var bob = pose switch
        {
            Pose.Walk when walking => new[] { 0, -1, -1, 0, -1, -1 }[tick % 6],
            Pose.Hop => new[] { 0, -2, -4, -5, -4, -2 }[tick % 6],
            Pose.Boop => tick % 4 < 2 ? 1 : 0,
            _ => 0
        };
        var squish = pose is Pose.Crouch or Pose.Sleep ? 0.79 : 1;
        static int Round(double value) => (int)Math.Round(value, MidpointRounding.AwayFromZero);
        var startY = 5 + Round((1 - squish) * animal.Height) + bob;
        var width = animal.Width + 8;
        var height = animal.Height + 10;
        var buffer = new uint[width * height];
        var colors = animal.Palette.ToDictionary(pair => pair.Key[0],
            pair => 0xFF000000u | uint.Parse(pair.Value, NumberStyles.HexNumber, CultureInfo.InvariantCulture));

        void Pixel(int x, int y, uint color, int w = 1, int h = 1)
        {
            var top = startY + Round(y * squish);
            var bottom = Math.Max(top + 1, startY + Round((y + h) * squish));
            for (var py = Math.Max(0, top); py < Math.Min(height, bottom); py++)
                for (var px = Math.Max(0, x + 4); px < Math.Min(width, x + 4 + w); px++)
                    buffer[py * width + px] = color;
        }

        for (var y = 0; y < animal.Height; y++)
            for (var x = 0; x < animal.Width; x++)
                if (!feet.Any(foot => foot.Contains(x, y)) && colors.TryGetValue(animal.Pixels[y][x], out var color))
                    Pixel(x, y, color);

        int[] stride = [-1, 0, 1, 1, 0, -1];
        int[] lift = [0, 0, -1, -1, -1, 0];
        for (var index = 0; index < feet.Length; index++)
        {
            var foot = feet[index];
            var phase = (tick + index * 3) % 6;
            var dx = stride[phase];
            var dy = lift[phase] - bob;
            for (var x = foot.Left; x <= foot.Right; x++)
            {
                if (dy > 0 && colors.TryGetValue(animal.Pixels[foot.Top][x], out var ankle))
                    Pixel(x + dx, foot.Top, ankle, h: dy);
                for (var y = foot.Top; y <= foot.Bottom; y++)
                    if (colors.TryGetValue(animal.Pixels[y][x], out var color)) Pixel(x + dx, y + dy, color);
            }
        }
        var eye = colors['e'];
        var body = colors['b'];
        var outline = colors['o'];
        var blink = pose == Pose.Sleep || (pose == Pose.Idle && tick % 40 >= 38);
        if (blink || pose == Pose.Wink)
            for (var index = 0; index < animal.EyeColumns.Length; index++)
            {
                if (!blink && index != 1) continue;
                var x = animal.EyeColumns[index];
                var eyelid = colors.GetValueOrDefault(animal.Pixels[animal.EyeRow][x - 1], body);
                Pixel(x, animal.EyeRow, eyelid);
                Pixel(x - 1, animal.EyeRow + 1, eye, w: 2);
            }
        if (pose == Pose.Boop)
        {
            Pixel(animal.Width - 7, animal.Height - 10, outline, 3, 3);
            Pixel(animal.Width - 7, animal.Height - 10, body, 2, 2);
            Pixel(animal.Width - 2, 7, 0xFFD9A65F);
            Pixel(animal.Width - 3, 8, 0xFFD9A65F, w: 3);
            Pixel(animal.Width - 2, 9, 0xFFD9A65F);
        }
        if (pose == Pose.Carry)
        {
            var middle = animal.Width / 2;
            Pixel(middle - 3, animal.Height - 8, outline, 6, 5);
            Pixel(middle - 2, animal.Height - 7, 0xFFD6B477, 4, 3);
            Pixel(middle, animal.Height - 7, 0xFFFFF0CE, h: 3);
            Pixel(middle - 4, animal.Height - 7, body, 2, 2);
            Pixel(middle + 2, animal.Height - 7, body, 2, 2);
        }
        if (pose == Pose.Sleep)
        {
            var x = animal.Width - 4;
            var y = tick % 12 < 6 ? 0 : -1;
            Pixel(x, y, outline, w: 3);
            Pixel(x + 1, y + 1, outline);
            Pixel(x, y + 2, outline, w: 3);
        }
        if (pose == Pose.Wink)
        {
            Pixel(animal.Width - 3, 5, 0xFFDC929E);
            Pixel(animal.Width - 1, 5, 0xFFDC929E);
            Pixel(animal.Width - 3, 6, 0xFFDC929E, w: 3);
            Pixel(animal.Width - 2, 7, 0xFFDC929E);
        }
        return new SpriteFrame(width, height, buffer);
    }
}
