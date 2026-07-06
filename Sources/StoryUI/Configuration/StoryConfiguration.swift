//
//  StoryConfiguration.swift
//  
//
//  Created by Tolga İskender on 11.06.2023.
//

import Foundation

public struct StoryConfiguration: Equatable, Hashable {
    public var mediaType: StoryUIMediaType

    public init(mediaType: StoryUIMediaType) {
        self.mediaType = mediaType
    }
}
