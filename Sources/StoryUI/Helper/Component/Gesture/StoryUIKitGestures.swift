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
//  anything, so it loses the race. A UIKit recognizer can, because UIKit grants
//  simultaneity when EITHER delegate says so.
//
//  Every delegate here answers the same way: yes to simultaneous, no to every
//  failure requirement, and nothing is ever disabled. These recognizers observe;
//  they cannot block. Which recognizer's effect we ACT on is decided in Swift,
//  from the accumulated translation, never by suppressing UIKit.
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
        /// all keep working while a hold is engaged. A long press with a huge
        /// allowableMovement recognizes during any swipe slower than 0.3s, so
        /// these three answers are what stop it eating page swipes.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { true }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { false }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool { false }
    }

    var onHoldChanged: (Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = Constant.holdToPauseDuration
        // UIKit applies allowableMovement only UNTIL the press is recognized;
        // after that the finger may move freely. That is exactly the rule wanted:
        // a swipe never engages a hold, while drift never releases one. (The
        // pre-iOS-18 SwiftUI gesture cannot express this, which is why it needs
        // `holdMovementTolerance` to be huge instead.)
        recognizer.allowableMovement = Constant.holdEngageMovementTolerance
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

        private var axis: Axis = .undecided

        /// Translation at the instant the axis latched vertical. The finger has
        /// already travelled `dismissAxisLockDistance` by then, so reporting the
        /// raw translation as the first offset teleports the story that far in a
        /// single unanimated frame. Subtracting it makes the first reported offset
        /// exactly 0 - the same slop UIScrollView swallows when it starts scrolling.
        private(set) var latchTranslation: CGPoint = .zero

        /// TabView's paging pan. Held weakly, and only ever suspended AFTER the
        /// axis has latched vertical on real evidence.
        private weak var pagingPan: UIPanGestureRecognizer?
        /// Whether *we* are the ones who disabled it. Restoring only what we
        /// suspended means we can never re-enable paging the app turned off.
        private var didSuspendPaging = false

        var isDismissing: Bool { axis == .vertical }

        deinit { restorePaging() }

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
            // Unconditionally simultaneous. UIKit documents that YES from EITHER
            // delegate guarantees both recognizers run, so this is what keeps
            // paging alive while the axis is still undecided.
            if pagingPan == nil,
               otherGestureRecognizer.view is UIScrollView,
               let pan = otherGestureRecognizer as? UIPanGestureRecognizer {
                pagingPan = pan
            }
            return true
        }

        /// Blocks nothing either: an early NO here would fail the paging pan.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        /// True once this touch has proved itself a vertical dismiss. The decision
        /// latches, so a drag cannot flip axis halfway and stutter.
        ///
        /// This gates only what WE draw. It never touches the paging recognizer:
        /// suspending that was what killed page swipes, because any misclassified
        /// touch was then unrecoverable. Now a misclassification costs at most a
        /// little unwanted movement, and paging keeps running regardless.
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
                axis = dy > dx * Constant.dismissAxisLockRatio ? .vertical : .horizontal
                if axis == .vertical {
                    latchTranslation = translation
                    // Only here, with the axis settled on evidence, is it safe to
                    // take paging out - otherwise a sideways move part-way through
                    // a dismiss would turn the page underneath it. Deciding this
                    // any earlier is what previously killed genuine page swipes.
                    suspendPaging()
                }
                return axis == .vertical
            }
        }

        /// Clears the latch and gives paging back, ready for the next touch.
        func finish() {
            restorePaging()
            axis = .undecided
            latchTranslation = .zero
        }

        private func suspendPaging() {
            guard !didSuspendPaging, let pagingPan else { return }
            didSuspendPaging = true
            pagingPan.isEnabled = false
        }

        private func restorePaging() {
            guard didSuspendPaging else { return }
            didSuspendPaging = false
            pagingPan?.isEnabled = true
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
        // Disabling our own recognizer cancels it without necessarily delivering a
        // state change, so release paging here too rather than relying on it.
        if !isEnabled { context.coordinator.finish() }
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        let translation = recognizer.translation(in: recognizer.view)

        switch recognizer.state {
        case .began, .changed:
            guard context.coordinator.shouldDrag(translation: translation) else { return }
            onChanged(translation.y - context.coordinator.latchTranslation.y)
        case .ended, .cancelled, .failed:
            let wasDismissing = context.coordinator.isDismissing
            // Read before finish() clears the latch.
            let offset = translation.y - context.coordinator.latchTranslation.y
            context.coordinator.finish()
            // A touch that turned out to be a page swipe never reported anything,
            // so it has nothing to finish either.
            guard wasDismissing else { return }
            onEnded(offset, recognizer.velocity(in: recognizer.view).y)
        default:
            break
        }
    }
}

// MARK: - Gated modifiers

/// Attaches EXACTLY ONE hold recognizer: the UIKit one on iOS 18+, the caller's
/// SwiftUI one below.
///
/// Both must never be attached at once. Silencing one is not enough - a gesture
/// whose effect is ignored is still installed and still arbitrating for every
/// touch, and the SwiftUI hold is deliberately built never to recognize, so it
/// stays pending for the entire duration of every touch including page swipes.
/// It also cannot answer UIKit's simultaneity and failure-requirement questions,
/// which is the whole reason the UIKit version exists.
struct StoryHoldGestureModifier<SwiftUIGesture: Gesture>: ViewModifier {
    var useUIKit: Bool
    var swiftUIGesture: SwiftUIGesture
    var onHoldChanged: (Bool) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), useUIKit {
            content.gesture(StoryHoldGesture(onHoldChanged: onHoldChanged))
        } else {
            content.simultaneousGesture(swiftUIGesture)
        }
    }
}

/// Attaches drag-to-dismiss on iOS 18+. Below 18 it falls back to a SwiftUI
/// `DragGesture`, which still works but races TabView's paging pan - the same
/// race the host app hits today, and not fixable without replacing TabView.
struct StoryDismissGestureModifier: ViewModifier {
    /// Reference box so the pre-iOS-18 gesture closures can share a latch origin
    /// without the modifier needing mutable state.
    final class Box { var value: CGFloat? }

    var isEnabled: Bool
    private let fallbackOrigin = Box()
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
                        // Same slop subtraction as the UIKit path: DragGesture's
                        // minimumDistance means the first value already carries
                        // 30pt, which would land as a teleport.
                        let origin = fallbackOrigin.value ?? {
                            fallbackOrigin.value = value.translation.height
                            return value.translation.height
                        }()
                        onChanged(value.translation.height - origin)
                    }
                    .onEnded { value in
                        guard isEnabled else { return }
                        let origin = fallbackOrigin.value ?? 0
                        fallbackOrigin.value = nil
                        onEnded(value.translation.height - origin, value.predictedEndTranslation.height)
                    }
            )
        }
    }
}

extension View {
    func holdToPause<G: Gesture>(
        useUIKit: Bool,
        swiftUIGesture: G,
        onHoldChanged: @escaping (Bool) -> Void
    ) -> some View {
        modifier(
            StoryHoldGestureModifier(
                useUIKit: useUIKit,
                swiftUIGesture: swiftUIGesture,
                onHoldChanged: onHoldChanged
            )
        )
    }

    func storyDismissGesture(
        isEnabled: Bool,
        onChanged: @escaping (CGFloat) -> Void,
        onEnded: @escaping (CGFloat, CGFloat) -> Void
    ) -> some View {
        modifier(StoryDismissGestureModifier(isEnabled: isEnabled, onChanged: onChanged, onEnded: onEnded))
    }
}
