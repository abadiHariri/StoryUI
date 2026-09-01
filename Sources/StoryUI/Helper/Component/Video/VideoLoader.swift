//
//  VideoLoader.swift
//  StoryUI (iOS)
//
//  Created by Tolga İskender on 30.04.2022.
//

import Foundation
import UIKit
import AVKit

final class PlayerView: UIView {

    // MARK: Public Properties
    weak var player: AVPlayer?
    var duration: Double = 0.0
    var state: MediaState = .notStarted
    var mediaState: ((MediaState, Double) -> ())?
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill {
        didSet { playerLayer.videoGravity = videoGravity }
    }

    let contentView = UIView()

    // MARK: Private Properties
    private let playerLayer = AVPlayerLayer()
    private var url: URL?
    private let cacheManager: StoryVideoCacheManager

    private var observation: NSKeyValueObservation?

    // MARK: - Initializers
    override init(frame: CGRect) {
        self.cacheManager = StoryVideoCacheManager()
        super.init(frame: frame)
        self.layer.cornerRadius = 12
        self.clipsToBounds = true
        setupPlayer()
    }

    deinit {
        observation = nil
        player = nil
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard playerLayer.frame != contentView.bounds else { return }
        // CALayer animates frame changes implicitly, which would make the video
        // lag a frame behind the view it sits in during a drag.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = contentView.bounds
        CATransaction.commit()
    }

    func startVideo(url: URL?) {
        guard let validatedUrl = url else { return }
        if self.url == url { return }
        self.url = validatedUrl
        addActivityIndicatory()
        // stop video if it's playing before video request
        stopVideo()
        guard let url = url else { return }
        cacheManager.loadVideo(from: url) { [weak self] result in
            switch result {
            case .success(let url):
                self?.setupPlayer(url)
            case .failure(let error):
                print(error)
            }
        }
    }

}

//MARK: - Configure

private extension PlayerView {
    func setupPlayer(_ url: URL) {
        self.player?.replaceCurrentItem(with: nil)
        self.player?.replaceCurrentItem(with: .init(url: url))

        observation = player?.observe(\.timeControlStatus, options: .new) { [weak self] player, change in
            guard let self else { return }
            if player.timeControlStatus == .playing {
                self.removeActivityIndicatory()
                self.state = .started
                self.mediaState?(self.state, self.duration)
            } else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                self.addActivityIndicatory()
            }
        }

        self.player?.automaticallyWaitsToMinimizeStalling = false
        self.getVideoLength(videoURL: url)
        self.playerLayer.player = self.player
        self.playerLayer.videoGravity = videoGravity
        self.playerLayer.backgroundColor = UIColor.black.cgColor
        playerLayer.removeFromSuperlayer()
        self.contentView.layer.addSublayer(self.playerLayer)
        // The asset is a fully downloaded local file by this point, so the layer can
        // render frame 0 without play(). Dropping the loading overlay here - rather
        // than only in the `.playing` KVO branch below - keeps a story that is paused
        // across the download (host `isPaused`, or a press-and-hold) from sitting
        // behind an opaque black view and a spinner for as long as the pause lasts.
        removeActivityIndicatory()
        state = .ready
        mediaState?(.ready, duration)
        addObserverToVideo()
    }

    func getVideoLength(videoURL: URL) {
        duration = AVURLAsset(url: videoURL).duration.seconds
    }

    func stopAndRestartVideo() {
        player?.seek(to: .zero)
    }

    func stopVideo() {
        if player?.timeControlStatus == .playing {
            player?.pause()
            player?.seek(to: .zero)
            state = .stopped
        }
    }

    func restartVideo() {
        if player?.timeControlStatus == .paused {
            player?.seek(to: .zero)
            player?.play()
            state = .restart
        }
    }

    func addObserverToVideo() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(restartVideoObserver),
            name: .restartVideo,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stopVideoObserver),
            name: .stopVideo,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stopAndRestartVideoObserver),
            name: .stopAndRestartVideo,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(replaceCurrentItemObserver),
            name: .replaceCurrentItem,
            object: nil
        )
    }

    @objc
    func stopAndRestartVideoObserver() {
        stopAndRestartVideo()
    }

    @objc
    func restartVideoObserver() {
        restartVideo()
    }

    @objc
    func stopVideoObserver() {
        stopVideo()
    }

    @objc
    func replaceCurrentItemObserver() {
        self.player?.replaceCurrentItem(with: nil)
        self.observation = nil
        self.player = nil
    }
}

// MARK: - Setup Func

private extension PlayerView {
    func addActivityIndicatory() {
        removeActivityIndicatory()
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        let view = UIView(frame: CGRect(x: 0, y: 0, width: w, height: h))
        view.backgroundColor = .black
        view.tag = 999
        self.addSubview(view)
        let activityView = UIActivityIndicatorView(style: .large)
        activityView.color = UIColor.lightGray.withAlphaComponent(0.7)
        activityView.frame = CGRect(x: w / 2, y: h / 2, width: .zero, height: .zero)
        view.addSubview(activityView)
        addConst(view: activityView)
        activityView.startAnimating()
    }

    func setupPlayer() {
        addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func removeActivityIndicatory() {
        self.subviews.forEach { (view) in
            if view.tag == 999 {
                view.removeFromSuperview()
            }
        }
    }

    func addConst(view: UIActivityIndicatorView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: view.superview!.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: view.superview!.centerYAnchor)
        ])
    }
}
