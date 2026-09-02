//
//  ImageLoader.swift
//  StoryUI
//
//  Created by Tolga İskender on 28.03.2022.
//

import Combine
import UIKit
import ImageIO

final class ImageLoader: UIView {
    
    // MARK: Public Properties
    var imageURL: URL?
    var imageView = UIImageView()
    let activityIndicator = UIActivityIndicatorView(style: .medium)
    
     // MARK: - Initializers
    init() {
        super.init(frame: .zero)
        setupImageView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func loadImageWithUrl(_ url: String?, imageIsLoaded: @escaping () -> Void) {

        guard let validatedUrl = url else {
            print("url error")
            return
        }

        if imageURL == URL(string: validatedUrl) {
            return
        }

        imageURL = URL(string: validatedUrl)

        guard let imageURL else { return }

        // stop video if it's playing before image request
        NotificationCenter.default.post(name: .stopVideo, object: nil)

        // Cache hit. The disk read, the decode and the downsample all happen off
        // the main thread, and the CURRENT image stays on screen until the new one
        // is ready, so there is no blank frame either.
        if let cachedResponse = URLCache.shared.cachedResponse(for: .init(url: imageURL)) {
            Self.decodeQueue.async { [weak self] in
                let image = Self.downsampledImage(from: cachedResponse.data)
                DispatchQueue.main.async {
                    guard let self, self.imageURL == imageURL else { return }
                    self.imageView.image = image
                    imageIsLoaded()
                }
            }
            return
        }

        imageView.image = nil
        addIndicator()

        URLSession.shared.dataTask(
            with: imageURL,
            completionHandler: { [weak self] (data, response, error) in
            guard let self else { return }
            if error != nil {
                print(error as Any)
                return
            }

            guard let data, let response else { return }

            URLCache.shared.storeCachedResponse(
                .init(response: response, data: data),
                for: .init( url: imageURL)
            )

            let image = Self.downsampledImage(from: data)

            DispatchQueue.main.async {
                guard self.imageURL == imageURL else { return }
                self.imageView.image = image
                imageIsLoaded()
                self.activityIndicator.stopAnimating()
            }
        }).resume()
    }

}

// MARK: - Decoding

private extension ImageLoader {

    static let decodeQueue = DispatchQueue(
        label: "StoryUI.ImageDecode",
        qos: .userInitiated
    )

    /// Longest edge to keep, in pixels. A story fills the screen, so anything
    /// beyond this is invisible detail that still costs memory and bandwidth on
    /// every composite.
    static var maxPixelSize: CGFloat {
        let bounds = UIScreen.main.bounds
        return max(bounds.width, bounds.height) * UIScreen.main.scale
    }

    /// Decodes and downsamples in one step, off the main thread.
    ///
    /// `UIImage(data:)` keeps the image at full source resolution and defers the
    /// decode until the first draw - which lands on the MAIN thread, inside a
    /// gesture. A 12MP camera photo is ~48MB decoded, and every frame that
    /// composites it through a transform or a clip mask pays for that size. This
    /// is the single largest cost in the whole story path.
    ///
    /// `kCGImageSourceShouldCacheImmediately` forces the decode to happen here,
    /// on this background queue, so the first draw is already a plain blit.
    static func downsampledImage(from data: Data) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return UIImage(data: data)
        }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as [CFString: Any] as CFDictionary

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: thumbnail)
    }
}
// MARK: - Private Funcs
private extension ImageLoader {
   func setupImageView() {
       addSubview(imageView)
       imageView.layer.cornerRadius = 12
       imageView.clipsToBounds = true
       imageView.contentMode = .scaleAspectFit
       // Once, in init. This used to run from layoutSubviews, which re-activated
       // four fresh constraints on every single layout pass - so they accumulated
       // without bound and fought each other, and the view visibly juddered under
       // anything that laid out repeatedly, like a drag or a page swipe.
       imageView.translatesAutoresizingMaskIntoConstraints = false
       NSLayoutConstraint.activate([
           imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
           imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
           imageView.topAnchor.constraint(equalTo: topAnchor),
           imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
       ])
   }
}

extension ImageLoader {
    /// Named `apply` rather than `contentMode` so it cannot shadow UIView's own.
    func apply(_ mode: StoryContentMode) {
        imageView.contentMode = mode.imageContentMode
    }
}
// MARK: - Const funcs
extension ImageLoader {

    private func addIndicator() {
        installIndicatorIfNeeded()
        activityIndicator.startAnimating()
    }

    /// Constraints installed exactly once. This used to add two fresh constraints
    /// to the same indicator on every cache miss, so they piled up across story
    /// changes and the resulting layout churn showed as judder.
    private func installIndicatorIfNeeded() {
        guard activityIndicator.superview == nil else { return }
        activityIndicator.color = UIColor.lightGray.withAlphaComponent(0.7)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}
