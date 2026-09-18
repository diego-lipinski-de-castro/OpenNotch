import SwiftUI

/// Every animation in the product, in one place.
///
/// Two rules carry the feel. Motion is **asymmetric**: opening is eager and a
/// little springy, closing is quick and fully damped, which is how every panel
/// on the system behaves — a menu that leaves as slowly as it arrives feels
/// reluctant. And motion is a **spring, not a duration**: a spring interrupted
/// halfway carries its velocity into the next one, which is the only reason
/// sweeping the cursor in and out of the notch never stutters. A duration-based
/// curve restarted mid-flight snaps back to zero velocity and reads as a glitch.
enum Motion {
    /// Hover opens the panel. Slightly under-damped so the silhouette arrives
    /// with some life; not enough to read as a bounce.
    static func open(_ reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.86)
    }

    /// Closing gets no overshoot you can see — but not a critically damped
    /// spring, which is where this started. Damping of exactly 1 approaches
    /// its target asymptotically: measured on the real panel it covered 87% of
    /// the width in 133ms and then spent another 217ms creeping through the
    /// last 13%, so the notch sat there visibly not-quite-shut. 0.92 overshoots
    /// by a fraction of a point, which nothing can see, and is done in half the
    /// time.
    static func close(_ reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.92)
    }

    /// The wings growing out of the cutout. Looser and slower than hover:
    /// hovering is something the user did, so it only has to keep up, while
    /// this one arrives unasked and has to be noticed.
    static func activate(_ reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.16) : .spring(response: 0.46, dampingFraction: 0.78)
    }

    static func deactivate(_ reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.16) : .spring(response: 0.3, dampingFraction: 0.94)
    }

    /// One state's glyph giving way to another's.
    static func glyph(_ reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.74)
    }

    /// The single beat the glyph gives when a turn starts needing a human. One
    /// beat, not a loop: the pulse already running says *still waiting*, and
    /// this says *started waiting*, which is a different piece of information
    /// and only true once.
    static let attention = Animation.spring(response: 0.3, dampingFraction: 0.5)

    /// Content crossing over inside the silhouette.
    ///
    /// Arriving content waits for the shape to have room and comes in scaled a
    /// hair down from the top edge, so it settles into the panel instead of
    /// appearing in it. Leaving content goes straight out with no scale, fast
    /// enough that the two never smear over each other. Without the delay you
    /// see the middle band of a 424pt panel clipped to the width of a notch,
    /// which reads as a glitch rather than a reveal.
    static func content(_ reduced: Bool) -> AnyTransition {
        guard !reduced else { return .opacity.animation(.easeOut(duration: 0.1)) }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.965, anchor: .top))
                .animation(.spring(response: 0.3, dampingFraction: 0.92).delay(0.055)),
            removal: .opacity.animation(.easeOut(duration: 0.07))
        )
    }

    /// The trailing wing growing or shrinking as the clock passes a minute and
    /// then an hour. A few points of width, arriving unasked: quick, and fully
    /// damped, because anything springy at that size reads as a twitch rather
    /// than a movement.
    static func resize(_ reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.1) : .spring(response: 0.26, dampingFraction: 0.96)
    }

    /// How long the longest spring above takes to come to rest. The window is
    /// only allowed to shrink back around the shape once nothing is moving.
    static let settle: TimeInterval = 0.6
}
