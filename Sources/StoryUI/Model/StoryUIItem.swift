//
//  StoryUIItem.swift
//  StoryUI
//
//  A ready-made `StoryUIRepresentable` for callers that have no model of their
//  own to show - just a bag of media with an id.
//
//  `StoryUIModel` is generic now, and Swift has no default generic parameters, so
//  `StoryUIModel` can no longer be spelled bare at a call site. This is what
//  replaces it for anyone who was using it purely as a container:
//
//      StoryView(
//          stories: [StoryUIItem(media: [.image(url), .video(url)])],
//          isPresented: $isPresented
//      )
//
//  Anyone with a model of their own should conform that instead and skip this.
//

import Foundation

public struct StoryUIItem: StoryUIRepresentable, Identifiable, Hashable {

    public var id: String
    public var media: [StoryUIMedia]
    public var isSeen: Bool

    public init(
        id: String = UUID().uuidString,
        media: [StoryUIMedia],
        isSeen: Bool = false
    ) {
        self.id = id
        self.media = media
        self.isSeen = isSeen
    }

    /// A bundle of images, in order.
    public init(
        id: String = UUID().uuidString,
        imageURLs: [String],
        isSeen: Bool = false
    ) {
        self.init(id: id, media: imageURLs.map { .image($0) }, isSeen: isSeen)
    }

    public var storyId: String { id }
    public var storyMedia: [StoryUIMedia] { media }
    public var storyIsSeen: Bool { isSeen }
}