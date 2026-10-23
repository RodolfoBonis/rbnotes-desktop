import Foundation

/// Pure geometry for the notch activity overlay: given a screen rectangle and
/// the notch dimensions, it computes the panel frame for the "birth" state
/// (the overlay emerging from the notch) and for each expanded size.
///
/// All rectangles use AppKit's screen convention: origin at the bottom-left of
/// the screen, `y` increasing upward, so the outputs can be handed straight to
/// `NSPanel.setFrame(_:display:)`. This type is Foundation-only so it can be
/// unit-tested via `RbNativeCore` without AppKit or a real display.
public enum NotchGeometry {
  /// A rectangle in AppKit screen coordinates (bottom-left origin, y-up).
  public struct Rect: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
      self.x = x
      self.y = y
      self.width = width
      self.height = height
    }

    /// The top edge (largest y) of the rectangle.
    public var maxY: Double { y + height }
    /// The horizontal center.
    public var midX: Double { x + width / 2 }
  }

  /// Whether the screen has a real hardware notch worth emerging from.
  ///
  /// A couple of points of `safeAreaInsets.top` on a notchless external display
  /// should not count, so we require a sensible minimum height.
  public static func hasNotch(notchHeight: Double, minHeight: Double = 20) -> Bool {
    notchHeight >= minHeight
  }

  /// The frame for a top-center pill of the given `width`/`height`, flush with
  /// the top of `screen` minus `topInset`.
  ///
  /// `topInset` is 0 on notched Macs (the pill hugs the physical top edge and
  /// visually continues the notch) and the menu-bar height on notchless Macs so
  /// the pill drops from just under the menu bar.
  public static func pillFrame(
    screen: Rect, width: Double, height: Double, topInset: Double = 0
  ) -> Rect {
    let clampedWidth = min(width, screen.width)
    let x = screen.x + (screen.width - clampedWidth) / 2
    let topEdge = screen.maxY - topInset
    let y = topEdge - height
    return Rect(x: x, y: y, width: clampedWidth, height: height)
  }

  /// The initial frame the overlay animates out from.
  ///
  /// On a notched Mac this is exactly the notch bounds (centered at the very top
  /// of the screen), so the pill looks like it grows out of the notch. On a
  /// notchless Mac there is nothing to grow from, so we start as a thin
  /// `fallbackWidth`-wide sliver just under the menu bar (`topInset`) which then
  /// expands downward.
  public static func birthFrame(
    screen: Rect,
    notchWidth: Double,
    notchHeight: Double,
    fallbackWidth: Double = 180,
    collapsedHeight: Double = 6,
    topInset: Double = 0
  ) -> Rect {
    if hasNotch(notchHeight: notchHeight) {
      return pillFrame(
        screen: screen, width: notchWidth, height: notchHeight, topInset: 0)
    }
    return pillFrame(
      screen: screen, width: fallbackWidth, height: collapsedHeight,
      topInset: topInset)
  }
}
