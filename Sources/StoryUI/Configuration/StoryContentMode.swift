//
//  StoryContentMode.swift
//  StoryUI
//
//  How media is scaled into the story frame. One vocabulary for both images and
//  video, since the UIKit and AVFoundation spellings differ but the intent does not.
//

import UIKit
import AVKit

public enum StoryContentMode: Equatable, Hashable {

    /// Fills the frame, cropping whatever overflows. No letterboxing, no distortion.
    case fill

    /// Fits entirely inside the frame, letterboxing the remainder. Nothing is cropped.
    case fit

    /// Stretches to the frame exactly, ignoring the source aspect ratio. Distorts.
    case stretch

    var imageContentMode: UIView.ContentMode {
        switch self {
        case .fill:    return .scaleAspectFill
        case .fit:     return .scaleAspectFit
        case .stretch: return .scaleToFill
        }
    }

    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fill:    return .resizeAspectFill
        case .fit:     return .resizeAspect
        case .stretch: return .resize
        }
    }
}
