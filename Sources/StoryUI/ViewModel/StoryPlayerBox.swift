//
//  StoryPlayerBox.swift
//  StoryUI
//

import Foundation
import AVKit

/// Holds the AVPlayer for one story bundle.
///
/// `@State private var player = AVPlayer()` allocated a fresh AVPlayer on every
/// single re-evaluation of the enclosing view - SwiftUI throws all but the first
/// away, but the allocation still happens, on the main thread, during drags and
/// swipes. `@StateObject` evaluates its autoclosure exactly once.
final class StoryPlayerBox: ObservableObject {
    @Published private(set) var player = AVPlayer()

    func reset() {
        player.pause()
        player = AVPlayer()
    }
}
