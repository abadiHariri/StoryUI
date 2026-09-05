//
//  StoryViewModel.swift
//  StoryUI (iOS)
//
//  Created by Tolga İskender on 28.04.2022.
//

import Foundation
import CoreGraphics

/// Generic over the host's model for exactly one reason: `stories` holds the
/// runtime state for every bundle, and each bundle carries the host's own model
/// beside it. Nothing else in here knows or cares what `Item` is.
final class StoryViewModel<Item: StoryUIRepresentable>: ObservableObject {

    @Published var currentStoryUser: String = ""
    @Published var stories: [StoryUIModel<Item>] = []

    // MARK: Interaction state
    //
    // Shared here rather than threaded through bindings because the dismiss drag
    // lives in StoryView while the pause machine lives in StoryDetailView, and
    // every StoryDetailView already observes this object.

    /// True while a dismiss drag is visually in progress - including the snap-back
    /// animation, which is why it is not simply "finger is down".
    ///
    /// Page transitions read `.global` frames, which the dismiss scale and offset
    /// move. Without holding this true until the snap-back has settled, the spring
    /// feeds back into the page transition and the content visibly judders.
    @Published var isDragging: Bool = false

    /// Pauses the story for a dismiss drag, and keeps it paused for a moment after
    /// a cancelled one so the story does not snap straight back into motion.
    @Published var isPausedByDrag: Bool = false

    /// A finger is driving a pan right now, on EITHER axis - so this covers page
    /// swipes as well as dismiss drags.
    ///
    /// Until the hold recognizer's allowableMovement was tightened to 12pt, this
    /// came for free and nobody noticed: at 10_000pt every swipe longer than 0.3s
    /// also engaged a hold, which froze the story machine for the swipe's whole
    /// duration. Tightening it removed the chrome flicker AND, silently, that
    /// pause - leaving the 0.1s timer writing @State ten times a second, and
    /// invalidating the whole page body, underneath a 120Hz scroll.
    @Published private(set) var isTouchActive: Bool = false

    /// @Published fires on every assignment, so this equality guard is what keeps
    /// the cost at two writes per gesture rather than one per frame.
    func setTouchActive(_ active: Bool) {
        guard active != isTouchActive else { return }
        isTouchActive = active
    }

    /// True while the current story is held. Hides host chrome.
    @Published var isHolding: Bool = false

    private var scheduled: [DispatchWorkItem] = []

    deinit { cancelScheduled() }

    func getVideoProgressBarFrame(duration: Double) -> Double {
        return duration * 0.1 // convert any second to  between 0 - 1 second
    }

    func getStoryModel() -> StoryUIModel<Item>? {
        if let i = stories.firstIndex(where: { $0.id == currentStoryUser }) {
            return stories[i]
        }
        return nil
    }

    func getStories() -> [Story]? {
        return getStoryModel()?.stories
    }

    func getStory(with index: Int) -> Story? {
        return getStories()?[index]
    }
}

// MARK: - Dismiss drag lifecycle

extension StoryViewModel {

    func beginDismissDrag() {
        cancelScheduled()
        isDragging = true
        isPausedByDrag = true
    }

    /// The drag was released without committing. The story springs back, and only
    /// then - after a beat - starts playing again.
    func cancelDismissDrag() {
        // Unfreeze once the spring has settled, not when the finger lifts.
        schedule(after: Constant.dismissSnapBackDuration) { [weak self] in
            self?.isDragging = false
        }
        schedule(after: Constant.dismissResumeDelay) { [weak self] in
            self?.isPausedByDrag = false
        }
    }

    /// The drag committed. Nothing resumes - the story is going away.
    func commitDismissDrag() {
        cancelScheduled()
    }

    private func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem(block: block)
        scheduled.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelScheduled() {
        scheduled.forEach { $0.cancel() }
        scheduled.removeAll()
    }
}
