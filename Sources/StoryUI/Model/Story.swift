//
//  StoryUIUser.swift
//  StoryUI
//
//  Created by Tolga İskender on 28.03.2022.
//

import Foundation

/// The runtime record for one piece of media inside a bundle.
///
/// Built by `StoryUIModel` from the host's `StoryUIMedia`, then mutated in place
/// as the story plays: `isReady` once the media has loaded, `duration` once a
/// video reports its measured length. A host never constructs one - it declares
/// `StoryUIMedia` and the viewer builds this beside it.
public struct Story: Identifiable, Hashable {
    public var id: String
    public var mediaURL: String
    public var isReady: Bool = false
    public var isLiked: Bool = false
    public var duration: Double = Constant.storySecond
    public var config: StoryConfiguration

    public init(id: String = UUID().uuidString,
                mediaURL: String,
                isLiked: Bool = false,
                duration: Double = 5,
                config: StoryConfiguration) {

        self.id = id
        self.mediaURL = mediaURL
        self.duration = duration
        self.config = config
        self.isLiked = isLiked
    }
}

