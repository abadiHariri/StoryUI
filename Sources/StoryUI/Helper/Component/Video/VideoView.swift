//
//  VideoView.swift
//  StoryUI
//
//  Created by Tolga İskender on 31.03.2022.
//

import SwiftUI
import AVKit

struct VideoView: UIViewRepresentable {
    
    // MARK: Public Properties
    var videoURL: String
    var player: AVPlayer
    var contentMode: StoryContentMode
    let mediaState: ((MediaState, Double) -> Void)?
    
    func makeUIView(context: Context) -> PlayerView {
        let playerView = PlayerView(
            frame: .init(
                x: 0, 
                y: 0,
                width: UIScreen.main.bounds.width,
                height: UIScreen.main.bounds.height
            )
        )

        if playerView.player == nil {
            playerView.player = player
        }
        playerView.videoGravity = contentMode.videoGravity
        playerView.mediaState = { state, duration in
            mediaState?(state, duration)
        }
        return playerView
    }
    
    func updateUIView(_ playerView: PlayerView, context: Context) {
        playerView.videoGravity = contentMode.videoGravity
        // Before startVideo, so anything the new video reports reaches the closure
        // for the story that is showing now.
        playerView.mediaState = { state, duration in
            mediaState?(state, duration)
        }
        playerView.startVideo(videoURL)
    }

    /// Takes the item off the player when SwiftUI removes the page, so a video
    /// that is still streaming stops using the network straight away.
    static func dismantleUIView(_ playerView: PlayerView, coordinator: ()) {
        playerView.releasePlayer()
    }
    
}
