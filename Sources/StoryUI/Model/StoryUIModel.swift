//
//  StoryUIMedia.swift
//  StoryUI
//
//  Created by Tolga İskender on 28.03.2022.
//

import Foundation

public struct StoryUIModel: Identifiable, Hashable {
    public var id: String
    public var isSeen: Bool = false
    public var stories: [Story]

    public init(id: String = UUID().uuidString, isSeen: Bool = false, stories: [Story]) {
        self.id = id
        self.isSeen = isSeen
        self.stories = stories
    }
}
