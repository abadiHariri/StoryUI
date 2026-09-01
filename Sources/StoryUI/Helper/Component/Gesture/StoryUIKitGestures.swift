//
//  StoryUIKitGestures.swift
//  StoryUI
//
//  UIKit-backed gestures for iOS 18+, so the SDK controls arbitration itself
//  instead of losing races to TabView's private paging scroll view.
//
//  TabView(.page) is backed by a UICollectionView, i.e. a UIScrollView with a
//  real panGestureRecognizer that starts at ~10pt in any direction. A gesture
//  declared in SwiftUI - here or in the host app - cannot tell that recognizer
//  anything. A UIKit recognizer can: UIKit grants simultaneity when EITHER
//  delegate says so, and `shouldRecognizeSimultaneouslyWith` hands us the
//  paging pan itself, which is also the handle we need to suspend it.
//

import SwiftUI
import UIKit

// MARK: - Press and hold

/// Reports press-and-hold begin/end. `UILongPressGestureRecognizer` applies the
/// threshold itself, so unlike the pre-iOS-18 SwiftUI path there is no timer or
/// Date arithmetic involved - `.began` *is* the hold.
@available(iOS 18.0, *)
struct StoryHoldGesture: UIGestureRecognizerRepresentable {

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// Never block anything: taps, the paging pan and the dismiss pan must
        /// all keep working while a hold is engaged.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }
    }

    var onHoldChanged: (Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = Constant.holdToPauseDuration
        // Huge on purpose: a settled finger drifts, and drift must never resume
        // the story. Only lifting or a system cancellation may end a hold.
        recognizer.allowableMovement = Constant.holdMovementTolerance
        // Mandatory - without it the media view stops receiving touches and
        // tap-to-advance dies.
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UILongPressGestureRecognizer,
        context: Context
    ) {
        switch recognizer.state {
        case .began:
            onHoldChanged(true)
        case .ended, .cancelled, .failed:
            onHoldChanged(false)
        default:
            break
        }
    }
}

// MARK: - Drag to dismiss

/// Vertical drag-to-dismiss.
///
/// Both this and TabView's paging pan track every touch from the start - neither
/// blocks the other - and the axis is decided only once the finger has travelled
/// far enough to prove intent. Deciding earlier (in `gestureRecognizerShouldBegin`,
/// which UIKit calls at ~10pt) misreads page swipes as dismisses, because a
/// horizontal swipe routinely starts with a slight vertical component.
@available(iOS 18.0, *)
struct StoryDismissGesture: UIGestureRecognizerRepresentable {

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        private enum Axis { case undecided, vertical, horizontal }

        /// TabView's paging pan, captured the first time UIKit asks us about it.
        private weak var pagingPan: UIPanGestureRecognizer?
        private var axis: Axis = .undecided

        var isDismissing: Bool { axis == .vertical }

        /// Always begin. The axis is decided later, in `shouldDrag`, once there is
        /// enough travel to tell a page swipe from a dismiss - UIKit asks this at
        /// ~10pt, where the two are genuinely indistinguishable.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // The paging pan is the one living on a UIScrollView. Hold a weak
            // reference so we can suspend it once we know the drag is vertical.
            if pagingPan == nil,
               otherGestureRecognizer.view is UIScrollView,
               let pan = otherGestureRecognizer as? UIPanGestureRecognizer {
                pagingPan = pan
            }
            // Never block the pager: until the axis is settled both must be free
            // to track, otherwise a swipe is dead before we know what it was.
            return true
        }

        /// True once this touch has proved itself a vertical dismiss. The decision
        /// latches, so a drag cannot flip axis halfway and stutter.
        func shouldDrag(translation: CGPoint) -> Bool {
            switch axis {
            case .vertical:
                return true
            case .horizontal:
                return false
            case .undecided:
                let dx = abs(translation.x)
                let dy = abs(translation.y)
                guard max(dx, dy) >= Constant.dismissAxisLockDistance else { return false }

                if dy > dx * Constant.dismissAxisLockRatio {
                    axis = .vertical
                    // Only now, with the axis settled, is it safe to take paging
                    // out. Disabling force-cancels it, snapping any partial page back.
                    pagingPan?.isEnabled = false
                } else {
                    axis = .horizontal
                }
                return axis == .vertical
            }
        }

        /// Restores paging and clears the latch, ready for the next touch.
        func finish() {
            if let pagingPan, !pagingPan.isEnabled {
                pagingPan.isEnabled = true
            }
            axis = .undecided
        }
    }

    var isEnabled: Bool
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.minimumNumberOfTouches = 1
        recognizer.requiresExclusiveTouchType = false
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        let translation = recognizer.translation(in: recognizer.view)

        switch recognizer.state {
        case .began, .changed:
            guard context.coordinator.shouldDrag(translation: translation) else { return }
            onChanged(translation.y)
        case .ended, .cancelled, .failed:
            let wasDismissing = context.coordinator.isDismissing
            context.coordinator.finish()
            // A touch that turned out to be a page swipe never reported anything,
            // so it has nothing to finish either.
            guard wasDismissing else { return }
            onEnded(translation.y, recognizer.velocity(in: recognizer.view).y)
        default:
            break
        }
    }
}

// MARK: - Gated modifiers

/// Attaches the UIKit hold on iOS 18+, and nothing at all below it - the older
/// path keeps the SwiftUI `holdToPauseGesture` declared in `StoryDetailView`.
struct StoryHoldGestureModifier: ViewModifier {
    var onHoldChanged: (Bool) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(StoryHoldGesture(onHoldChanged: onHoldChanged))
        } else {
            content
        }
    }
}

/// Attaches drag-to-dismiss on iOS 18+. Below 18 it falls back to a SwiftUI
/// `DragGesture`, which still works but races TabView's paging pan - the same
/// race the host app hits today, and not fixable without replacing TabView.
struct StoryDismissGestureModifier: ViewModifier {
    var isEnabled: Bool
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat, CGFloat) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(
                StoryDismissGesture(isEnabled: isEnabled, onChanged: onChanged, onEnded: onEnded)
            )
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: Constant.dismissFallbackMinimumDistance)
                    .onChanged { value in
                        guard isEnabled else { return }
                        let dx = abs(value.translation.width)
                        let dy = abs(value.translation.height)
                        guard dy >= Constant.dismissAxisLockDistance,
                              dy > dx * Constant.dismissAxisLockRatio else { return }
                        onChanged(value.translation.height)
                    }
                    .onEnded { value in
                        guard isEnabled else { return }
                        onEnded(value.translation.height, value.predictedEndTranslation.height)
                    }
            )
        }
    }
}

extension View {
    func storyHoldGesture(onHoldChanged: @escaping (Bool) -> Void) -> some View {
        modifier(StoryHoldGestureModifier(onHoldChanged: onHoldChanged))
    }

    func storyDismissGesture(
        isEnabled: Bool,
        onChanged: @escaping (CGFloat) -> Void,
        onEnded: @escaping (CGFloat, CGFloat) -> Void
    ) -> some View {
        modifier(StoryDismissGestureModifier(isEnabled: isEnabled, onChanged: onChanged, onEnded: onEnded))
    }
}
