//
//  Constant.swift
//  StoryUI (iOS)
//
//  Created by Tolga İskender on 29.04.2022.
//

import Foundation
import UIKit
import SwiftUI

enum Constant {
    static let progressBarHeight: CGFloat = 4
    static var storySecond: Double = 5.0
    static let progressBarSpacing: CGFloat = 6

    // MARK: Press-and-hold to pause

    /// How long a finger must stay down before the story pauses. UIKit's 0.5s
    /// default reads as sluggish for a story viewer; 0.3s is the genre norm and
    /// is comfortably longer than any deliberate tap-to-advance.
    static let holdToPauseDuration: TimeInterval = 0.3

    /// How far the finger may drift before the press stops counting as a hold.
    /// Deliberately at the paging scroll view's ~10pt pan slop and well under a
    /// host drag-to-dismiss threshold, so a page swipe or a vertical drag always
    /// releases the hold *before* it becomes a page turn or a dismiss.
    /// Never raise this to .infinity - that is what freezes the story through an
    /// entire drag-dismiss.
    static let holdMovementTolerance: CGFloat = 10

    /// A `minimumDuration` no real interaction reaches, which turns the
    /// LongPressGesture into a pure touch-down / touch-up signal: it can only end
    /// by lift, by drifting past `holdMovementTolerance`, or by system
    /// cancellation - each of which reverts the `@GestureState`. Finite rather
    /// than `.infinity` so the degenerate case (an hour-long press) fails safe by
    /// resuming, rather than wedging.
    static let holdGestureMaxDuration: TimeInterval = 60 * 60
}
