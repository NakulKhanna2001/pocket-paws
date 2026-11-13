using System.Runtime.InteropServices;
using PocketPaws.Core;

namespace PocketPaws.Windows;

internal static class NativeMethods
{
    internal const int WsExLayered = 0x80000;
    internal const int WsExTransparent = 0x20;
    internal const int WsExToolWindow = 0x80;
    internal const int WsExNoActivate = 0x08000000;
    internal static readonly uint ShowSettingsMessage = RegisterWindowMessage("PocketPaws.ShowSettings");
    internal delegate nint HookProc(int code, nint message, nint data);

    [DllImport("user32.dll")] internal static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] internal static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] internal static extern uint GetDpiForWindow(nint window);
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SetWindowPos(nint window, nint after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern uint RegisterWindowMessage(string message);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool PostMessage(nint window, uint message, nint wParam, nint lParam);
    [DllImport("user32.dll", SetLastError = true)]
    internal static extern nint SetWindowsHookEx(int type, HookProc callback, nint module, uint threadId);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UnhookWindowsHookEx(nint hook);
    [DllImport("user32.dll")] internal static extern nint CallNextHookEx(nint hook, int code, nint message, nint data);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] internal static extern nint GetModuleHandle(string? name);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool DestroyIcon(nint icon);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    internal static extern nint GetWindowLongPtr(nint window, int index);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SystemParametersInfo(uint action, uint parameter, [MarshalAs(UnmanagedType.Bool)] out bool value, uint flags);

    internal static bool ReducedMotion => SystemParametersInfo(0x1042, 0, out var animated, 0) && !animated;
    internal static int MouseButtons()
    {
        // GetAsyncKeyState reports physical buttons. Respect Windows' handedness setting.
        var swapped = GetSystemMetrics(23) != 0;
        var left = (GetAsyncKeyState(swapped ? 2 : 1) & 0x8000) != 0;
        var right = (GetAsyncKeyState(swapped ? 1 : 2) & 0x8000) != 0;
        return (left ? 1 : 0) | (right ? 2 : 0);
    }
}

/// <summary>Retains very short clicks between timer samples; never consumes events.</summary>
internal sealed class MouseMonitor : IDisposable
{
    private readonly NativeMethods.HookProc callback;
    private nint handle;

    internal MouseMonitor(Action<Gesture> onDown)
    {
        callback = (code, message, data) =>
        {
            if (code >= 0)
            {
                try
                {
                    if (message == 0x0201) onDown(Gesture.LeftClick);
                    else if (message == 0x0204) onDown(Gesture.RightClick);
                }
                catch (Exception error) { System.Diagnostics.Debug.WriteLine(error); }
            }
            return NativeMethods.CallNextHookEx(handle, code, message, data);
        };
        handle = NativeMethods.SetWindowsHookEx(14, callback, NativeMethods.GetModuleHandle(null), 0);
        // Button polling continues to work if this session doesn't allow a mouse hook.
    }

    public void Dispose()
    {
        if (handle != 0) NativeMethods.UnhookWindowsHookEx(handle);
        handle = 0;
        GC.KeepAlive(callback);
    }
}
