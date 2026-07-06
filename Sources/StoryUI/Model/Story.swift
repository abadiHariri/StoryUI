//
//  StoryUIUser.swift
//  StoryUI
//
//  Created by Tolga İskender on 28.03.2022.
//

import Foundation

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
        Constant.storySecond = duration
    }
}

