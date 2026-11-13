namespace PocketPaws.Core;

public enum Pose { Idle, Walk, Boop, Wink, Crouch, Hop, Carry, Sleep }
public enum Gesture { LeftClick, RightClick, LongPress, Drag }

public static class Reactions
{
    public static readonly Pose[] Choices = [Pose.Boop, Pose.Wink, Pose.Crouch, Pose.Hop, Pose.Carry];
    public static Pose Default(Gesture gesture) => gesture switch
    {
        Gesture.LeftClick => Pose.Boop,
        Gesture.RightClick => Pose.Wink,
        Gesture.LongPress => Pose.Crouch,
        Gesture.Drag => Pose.Carry,
        _ => throw new ArgumentOutOfRangeException(nameof(gesture))
    };
    public static string Title(this Pose pose) => pose switch
    {
        Pose.Idle => "Blink", Pose.Walk => "Little steps", Pose.Boop => "Paw tap",
        Pose.Wink => "Wink", Pose.Crouch => "Crouch", Pose.Hop => "Happy hop",
        Pose.Carry => "Grab", Pose.Sleep => "Nap", _ => pose.ToString()
    };
    public static string Title(this Gesture gesture) => gesture switch
    {
        Gesture.LeftClick => "Left click", Gesture.RightClick => "Right click",
        Gesture.LongPress => "Press & hold", Gesture.Drag => "Drag", _ => gesture.ToString()
    };
}

public readonly record struct PointerSample(double X, double Y, int Buttons, double Time);

/// <summary>Matches the Mac gesture behavior, independently of Windows input and drawing.</summary>
public sealed class GestureEngine
{
    public Dictionary<Gesture, Pose> Mappings { get; set; } = [];
    public bool NapsEnabled { get; set; } = true;
    private PointerSample? previous;
    private double lastActivity;
    private double lastMovement = double.NegativeInfinity;
    private double? pressStarted;
    private (double X, double Y)? pressOrigin;
    private bool dragging;
    private (Pose Pose, double Until)? transient;

    public void Reset()
    {
        previous = null;
        pressStarted = null;
        pressOrigin = null;
        transient = null;
        dragging = false;
        lastMovement = double.NegativeInfinity;
    }

    public void ReactTo(Gesture gesture, double time)
    {
        transient = (Mapped(gesture), time + 0.30);
        lastActivity = time;
    }

    private Pose Mapped(Gesture gesture) => Mappings.GetValueOrDefault(gesture, Reactions.Default(gesture));
    private static double Distance(double x, double y) => Math.Sqrt(x * x + y * y);

    public Pose Update(PointerSample sample)
    {
        if (previous is not { } old)
        {
            previous = sample;
            lastActivity = sample.Time;
            return Pose.Idle;
        }
        if (Distance(sample.X - old.X, sample.Y - old.Y) > 0.25)
            lastActivity = lastMovement = sample.Time;

        var leftDown = (sample.Buttons & 1) != 0;
        var wasLeftDown = (old.Buttons & 1) != 0;
        if (leftDown && !wasLeftDown)
        {
            pressStarted = sample.Time;
            pressOrigin = (sample.X, sample.Y);
            dragging = false;
            ReactTo(Gesture.LeftClick, sample.Time);
        }
        if ((sample.Buttons & 2) != 0 && (old.Buttons & 2) == 0)
            ReactTo(Gesture.RightClick, sample.Time);
        if (!leftDown && wasLeftDown)
        {
            if (pressStarted is { } start && !dragging && sample.Time - start >= 0.45)
                transient = (Pose.Hop, sample.Time + 0.36);
            pressStarted = null;
            pressOrigin = null;
            dragging = false;
            lastActivity = sample.Time;
        }
        previous = sample;
        if (leftDown && pressStarted is { } began && pressOrigin is { } origin)
        {
            if (Distance(sample.X - origin.X, sample.Y - origin.Y) >= 4) dragging = true;
            lastActivity = sample.Time;
            if (dragging) return Mapped(Gesture.Drag);
            if (sample.Time - began >= 0.45) return Mapped(Gesture.LongPress);
        }
        if (sample.Buttons != 0) lastActivity = sample.Time;
        if (transient is { } reaction && sample.Time < reaction.Until) return reaction.Pose;
        if (sample.Time - lastMovement < 0.12) return Pose.Walk;
        if (NapsEnabled && sample.Time - lastActivity >= 6) return Pose.Sleep;
        return Pose.Idle;
    }
}
