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

/// Vertical drag-to-dismiss. The mirror image of the horizontal pager gesture in
/// the host app: this one owns the vertical axis and refuses horizontal, so a
/// page swipe and a dismiss drag can never both claim the same touch.
@available(iOS 18.0, *)
struct StoryDismissGesture: UIGestureRecognizerRepresentable {

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// TabView's paging pan, captured the first time UIKit asks us about it.
        private weak var pagingPan: UIPanGestureRecognizer?

        /// Suspends paging for the duration of a dismiss drag. Disabling a
        /// recognizer mid-touch force-cancels it, which also snaps any partial
        /// page back - exactly what we want when the drag turns out to be vertical.
        func suspendPaging(_ suspend: Bool) {
            guard let pagingPan, pagingPan.isEnabled == suspend else { return }
            pagingPan.isEnabled = !suspend
        }

        /// Only begin for a clearly vertical drag. Everything else is left to the
        /// pager, so this never competes for a horizontal swipe.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard
                let pan = gestureRecognizer as? UIPanGestureRecognizer,
                let view = pan.view
            else { return false }
            let translation = pan.translation(in: view)
            return abs(translation.y) > abs(translation.x)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // The paging pan is the one living on a UIScrollView. Hold a weak
            // reference so `.began` can suspend it.
            if pagingPan == nil,
               otherGestureRecognizer.view is UIScrollView,
               let pan = otherGestureRecognizer as? UIPanGestureRecognizer {
                pagingPan = pan
            }
            return true
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
        let translation = recognizer.translation(in: recognizer.view).y

        switch recognizer.state {
        case .began:
            context.coordinator.suspendPaging(true)
            onChanged(translation)
        case .changed:
            onChanged(translation)
        case .ended, .cancelled, .failed:
            context.coordinator.suspendPaging(false)
            onEnded(translation, recognizer.velocity(in: recognizer.view).y)
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
                        guard abs(value.translation.height) > abs(value.translation.width) else { return }
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
