//
//  StoryDismissStyle.swift
//  StoryUI
//
//  How the story looks while it is being dragged away.
//
//  Every style is a pure function of the rubber-banded drag offset, resolved into
//  one `Transform` value. Keeping it a single struct means `StoryView` applies the
//  same fixed set of modifiers in the same order no matter which style is active,
//  so switching styles can never change view identity mid-drag.
//

import SwiftUI

public enum StoryDismissStyle: Equatable {

    /// The default. Shrinks toward `minScale` as it goes.
    case scale(minScale: Double = 0.75)

    /// Snapchat-style: shrinks and rounds into a circle as it flies away.
    case circle(minScale: Double = 0.35)

    /// Translation only - the story leaves at full size.
    case slide

    /// Tilts as it goes, like flicking a card off a deck.
    case card(maxRotation: Double = 12)

    /// Recedes rather than shrinks: a small scale change plus a darkening veil,
    /// so the story reads as falling behind the backdrop.
    case depth(minScale: Double = 0.90, dim: Double = 0.5)
}

// MARK: - Resolved transform

extension StoryDismissStyle {

    struct Transform: Equatable {
        var offset: CGFloat = 0
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var rotation: Angle = .zero
        /// 0 = rectangle, 1 = ellipse inscribed in the frame.
        var roundness: CGFloat = 0
        /// Darkening veil over the story itself.
        var dim: CGFloat = 0
        var backdropOpacity: CGFloat = 1
    }

    /// - Parameters:
    ///   - offset: raw vertical drag translation, before rubber banding.
    ///   - size: the story's full size, used to normalise and to square up `.circle`.
    func transform(offset: CGFloat, size: CGSize) -> Transform {
        guard offset != 0, size.width > 0, size.height > 0 else { return Transform() }

        let banded = Self.rubberBanded(offset, dimension: size.height)
        let distance = abs(banded)
        // 0...1 against the commit threshold, so every style reaches its full
        // effect at exactly the point where letting go would dismiss.
        let progress = min(1, distance / Constant.dismissCommitDistance)

        var transform = Transform()
        transform.offset = banded
        transform.backdropOpacity = max(0, 1 - distance / Constant.dismissOpacityDivisor)

        switch self {
        case let .scale(minScale):
            let scale = 1 - distance / Constant.dismissScaleDivisor
            transform.scaleX = max(minScale, scale)
            transform.scaleY = transform.scaleX

        case let .circle(minScale):
            // Scaling y by `minScale` and x by `minScale * height/width` lands on a
            // square, so the inscribed ellipse below renders as a true circle.
            let scaleY = 1 - (1 - minScale) * progress
            let aspect = size.height / size.width
            transform.scaleY = scaleY
            transform.scaleX = 1 - (1 - minScale * aspect) * progress
            transform.roundness = progress

        case .slide:
            break

        case let .card(maxRotation):
            transform.rotation = .degrees(maxRotation * progress * (banded < 0 ? -1 : 1))
            let scale = 1 - distance / Constant.dismissScaleDivisor
            transform.scaleX = max(0.85, scale)
            transform.scaleY = transform.scaleX

        case let .depth(minScale, dim):
            let scale = 1 - (1 - minScale) * progress
            transform.scaleX = scale
            transform.scaleY = scale
            transform.dim = dim * progress
        }

        return transform
    }

    /// The transform the story settles into once a dismiss has committed.
    func committedTransform(offset: CGFloat, size: CGSize) -> Transform {
        var transform = self.transform(offset: offset, size: size)
        // Straight off the nearest edge, in the direction the finger was going.
        transform.offset = offset < 0 ? -size.height : size.height
        transform.backdropOpacity = 0
        if case .circle = self { transform.roundness = 1 }
        return transform
    }

    /// UIKit's rubber-band curve: 1:1 with the finger at first, saturating toward
    /// `dimension` as you pull further. This is what stops a drag feeling like the
    /// view is glued to the touch, and it bounds the offset so a fast flick cannot
    /// throw the story an arbitrary distance before the gesture ends.
    static func rubberBanded(_ offset: CGFloat, dimension: CGFloat) -> CGFloat {
        guard dimension > 0 else { return offset }
        let sign: CGFloat = offset < 0 ? -1 : 1
        let distance = abs(offset)
        let c = Constant.dismissRubberBandCoefficient
        return sign * (1 - (1 / (distance * c / dimension + 1))) * dimension
    }
}

// MARK: - Rect to ellipse

/// Morphs a rectangle into the ellipse inscribed in it. `Path(roundedRect:cornerSize:)`
/// with corners of half the width and height *is* that ellipse, so the whole morph is
/// one interpolation with no special cases at either end.
struct StoryRoundnessShape: Shape {
    var roundness: CGFloat

    var animatableData: CGFloat {
        get { roundness }
        set { roundness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard roundness > 0 else { return Path(rect) }
        let clamped = min(1, roundness)
        return Path(
            roundedRect: rect,
            cornerSize: CGSize(
                width: rect.width / 2 * clamped,
                height: rect.height / 2 * clamped
            )
        )
    }
}
