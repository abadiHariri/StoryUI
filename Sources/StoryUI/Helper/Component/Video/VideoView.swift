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
    @Binding var state: MediaState
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
        playerView.state = state
        playerView.videoGravity = contentMode.videoGravity
        playerView.mediaState = { state, duration in
            mediaState?(state, duration)
        }
        return playerView
    }
    
    func updateUIView(_ playerView: PlayerView, context: Context) {
        playerView.videoGravity = contentMode.videoGravity
        playerView.state = state
        playerView.startVideo(url: URL(string: videoURL))
        playerView.mediaState = { state, duration in
            mediaState?(state, duration)
        }
    }
    
}
