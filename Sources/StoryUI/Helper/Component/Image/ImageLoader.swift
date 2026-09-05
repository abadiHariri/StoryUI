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

    /// The download in flight, so it can be cancelled when this view goes away.
    /// Without it a dismissed story keeps N requests running to completion, each
    /// still holding its completion handler's captures.
    private var task: URLSessionDataTask?

     // MARK: - Initializers
    init() {
        super.init(frame: .zero)
        setupImageView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        task?.cancel()
    }

    /// Drops the decoded bitmap and any in-flight download at the moment SwiftUI
    /// removes the page, rather than whenever the last reference happens to go.
    /// A fullscreen story bitmap is 5-23 MB.
    func releaseImage() {
        task?.cancel()
        task = nil
        imageURL = nil
        imageView.image = nil
        activityIndicator.stopAnimating()
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

        // Read HERE, on the main thread, and pass them down. `UIScreen` and `UIView`
        // state are main-thread-only, and the decode below runs on `decodeQueue` or on
        // URLSession's delegate thread. `updateUIView` calls `apply(_:)` before this,
        // so `imageView.contentMode` is already current.
        let pixelBox = Self.screenPixelBox
        let mode = imageView.contentMode

        task?.cancel()

        // The whole cache lookup is off the main thread: `cachedResponse(for:)` is a
        // synchronous disk-backed read and this runs from `updateUIView`, i.e. inside
        // a SwiftUI update pass. The CURRENT image stays on screen until the new one
        // is ready, so there is no blank frame either.
        Self.decodeQueue.async { [weak self] in
            guard let cachedResponse = URLCache.shared.cachedResponse(for: .init(url: imageURL)) else {
                DispatchQueue.main.async {
                    guard let self, self.imageURL == imageURL else { return }
                    self.download(imageURL, pixelBox: pixelBox, mode: mode, imageIsLoaded: imageIsLoaded)
                }
                return
            }
            let image = Self.downsampledImage(from: cachedResponse.data, fitting: pixelBox, mode: mode)
            DispatchQueue.main.async {
                guard let self, self.imageURL == imageURL else { return }
                self.imageView.image = image
                imageIsLoaded()
                // Also stopped here: a cache hit that followed a miss used to leave
                // the spinner turning forever behind the image.
                self.activityIndicator.stopAnimating()
            }
        }
    }

    private func download(
        _ imageURL: URL,
        pixelBox: CGSize,
        mode: UIView.ContentMode,
        imageIsLoaded: @escaping () -> Void
    ) {
        imageView.image = nil
        addIndicator()

        let dataTask = URLSession.shared.dataTask(
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

            let image = Self.downsampledImage(from: data, fitting: pixelBox, mode: mode)

            DispatchQueue.main.async {
                guard self.imageURL == imageURL else { return }
                self.imageView.image = image
                imageIsLoaded()
                self.activityIndicator.stopAnimating()
            }
        })
        task = dataTask
        dataTask.resume()
    }

}

// MARK: - Decoding

private extension ImageLoader {

    static let decodeQueue = DispatchQueue(
        label: "StoryUI.ImageDecode",
        qos: .userInitiated
    )

    /// The screen in pixels. Read on the MAIN thread by the caller and passed in;
    /// the decode does not run there.
    static var screenPixelBox: CGSize {
        let bounds = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        return CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    /// Longest edge to keep, in pixels, for THIS image.
    ///
    /// This used to return the screen's longest edge for every image. Because
    /// `kCGImageSourceThumbnailMaxPixelSize` caps the LONGEST edge, a landscape photo
    /// was decoded at 2796x2097 (23 MB) though `.scaleAspectFit` can only ever show it
    /// at 1290x968 (5 MB) - 4.7x waste - and a 3:4 portrait at 2.6x. With
    /// `kCGImageSourceShouldCacheImmediately` those bytes are materialised and
    /// non-purgeable, and there is no cache or cap anywhere in this file, so every
    /// presentation pays for them again.
    ///
    /// Only `.scaleAspectFit` is narrowed. `.scaleAspectFill` and `.scaleToFill` cover
    /// the whole box, so shrinking them to the fit size would upscale them on screen;
    /// they keep the previous behaviour exactly.
    static func maxPixelSize(
        for source: CGImageSource,
        fitting box: CGSize,
        mode: UIView.ContentMode
    ) -> CGFloat {
        let screenLongestEdge = max(box.width, box.height)
        guard mode == .scaleAspectFit, box.width > 0, box.height > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let rawHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              rawWidth > 0, rawHeight > 0
        else { return screenLongestEdge }

        // `kCGImageSourceCreateThumbnailWithTransform` applies EXIF orientation, but
        // pixelWidth/pixelHeight are the PRE-orientation values, so swap them for the
        // four orientations that rotate a quarter turn.
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let quarterTurned = (5...8).contains(orientation)
        let width = CGFloat(quarterTurned ? rawHeight : rawWidth)
        let height = CGFloat(quarterTurned ? rawWidth : rawHeight)

        // Capped at 1 so a small image is never upscaled into a bigger bitmap, and at
        // the screen's longest edge so this can only ever shrink.
        let fit = min(box.width / width, box.height / height, 1)
        return min(max(width * fit, height * fit).rounded(), screenLongestEdge)
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
    static func downsampledImage(
        from data: Data,
        fitting box: CGSize,
        mode: UIView.ContentMode
    ) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return UIImage(data: data)
        }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize(for: source, fitting: box, mode: mode),
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
       // No cornerRadius/clipsToBounds here on purpose. A rounded, clipped layer
       // is composited through an offscreen pass on every frame that an ancestor
       // transform animates - a swipe or a dismiss drag - and on a fullscreen
       // story the corners are off screen anyway. Rounding during a dismiss comes
       // from the clip in StoryDismissTransformModifier instead.
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
