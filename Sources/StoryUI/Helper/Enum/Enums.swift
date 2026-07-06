//
//  Enums.swift
//  StoryUI
//
//  Created by Tolga İskender on 28.03.2022.
//

import Foundation

// MARK: - StoryUIMediaType
public enum StoryUIMediaType: Equatable {
    case image
    case video
}

// MARK: - StoryUIMediaStateType
public enum StoryUIMediaStateType {
    case seen
    case notSeen
}

// MARK: - StoryDirectionEnum
enum StoryDirectionEnum {
    case previous
    case next
}

 // MARK: - MediaState
enum MediaState {
    case started
    case notStarted
    case restart
    case ready
    case stopped
}


