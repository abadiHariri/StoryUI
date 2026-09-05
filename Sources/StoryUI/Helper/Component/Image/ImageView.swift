//
//  StoryUIImageView.swift
//  StoryUI
//
//  Created by Tolga İskender on 28.03.2022.
//

import SwiftUI
import AVKit

struct ImageView: UIViewRepresentable {
    
    var imageURL: String?
    var contentMode: StoryContentMode
    let imageIsLoaded: () -> Void
   
    func makeUIView(context: UIViewRepresentableContext<ImageView>) -> ImageLoader {
        let loader = ImageLoader()
        loader.apply(contentMode)
        return loader
    }
    
    func updateUIView(_ uiView: ImageLoader, context: Context) {
        uiView.apply(contentMode)
        uiView.loadImageWithUrl(imageURL, imageIsLoaded: imageIsLoaded)
    }

    /// Drops the decoded bitmap and cancels the download when SwiftUI removes the
    /// page, instead of waiting for the last reference to go.
    static func dismantleUIView(_ uiView: ImageLoader, coordinator: ()) {
        uiView.releaseImage()
    }
}
