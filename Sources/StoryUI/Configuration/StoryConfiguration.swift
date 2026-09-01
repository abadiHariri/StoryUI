//
//  StoryConfiguration.swift
//  
//
//  Created by Tolga İskender on 11.06.2023.
//

import Foundation

public struct StoryConfiguration: Equatable, Hashable {
    public var mediaType: StoryUIMediaType

    /// How long this image stays on screen before auto-advancing. Ignored for
    /// video, which is always its own length. Leave nil to use the viewer-wide
    /// `imageDuration` passed to `StoryView`.
    public var imageDuration: TimeInterval?

    /// How this story's media is scaled. Leave nil to use the viewer-wide
    /// `imageContentMode` / `videoContentMode` passed to `StoryView`.
    public var contentMode: StoryContentMode?

    public init(
        mediaType: StoryUIMediaType,
        imageDuration: TimeInterval? = nil,
        contentMode: StoryContentMode? = nil
    ) {
        self.mediaType = mediaType
        self.imageDuration = imageDuration
        self.contentMode = contentMode
    }
}
