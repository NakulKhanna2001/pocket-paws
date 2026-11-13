using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using PocketPaws.Core;

namespace PocketPaws.Windows;

internal static class SpriteImages
{
    internal static Bitmap Bitmap(SpriteFrame frame)
    {
        var image = new Bitmap(frame.Width, frame.Height, PixelFormat.Format32bppArgb);
        var data = image.LockBits(new Rectangle(0, 0, image.Width, image.Height), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        try
        {
            var pixels = frame.Argb.Select(pixel => unchecked((int)pixel)).ToArray();
            for (var y = 0; y < frame.Height; y++)
                Marshal.Copy(pixels, y * frame.Width, data.Scan0 + y * data.Stride, frame.Width);
        }
        finally { image.UnlockBits(data); }
        return image;
    }

    internal static void Draw(Graphics graphics, Bitmap image, Rectangle target)
    {
        graphics.InterpolationMode = InterpolationMode.NearestNeighbor;
        graphics.PixelOffsetMode = PixelOffsetMode.Half;
        graphics.SmoothingMode = SmoothingMode.None;
        graphics.DrawImage(image, target, 0, 0, image.Width, image.Height, GraphicsUnit.Pixel);
    }

    internal static Bitmap Portrait(Animal animal)
    {
        using var source = Bitmap(SpriteRenderer.Render(animal, Pose.Idle, 0));
        var image = new Bitmap(source.Width * 2, source.Height * 2);
        using var graphics = Graphics.FromImage(image);
        Draw(graphics, source, new Rectangle(Point.Empty, image.Size));
        return image;
    }

    internal static Icon Icon(Animal animal)
    {
        using var source = Bitmap(SpriteRenderer.Render(animal, Pose.Idle, 0));
        using var image = new Bitmap(32, 32);
        using (var graphics = Graphics.FromImage(image))
            Draw(graphics, source, new Rectangle(0, 0, 32, 32));
        var handle = image.GetHicon();
        try
        {
            using var borrowed = System.Drawing.Icon.FromHandle(handle);
            return (Icon)borrowed.Clone();
        }
        finally { NativeMethods.DestroyIcon(handle); }
    }
}
