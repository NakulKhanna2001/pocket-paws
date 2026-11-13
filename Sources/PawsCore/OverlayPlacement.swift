import Foundation
import CoreGraphics

public enum OverlayPlacement {
    /// AppKit coordinates: y grows upward. Prefer the pointer's bottom-right,
    /// flip at edges, then clamp to the display (including negative-origin ones).
    public static func origin(pointer: CGPoint, size: CGSize, screen: CGRect) -> CGPoint {
        var x = pointer.x + 12
        var y = pointer.y - size.height - 8
        if x + size.width > screen.maxX { x = pointer.x - size.width - 12 }
        if y < screen.minY { y = pointer.y + 12 }
        x = min(max(x, screen.minX), max(screen.minX, screen.maxX - size.width))
        y = min(max(y, screen.minY), max(screen.minY, screen.maxY - size.height))
        return CGPoint(x: x.rounded(), y: y.rounded())
    }
}
