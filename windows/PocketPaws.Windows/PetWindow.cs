using PocketPaws.Core;

namespace PocketPaws.Windows;

internal sealed class PetWindow : Form
{
    private Bitmap? sprite;
    internal event Action? SettingsRequested;
    protected override bool ShowWithoutActivation => true;
    protected override CreateParams CreateParams
    {
        get
        {
            var parameters = base.CreateParams;
            parameters.ExStyle |= NativeMethods.WsExLayered | NativeMethods.WsExTransparent
                | NativeMethods.WsExToolWindow | NativeMethods.WsExNoActivate;
            return parameters;
        }
    }

    internal PetWindow()
    {
        Text = "Pocket Paws companion";
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        BackColor = TransparencyKey = Color.Magenta;
        AutoScaleMode = AutoScaleMode.None;
        StartPosition = FormStartPosition.Manual;
        DoubleBuffered = true;
        SetStyle(ControlStyles.Selectable, false);
        _ = Handle;
    }

    internal void SetSprite(SpriteFrame frame)
    {
        var previous = sprite;
        sprite = SpriteImages.Bitmap(frame);
        previous?.Dispose();
        Invalidate();
    }

    internal void Place(PixelPoint origin, int width, int height)
    {
        if (Bounds != new Rectangle(origin.X, origin.Y, width, height))
            NativeMethods.SetWindowPos(Handle, new nint(-1), origin.X, origin.Y, width, height, 0x0010);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        if (sprite is not null) SpriteImages.Draw(e.Graphics, sprite, ClientRectangle);
    }

    protected override void WndProc(ref Message message)
    {
        if ((uint)message.Msg == NativeMethods.ShowSettingsMessage) { SettingsRequested?.Invoke(); return; }
        if (message.Msg == 0x0084) { message.Result = new nint(-1); return; } // HTTRANSPARENT
        if (message.Msg == 0x0021) { message.Result = new nint(3); return; } // MA_NOACTIVATE
        base.WndProc(ref message);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) sprite?.Dispose();
        base.Dispose(disposing);
    }
}
