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

    /// Dissolves in place. No scale, no rounding.
    case fade

    /// Tilts away from you on the horizontal axis, like a page being lifted.
    case flip(maxRotation: Double = 28)

    /// Collapses hard toward a small thumbnail, fading as it goes.
    case shrink(minScale: Double = 0.25)

    /// Slides back into the deck: a small scale drop plus a slight backward tilt.
    case stack(minScale: Double = 0.85)

    /// The circle, dissolving as it flies. Snapchat with a softer exit.
    case circleFade(minScale: Double = 0.35)
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
        var opacity: CGFloat = 1
        /// Tilt about the horizontal axis, for the styles that lean away.
        var tilt: Angle = .zero
        var perspective: CGFloat = 1
        var backdropOpacity: CGFloat = 1
    }

    /// - Parameters:
    ///   - offset: raw vertical drag translation, before rubber banding.
    ///   - size: the story's full size, used to normalise and to square up `.circle`.
    ///   - rubberBand: false once a dismiss has committed, so the story can travel
    ///     the whole way off screen - the band saturates at `size.height`.
    func transform(offset: CGFloat, size: CGSize, rubberBand: Bool = true) -> Transform {
        guard offset != 0, size.width > 0, size.height > 0 else { return Transform() }

        let banded = rubberBand ? Self.rubberBanded(offset, dimension: size.height) : offset
        let distance = abs(banded)
        // Paced by its own constant rather than the commit threshold, so the
        // dismiss can trigger early without the visuals racing to keep up.
        let progress = min(1, distance / Constant.dismissProgressDistance)

        var transform = Transform()
        transform.offset = banded
        // Default fade. Styles that shrink the story to a small shape override this
        // below: at the commit point they are only covering a fraction of the
        // screen, so a backdrop still at 60% opacity reads as "the screen is just
        // black", which defeats the effect entirely.
        transform.backdropOpacity = max(0, 1 - distance / Constant.dismissOpacityDivisor)

        switch self {
        case let .scale(minScale):
            let scale = 1 - distance / Constant.dismissScaleDivisor
            transform.scaleX = max(minScale, scale)
            transform.scaleY = transform.scaleX

        case let .circle(minScale):
            // Uniform scale: the clip does the squaring, so the media keeps its
            // aspect ratio and is cropped rather than squashed.
            let scale = 1 - (1 - minScale) * progress
            transform.scaleX = scale
            transform.scaleY = scale
            // Rounds ahead of the shrink so it reads as a circle well before the
            // commit point, rather than only at the very end.
            transform.roundness = min(1, progress * Constant.dismissRoundnessLead)
            // Gone completely by commit: the story is a small circle by then, and
            // anything left of the backdrop just looks like a black screen.
            transform.backdropOpacity = max(0, 1 - progress)

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

        case .fade:
            transform.opacity = 1 - progress

        case let .flip(maxRotation):
            transform.tilt = .degrees(maxRotation * progress * (banded < 0 ? 1 : -1))
            transform.perspective = 0.6
            let scale = 1 - 0.10 * progress
            transform.scaleX = scale
            transform.scaleY = scale

        case let .shrink(minScale):
            let scale = 1 - (1 - minScale) * progress
            transform.scaleX = scale
            transform.scaleY = scale
            transform.opacity = 1 - progress * 0.6
            transform.backdropOpacity = max(0, 1 - progress)

        case let .stack(minScale):
            let scale = 1 - (1 - minScale) * progress
            transform.scaleX = scale
            transform.scaleY = scale
            transform.tilt = .degrees(6 * progress * (banded < 0 ? 1 : -1))
            transform.perspective = 0.4

        case let .circleFade(minScale):
            let scale = 1 - (1 - minScale) * progress
            transform.scaleX = scale
            transform.scaleY = scale
            transform.roundness = min(1, progress * Constant.dismissRoundnessLead)
            transform.opacity = 1 - progress * 0.5
            transform.backdropOpacity = max(0, 1 - progress)
        }

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

// MARK: - Which effects a style actually needs

extension StoryDismissStyle {
    /// Each of these gates one render effect. `clipShape` and `rotation3DEffect`
    /// in particular force extra rendering passes over the whole story - a live
    /// AVPlayer layer and TabView's collection view included - on every frame of a
    /// drag, even when they are mathematically the identity. Applying only what a
    /// style uses is the difference between a smooth drag and a dropped frame.
    ///
    /// All of these are constant for a given style, so branching on them cannot
    /// change view identity part-way through a drag.

    var needsRoundness: Bool {
        switch self {
        case .circle, .circleFade: return true
        default: return false
        }
    }

    var needsDim: Bool {
        if case .depth = self { return true }
        return false
    }

    var needsTilt: Bool {
        switch self {
        case .flip, .stack: return true
        default: return false
        }
    }

    var needsRotation: Bool {
        if case .card = self { return true }
        return false
    }

    var needsOpacity: Bool {
        switch self {
        case .fade, .shrink, .circleFade: return true
        default: return false
        }
    }
}

// MARK: - Applying the transform

struct StoryDismissTransformModifier: ViewModifier {
    let style: StoryDismissStyle
    let transform: StoryDismissStyle.Transform

    func body(content: Content) -> some View {
        content
            .modifier(DimModifier(isActive: style.needsDim, dim: transform.dim))
            .modifier(RoundnessModifier(isActive: style.needsRoundness, roundness: transform.roundness))
            .modifier(OpacityModifier(isActive: style.needsOpacity, opacity: transform.opacity))
            .modifier(TiltModifier(isActive: style.needsTilt, tilt: transform.tilt, perspective: transform.perspective))
            // Scale and offset are the core of every style and are cheap enough to
            // apply unconditionally.
            .scaleEffect(x: transform.scaleX, y: transform.scaleY)
            .modifier(RotationModifier(isActive: style.needsRotation, rotation: transform.rotation))
            .offset(y: transform.offset)
    }

    private struct DimModifier: ViewModifier {
        let isActive: Bool
        let dim: CGFloat
        func body(content: Content) -> some View {
            if isActive {
                content.overlay(Color.black.opacity(dim).allowsHitTesting(false))
            } else {
                content
            }
        }
    }

    private struct RoundnessModifier: ViewModifier {
        let isActive: Bool
        let roundness: CGFloat
        func body(content: Content) -> some View {
            if isActive {
                content
                    // Inside the clip, so it becomes the disc itself. Without it,
                    // `.fit` media leaves transparent letterbox bars and the
                    // clipped edge has nothing to show against.
                    .background(Color.black)
                    .clipShape(StoryRoundnessShape(roundness: roundness))
            } else {
                content
            }
        }
    }

    private struct OpacityModifier: ViewModifier {
        let isActive: Bool
        let opacity: CGFloat
        func body(content: Content) -> some View {
            if isActive { content.opacity(opacity) } else { content }
        }
    }

    private struct TiltModifier: ViewModifier {
        let isActive: Bool
        let tilt: Angle
        let perspective: CGFloat
        func body(content: Content) -> some View {
            if isActive {
                content.rotation3DEffect(tilt, axis: (x: 1, y: 0, z: 0), perspective: perspective)
            } else {
                content
            }
        }
    }

    private struct RotationModifier: ViewModifier {
        let isActive: Bool
        let rotation: Angle
        func body(content: Content) -> some View {
            if isActive { content.rotationEffect(rotation) } else { content }
        }
    }
}

// MARK: - Rect to ellipse

/// Morphs the full rectangle into the largest circle that fits inside it, centred.
///
/// Interpolating the corner radius alone is not enough on a tall frame: the ellipse
/// inscribed in a full-screen rect is wider than the media at its centre, so it
/// clips nothing visible. This shrinks the rect toward a centred square as it
/// rounds, so the clip actually bites and ends as a real circle.
struct StoryRoundnessShape: Shape {
    var roundness: CGFloat

    var animatableData: CGFloat {
        get { roundness }
        set { roundness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard roundness > 0 else { return Path(rect) }
        let t = min(1, roundness)
        let side = min(rect.width, rect.height)
        let width = rect.width + (side - rect.width) * t
        let height = rect.height + (side - rect.height) * t
        let box = CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
        return Path(roundedRect: box, cornerRadius: min(width, height) / 2 * t)
    }
}
