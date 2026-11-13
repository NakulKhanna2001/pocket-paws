namespace PocketPaws.Core;

public readonly record struct ScreenBounds(double X, double Y, double Width, double Height);
public readonly record struct PixelPoint(int X, int Y);

public static class Placement
{
    // Windows screen coordinates grow downward; secondary displays can start negative.
    public static PixelPoint Origin(double pointerX, double pointerY, int width, int height, ScreenBounds screen)
    {
        var x = pointerX + 12;
        var y = pointerY + 8;
        if (x + width > screen.X + screen.Width) x = pointerX - width - 12;
        if (y + height > screen.Y + screen.Height) y = pointerY - height - 8;
        x = Math.Clamp(x, screen.X, Math.Max(screen.X, screen.X + screen.Width - width));
        y = Math.Clamp(y, screen.Y, Math.Max(screen.Y, screen.Y + screen.Height - height));
        return new PixelPoint((int)Math.Round(x), (int)Math.Round(y));
    }
}
