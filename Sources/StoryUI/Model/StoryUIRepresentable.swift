//
//  StoryUIRepresentable.swift
//  StoryUI
//
//  The whole viewer is generic over the host's own model. A host conforms its
//  own type here and hands it straight to `StoryView`; the footer closure hands
//  the SAME type back. There is no mapping on the way in and no lookup on the
//  way out.
//

import Foundation

// MARK: - One piece of media

/// A single piece of media inside a bundle - the host's *declaration* of it.
///
/// Deliberately a concrete struct rather than a second protocol with an
/// associated type: with nothing associated, `StoryUIRepresentable` stays
/// trivial to conform to and trivial to use as a generic constraint, and the
/// viewer never imposes a requirement on the host's own element type.
///
/// It carries no identifier, on purpose. Media identity inside a bundle *is* its
/// position, and the viewer derives `Story.id` from that position itself - so
/// `storyMedia` may be a computed property that rebuilds the array on every
/// access, as the typical host's is, without ever destabilising identity.
public struct StoryUIMedia: Hashable {

    /// Remote URL of the image or video.
    public var url: String

    public var mediaType: StoryUIMediaType

    /// How long this image stays on screen before auto-advancing. `nil` uses the
    /// viewer-wide `imageDuration` passed to `StoryView`. Ignored for video,
    /// which always runs its own measured length.
    public var duration: TimeInterval?

    /// How this media is scaled into the frame. `nil` uses the viewer-wide
    /// `imageContentMode` / `videoContentMode` passed to `StoryView`.
    public var contentMode: StoryContentMode?

    public init(
        url: String,
        mediaType: StoryUIMediaType,
        duration: TimeInterval? = nil,
        contentMode: StoryContentMode? = nil
    ) {
        self.url = url
        self.mediaType = mediaType
        self.duration = duration
        self.contentMode = contentMode
    }

    public static func image(
        _ url: String,
        duration: TimeInterval? = nil,
        contentMode: StoryContentMode? = nil
    ) -> StoryUIMedia {
        .init(url: url, mediaType: .image, duration: duration, contentMode: contentMode)
    }

    public static func video(
        _ url: String,
        contentMode: StoryContentMode? = nil
    ) -> StoryUIMedia {
        .init(url: url, mediaType: .video, contentMode: contentMode)
    }
}

// MARK: - A bundle of media

/// Conform your own model to this and hand it to `StoryView` directly.
///
///     extension FeaturedFeedbacksModel: StoryUIRepresentable {
///         var storyId: String { "\(id)" }
///         var storyMedia: [StoryUIMedia] { (images ?? []).map { .image($0) } }
///     }
///
///     StoryView(stories: feedbacks, isPresented: $isPresented) { feedback in
///         FeedbackDetailsCardView(feedback: feedback)   // your OWN type, back again
///     }
///
/// Note what is *not* required: `Hashable`, `Equatable`, `Identifiable`,
/// `Sendable`, or even that the type be a value type. The viewer identifies a
/// bundle by `storyId` and by nothing else, and every piece of state the viewer
/// mutates lives beside your model in `StoryUIModel` rather than inside it - so
/// conforming costs two lines and constrains your type in no other way.
public protocol StoryUIRepresentable {

    /// Stable and unique across the set. This is the page identity: it drives
    /// `ForEach`, the `TabView` selection and therefore every piece of per-page
    /// state, so a value that changed between reads would reset the story
    /// mid-play. Read once, when the viewer is presented.
    var storyId: String { get }

    /// The media to play, in order. Read once, when the viewer is presented.
    /// A bundle with no media is skipped - there is nothing to show.
    var storyMedia: [StoryUIMedia] { get }

    /// Seeds the viewer's `isSeen` runtime flag. Optional - defaults to false.
    var storyIsSeen: Bool { get }
}

public extension StoryUIRepresentable {
    var storyIsSeen: Bool { false }
}

/// A model that is already `Identifiable` by `String` needs only `storyMedia`.
public extension StoryUIRepresentable where Self: Identifiable, Self.ID == String {
    var storyId: String { id }
}