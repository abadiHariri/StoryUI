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
    ///
    /// Deliberately huge. A finger resting on the screen drifts tens of points
    /// over a few seconds, and a tight tolerance would end the hold - resuming
    /// the story with the finger still down. The requirement is the opposite:
    /// while the finger is held the story must never continue, so only LIFTING
    /// (or a system cancellation) may release it.
    ///
    /// The trade this accepts: a page swipe or a drag-to-dismiss that takes
    /// longer than `holdToPauseDuration` also engages the hold, so the story
    /// stays frozen for the duration of that drag and resumes on lift. That is
    /// invisible mid-transition, and it is the correct side to err on here.
    static let holdMovementTolerance: CGFloat = 10_000

    /// A `minimumDuration` no real interaction reaches, which turns the
    /// LongPressGesture into a pure touch-down / touch-up signal: it can only end
    /// by lift, by drifting past `holdMovementTolerance`, or by system
    /// cancellation - each of which reverts the `@GestureState`. Finite rather
    /// than `.infinity` so the degenerate case (an hour-long press) fails safe by
    /// resuming, rather than wedging.
    static let holdGestureMaxDuration: TimeInterval = 60 * 60

    // MARK: Drag to dismiss

    /// Past this many points of vertical drag, letting go dismisses.
    static let dismissCommitDistance: CGFloat = 150

    /// A flick this fast dismisses even if it never travelled `dismissCommitDistance`.
    static let dismissCommitVelocity: CGFloat = 900

    /// The story shrinks by distance/700 and the backdrop fades by distance/400,
    /// matching the host app's fullscreen image gallery exactly.
    static let dismissScaleDivisor: CGFloat = 700
    static let dismissOpacityDivisor: CGFloat = 400

    /// Where the story settles as it flies away.
    static let dismissFinalScale: CGFloat = 0.75

    /// Only used by the pre-iOS-18 SwiftUI fallback, which has to out-wait
    /// TabView's paging pan rather than out-rank it.
    static let dismissFallbackMinimumDistance: CGFloat = 30

    /// How far a touch must travel before we decide whether it is a page swipe or
    /// a dismiss. UIKit asks `gestureRecognizerShouldBegin` at ~10pt, which is far
    /// too early: a horizontal swipe routinely starts with a slight vertical
    /// component, so deciding there classifies real page swipes as dismisses.
    static let dismissAxisLockDistance: CGFloat = 16

    /// How much more vertical than horizontal a drag must be to count as a
    /// dismiss. Anything less decisive is left to the pager.
    static let dismissAxisLockRatio: CGFloat = 1.2

    /// Resistance curve. 1.0 tracks the finger 1:1 at first and saturates as the
    /// drag grows; lower values feel stiffer from the start.
    static let dismissRubberBandCoefficient: CGFloat = 1.0

    /// How long the snap-back spring takes. Page transitions stay frozen for
    /// exactly this long after a cancelled drag, so the spring cannot feed back
    /// into them through the `.global` frames they read.
    static let dismissSnapBackDuration: TimeInterval = 0.32

    /// After a cancelled drag the story waits before playing again, rather than
    /// lurching straight back into motion under the finger that just let go. Long
    /// enough to read as deliberate, short enough not to feel stuck.
    static let dismissResumeDelay: TimeInterval = 0.8

    // MARK: Timing

    /// Progress tick. Advancing is measured against the wall clock rather than
    /// counted in ticks, so a late or coalesced tick cannot stretch a story past
    /// its configured duration - this is only how often we look.
    static let timerTick: TimeInterval = 0.1

    /// Longest gap a single tick may account for. Caps the catch-up jump after the
    /// app is backgrounded or the main thread stalls.
    static let maxTickInterval: TimeInterval = 0.5
}
