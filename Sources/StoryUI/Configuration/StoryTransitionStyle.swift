//
//  StoryTransitionStyle.swift
//  StoryUI
//
//  How a story bundle looks as it moves between pages.
//
//  Every style is a pure function of the page's horizontal position, so all of
//  them track your finger during a swipe exactly like the cube does, and all of
//  them also play on a programmatic advance. What none of them can change is the
//  paging physics - how far you must swipe to commit, and how fast it settles -
//  which belongs to TabView's private paging scroll view.
//

import SwiftUI

public enum StoryTransitionStyle: Equatable {

    /// The default. Pages rotate about their inner edge like faces of a cube.
    case cube(degrees: Double = 45, perspective: Double = 2.5)

    /// The outgoing page dissolves as it leaves.
    case fade

    /// The outgoing page shrinks into the distance and fades out.
    case zoom(minScale: Double = 0.80)

    /// The page lags behind the finger, so it slides at a fraction of the
    /// swipe's speed. `factor` 0 is a plain slide, 1 pins the page in place.
    case parallax(factor: Double = 0.50)

    /// Flat horizontal slide - no effect layered on top.
    case slide

    /// Snapchat-style depth: the story you are leaving shrinks and dims into the
    /// background while the one you are moving toward grows to full size. Both
    /// pages use the same curve, so the incoming one reads as "bigger" simply
    /// because it is closer to the centre.
    case snap(minScale: Double = 0.85, dim: Double = 0.35)
}

// MARK: - Applying a style

extension View {
    /// - Parameters:
    ///   - progress: the page's offset from centre in page-widths. 0 is centred,
    ///     +1 is one full width to the right, -1 one full width to the left.
    ///   - width: the page width, used by styles that translate.
    ///   - isFrozen: true while a dismiss drag is running. Position is read from
    ///     `.global` frames, so the dismiss transform would otherwise feed back
    ///     into the transition and distort every page as the story shrinks.
    @ViewBuilder
    func storyTransition(
        _ style: StoryTransitionStyle,
        progress: CGFloat,
        width: CGFloat,
        isFrozen: Bool
    ) -> some View {
        let value = isFrozen ? 0 : max(-1, min(1, progress))
        let distance = abs(value)

        switch style {
        case let .cube(degrees, perspective):
            rotation3DEffect(
                Angle(degrees: degrees * value),
                axis: (x: 0, y: 1, z: 0),
                anchor: value > 0 ? .leading : .trailing,
                perspective: perspective
            )

        case .fade:
            opacity(1 - distance)

        case let .zoom(minScale):
            scaleEffect(1 - (1 - minScale) * distance)
                .opacity(1 - distance)

        case let .parallax(factor):
            offset(x: -value * width * factor)

        case .slide:
            self

        case let .snap(minScale, dim):
            scaleEffect(1 - (1 - minScale) * distance)
                .overlay(
                    Color.black
                        .opacity(dim * distance)
                        .allowsHitTesting(false)
                )
        }
    }
}
