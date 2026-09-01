//
//  StoryViewModel.swift
//  StoryUI (iOS)
//
//  Created by Tolga İskender on 28.04.2022.
//

import Foundation
import CoreGraphics

final class StoryViewModel: ObservableObject {

    @Published var currentStoryUser: String = ""
    @Published var stories: [StoryUIModel] = []

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

    /// True while the current story is held. Hides host chrome.
    @Published var isHolding: Bool = false

    private var scheduled: [DispatchWorkItem] = []

    deinit { cancelScheduled() }

    func getVideoProgressBarFrame(duration: Double) -> Double {
        return duration * 0.1 // convert any second to  between 0 - 1 second
    }

    func getStoryModel() -> StoryUIModel? {
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
