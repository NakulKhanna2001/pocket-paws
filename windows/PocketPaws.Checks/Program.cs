using PocketPaws.Core;

var passed = 0;
var failed = 0;
void Check(string name, Action body)
{
    try { body(); passed++; Console.WriteLine($"PASS  {name}"); }
    catch (Exception error) { failed++; Console.WriteLine($"FAIL  {name}: {error.Message}"); }
}
static void Expect(bool condition, string message = "Expectation failed")
{
    if (!condition) throw new InvalidOperationException(message);
}
static PointerSample Sample(double time, double x = 100, double y = 100, int buttons = 0) => new(x, y, buttons, time);

Check("all shared animals load with unique IDs, including Pengu", () =>
{
    var animals = Animal.LoadBundled();
    Expect(animals.Count == 12 && animals.Select(a => a.Id).Distinct().Count() == 12);
    Expect(animals.Single(a => a.Id == "pip").Name == "Pengu");
    Expect(animals.Single(a => a.Id == "maple").Species == "Red panda");
    Expect(animals.All(a => a.Id != "sprout"));
    foreach (var animal in animals) animal.Validate();
});
Check("click, hold, release, and settle have distinct reactions", () =>
{
    var engine = new GestureEngine();
    Expect(engine.Update(Sample(0)) == Pose.Idle);
    Expect(engine.Update(Sample(1, buttons: 1)) == Pose.Boop);
    Expect(engine.Update(Sample(1.46, buttons: 1)) == Pose.Crouch);
    Expect(engine.Update(Sample(1.6)) == Pose.Hop);
    Expect(engine.Update(Sample(2.1)) == Pose.Idle);
});
Check("drag stays latched even when returning to the press origin", () =>
{
    var engine = new GestureEngine();
    engine.Update(Sample(0));
    engine.Update(Sample(1, buttons: 1));
    Expect(engine.Update(Sample(1.1, x: 108, buttons: 1)) == Pose.Carry);
    Expect(engine.Update(Sample(2, buttons: 1)) == Pose.Carry);
    Expect(engine.Update(Sample(2.1)) != Pose.Hop);
});
Check("small pointer jitter does not become a drag", () =>
{
    var engine = new GestureEngine();
    engine.Update(Sample(0));
    engine.Update(Sample(1, buttons: 1));
    Expect(engine.Update(Sample(1.5, x: 102, y: 102, buttons: 1)) == Pose.Crouch);
});
Check("custom right-click reaction expires", () =>
{
    var engine = new GestureEngine();
    engine.Mappings[Gesture.RightClick] = Pose.Hop;
    engine.Update(Sample(0));
    Expect(engine.Update(Sample(1, buttons: 2)) == Pose.Hop);
    Expect(engine.Update(Sample(1.1)) == Pose.Hop);
    Expect(engine.Update(Sample(1.4)) == Pose.Idle);
});
Check("a click between polling samples is retained", () =>
{
    var engine = new GestureEngine();
    engine.Update(Sample(0));
    engine.ReactTo(Gesture.RightClick, 0.005);
    Expect(engine.Update(Sample(0.016)) == Pose.Wink);
});
Check("movement wakes the pet with little steps that settle promptly", () =>
{
    var engine = new GestureEngine();
    engine.Update(Sample(10));
    Expect(engine.Update(Sample(16.1)) == Pose.Sleep);
    Expect(engine.Update(Sample(17, x: 90)) == Pose.Walk);
    Expect(engine.Update(Sample(17.1, x: 120)) == Pose.Walk);
    Expect(engine.Update(Sample(17.3, x: 120)) == Pose.Idle);
});
Check("disabled naps and held buttons prevent sleep", () =>
{
    var engine = new GestureEngine { NapsEnabled = false };
    engine.Update(Sample(0));
    Expect(engine.Update(Sample(10)) == Pose.Idle);
    engine.NapsEnabled = true;
    engine.Update(Sample(11, buttons: 2));
    Expect(engine.Update(Sample(30, buttons: 2)) == Pose.Idle);
});
Check("resuming during a press does not invent a click or hop", () =>
{
    var engine = new GestureEngine();
    engine.Update(Sample(0));
    engine.Update(Sample(1, buttons: 1));
    engine.Reset();
    Expect(engine.Update(Sample(10, buttons: 1)) == Pose.Idle);
    Expect(engine.Update(Sample(11)) == Pose.Idle);
});
Check("custom hold and drag mappings are respected", () =>
{
    var engine = new GestureEngine();
    engine.Mappings[Gesture.LongPress] = Pose.Wink;
    engine.Mappings[Gesture.Drag] = Pose.Boop;
    engine.Update(Sample(0));
    engine.Update(Sample(1, buttons: 1));
    Expect(engine.Update(Sample(1.5, buttons: 1)) == Pose.Wink);
    Expect(engine.Update(Sample(2, x: 110, buttons: 1)) == Pose.Boop);
});
Check("overlay fits every corner of positive and negative-origin monitors", () =>
{
    ScreenBounds[] screens = [new(0, 0, 1920, 1080), new(-1920, -200, 1920, 1080), new(300, -900, 1440, 900)];
    foreach (var screen in screens)
        foreach (var x in new[] { screen.X, screen.X + screen.Width / 2, screen.X + screen.Width - 1 })
            foreach (var y in new[] { screen.Y, screen.Y + screen.Height / 2, screen.Y + screen.Height - 1 })
            {
                var origin = Placement.Origin(x, y, 128, 136, screen);
                Expect(origin.X >= screen.X && origin.Y >= screen.Y
                    && origin.X + 128 <= screen.X + screen.Width && origin.Y + 136 <= screen.Y + screen.Height);
            }
});
Check("ordinary placement leaves the pointer clear", () =>
{
    var origin = Placement.Origin(300, 400, 64, 68, new ScreenBounds(0, 0, 1920, 1080));
    Expect(origin == new PixelPoint(312, 408));
});
Check("all animals render every reaction with opaque pixel artwork", () =>
{
    foreach (var animal in Animal.LoadBundled())
        foreach (var pose in Enum.GetValues<Pose>())
            for (var frame = 0; frame < 40; frame++)
            {
                var image = SpriteRenderer.Render(animal, pose, frame);
                Expect(image.Argb.Length == image.Width * image.Height);
                Expect(image.Argb.Any(pixel => pixel != 0));
                Expect(image.Argb.All(pixel => pixel == 0 || (pixel >> 24) == 255));
            }
});
Check("all animals have six distinct stepping frames", () =>
{
    foreach (var animal in Animal.LoadBundled())
    {
        var frames = Enumerable.Range(0, 6).Select(frame => SpriteRenderer.Render(animal, Pose.Walk, frame).Argb).ToArray();
        for (var a = 0; a < frames.Length; a++)
            for (var b = a + 1; b < frames.Length; b++)
                Expect(!frames[a].SequenceEqual(frames[b]), $"{animal.Name} has identical step frames {a} and {b}");
    }
});
Check("reduced motion keeps footsteps still", () =>
{
    foreach (var animal in Animal.LoadBundled())
        Expect(SpriteRenderer.Render(animal, Pose.Walk, 0, true).Argb
            .SequenceEqual(SpriteRenderer.Render(animal, Pose.Walk, 5, true).Argb));
});

Console.WriteLine($"\n{passed} passed, {failed} failed");
return failed == 0 ? 0 : 1;
