//
//  ImageLoader.swift
//  StoryUI
//
//  Created by Tolga İskender on 28.03.2022.
//

import Combine
import UIKit

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

        // Cache hit: decode off the main thread, and leave the CURRENT image in
        // place until the new one is ready. Blanking first is what left an empty
        // frame on every advance between cached images; decoding synchronously to
        // avoid that just moved the cost into SwiftUI's update pass instead.
        if let cachedResponse = URLCache.shared.cachedResponse(for: .init(url: imageURL)) {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let image = UIImage(data: cachedResponse.data)
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

            guard let data,
                  let response,
                  let image = UIImage(data: data)
            else { return }

            URLCache.shared.storeCachedResponse(
                .init(response: response, data: data),
                for: .init( url: imageURL)
            )

            DispatchQueue.main.async {
                self.imageView.image = image
                imageIsLoaded()
                self.activityIndicator.stopAnimating()
            }
        }).resume()
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
