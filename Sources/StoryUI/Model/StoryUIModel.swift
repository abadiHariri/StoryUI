//
//  StoryUIModel.swift
//  StoryUI
//
//  Created by Tolga İskender on 28.03.2022.
//

import Foundation

/// One bundle on screen: the host's own model, paired with the mutable runtime
/// state the viewer owns while that bundle is playing.
///
/// The split is the whole point. `item` is the host's model held whole, and the
/// viewer never writes to it - it is read exactly once, for its id and its media
/// list. `isSeen`, and the per-story `isReady` and measured video `duration`,
/// belong to the viewer and live here. That is what lets a host model stay a
/// read-only value with no viewer concepts baked into it, and what removes the
/// mapping layer that used to sit between the two.
///
/// `item` is a snapshot taken when the viewer was presented. Anything the host
/// expects to change while a story plays - a like, a count - reaches the footer
/// through the array passed to `StoryView`, which is re-read on every render,
/// not through this.
public struct StoryUIModel<Item: StoryUIRepresentable>: Identifiable, Hashable {

    /// Captured once at construction rather than forwarded to `item.storyId` on
    /// every read. `ForEach` and the `TabView` selection ask for this constantly
    /// and `storyId` is usually a computed property on the host's model, so
    /// snapshotting makes page identity provably fixed for the life of the
    /// bundle - whatever the host's property happens to do.
    public let id: String

    /// The host's model for this bundle, exactly as it was handed in.
    public let item: Item

    // MARK: Runtime state

    /// Set when the bundle becomes the visible page.
    public var isSeen: Bool

    /// Runtime state per piece of media, in `storyMedia` order.
    public var stories: [Story]

    /// Pairs a host model with fresh runtime state. The one and only place a
    /// bundle's runtime state is ever allocated.
    ///
    /// `storyId` and `storyMedia` are each read exactly once here, which is what
    /// makes it safe for either to be a computed property that rebuilds on
    /// access.
    public init(_ item: Item) {
        let id = item.storyId
        self.id = id
        self.item = item
        self.isSeen = item.storyIsSeen
        self.stories = item.storyMedia.enumerated().map { offset, media in
            Story(
                // Derived from position, so it is deterministic, unique within
                // the bundle, and needs nothing from the host. Position is what
                // identifies a story inside a bundle.
                id: "\(id)#\(offset)",
                mediaURL: media.url,
                // Seeds video too, which then overwrites it with the measured
                // length once the asset reports one.
                duration: media.duration ?? Constant.storySecond,
                config: StoryConfiguration(
                    mediaType: media.mediaType,
                    imageDuration: media.duration,
                    contentMode: media.contentMode
                )
            )
        }
    }
}

// MARK: - Equality

// Written by hand rather than synthesised, so that conforming a host model to
// `StoryUIRepresentable` never drags a `Hashable` requirement along with it -
// synthesis would demand `Item: Hashable`.
//
// Identity plus runtime state is the right basis regardless: `storyId` must be
// unique across the set, so two bundles agreeing on id and on runtime state are
// the same bundle in the same state, which is exactly the question anything
// comparing these values is asking. `item` is excluded because it is a
// `let` captured from the same id - it cannot disagree.

public extension StoryUIModel {

    static func == (lhs: StoryUIModel<Item>, rhs: StoryUIModel<Item>) -> Bool {
        lhs.id == rhs.id && lhs.isSeen == rhs.isSeen && lhs.stories == rhs.stories
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isSeen)
        hasher.combine(stories)
    }
}
