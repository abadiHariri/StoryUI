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
    var mediaState: ((MediaState, Double) -> ())?
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill {
        didSet { playerLayer.videoGravity = videoGravity }
    }

    let contentView = UIView()

    // MARK: Private Properties
    private let playerLayer = AVPlayerLayer()
    private let activityIndicator = UIActivityIndicatorView(style: .large)

    /// The link exactly as the host gave it. Compared as text, so a second link
    /// that does not parse still counts as a new video rather than as the last one.
    private var source: String?

    /// The item this view put on the player. The player belongs to the page, so a
    /// callback about any other item is stale and is dropped.
    private var playerItem: AVPlayerItem?
    private var duration: Double = 0.0
    private var didReportReady: Bool = false
    private var didFail: Bool = false
    private var itemObservations: [NSKeyValueObservation] = []

    // MARK: - Initializers
    override init(frame: CGRect) {
        super.init(frame: frame)
        // See ImageLoader: an offscreen pass per frame for corners that are off
        // screen. The dismiss clip supplies any rounding that is actually visible.
        // Black while the first frame is on its way - the look the old full-screen
        // loading cover had - without hiding the last frame during a stall.
        backgroundColor = .black
        setupPlayer()
        setupActivityIndicator()
        // Once, here. This used to run for every new video, so each one stacked
        // another set of registrations on the same view.
        addObserverToVideo()
    }

    deinit {
        itemObservations.forEach { $0.invalidate() }
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

    func startVideo(_ source: String) {
        if self.source == source { return }
        self.source = source
        // The next video starts paused. The page decides when it plays, so a story
        // that is paused - held, dragged, behind a host sheet - stays paused.
        player?.pause()
        guard let url = URL(string: source) else {
            failInvalidURL()
            return
        }
        setupPlayer(url)
    }

    /// Takes the item off the player the moment SwiftUI removes this view, so a
    /// video that is still streaming stops using the network now rather than
    /// whenever the player is finally released.
    func releasePlayer() {
        removeItemObservers()
        activityIndicator.stopAnimating()
        if let playerItem, player?.currentItem === playerItem {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
        }
        playerItem = nil
    }
}

//MARK: - Configure

private extension PlayerView {
    func setupPlayer(_ url: URL) {
        removeItemObservers()
        duration = 0.0
        didReportReady = false
        didFail = false

        // Only nil once `.replaceCurrentItem` has run, i.e. while the story is closing.
        guard let player else { return }

        // Streamed, never downloaded: the player fetches only what it is about to
        // play, the way SallaVideoPlayerIOS plays product videos. The old path
        // downloaded the whole file - up to 100 MB - before the first frame.
        let item = AVPlayerItem(url: url)
        playerItem = item

        // Waits until enough is buffered and rides out short stalls by itself,
        // instead of starting at once and stopping every few seconds on a slow
        // network.
        player.automaticallyWaitsToMinimizeStalling = true
        player.replaceCurrentItem(with: item)

        playerLayer.player = player
        playerLayer.videoGravity = videoGravity
        playerLayer.backgroundColor = UIColor.black.cgColor
        playerLayer.removeFromSuperlayer()
        contentView.layer.addSublayer(playerLayer)

        addItemObservers(item, player: player)
        updateBufferingState()
    }

    func addItemObservers(_ item: AVPlayerItem, player: AVPlayer) {
        // Both fire off the main thread and are answered on it. `.initial` matters
        // as much as `.new`: an item that settled before this ran - a bad link that
        // fails at once - would otherwise never be reported, and the spinner would
        // never stop.
        itemObservations = [
            item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                DispatchQueue.main.async { [weak self] in
                    self?.handleStatusChange(of: item)
                }
            },
            player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { [weak self] in
                    self?.handleTimeControlStatusChange(of: item)
                }
            },
        ]

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(failedToPlayToEndObserver(_:)),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item
        )
    }

    func removeItemObservers() {
        itemObservations.forEach { $0.invalidate() }
        itemObservations = []
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
    }

    func handleStatusChange(of item: AVPlayerItem) {
        // The hop to the main thread is long enough for the page to have moved on
        // to another video.
        guard item === playerItem else { return }

        switch item.status {
        case .readyToPlay:
            handleReady(item)
        case .failed:
            handleFailure()
        default:
            break
        }

        updateBufferingState()
    }

    /// The first report for a video. The story only starts counting once it has
    /// it, and it carries the real length, so the bar never runs on a guess.
    func handleReady(_ item: AVPlayerItem) {
        guard !didReportReady, !didFail else { return }
        didReportReady = true

        let seconds = item.duration.seconds
        // A container that states no length - a live stream - runs for the default
        // rather than never.
        duration = seconds.isFinite && seconds > 0 ? seconds : Constant.storySecond
        mediaState?(.ready, duration)
    }

    func handleTimeControlStatusChange(of item: AVPlayerItem) {
        guard item === playerItem else { return }

        updateBufferingState()

        guard player?.currentItem === item,
              player?.timeControlStatus == .playing,
              didReportReady,
              !didFail
        else { return }
        mediaState?(.started, duration)
    }

    /// A video that cannot be played is skipped quietly: no error, no spinner left
    /// turning. The story runs for the default length and moves on.
    func handleFailure() {
        guard !didFail else { return }
        didFail = true

        player?.pause()
        duration = Constant.storySecond
        mediaState?(.failed, duration)
    }

    /// `URL(string:)` gives nil for a link it cannot parse, and nothing would ever
    /// call back about it. Treated as a failed video so the story moves on.
    func failInvalidURL() {
        releasePlayer()
        didFail = true

        // This runs inside a SwiftUI update, where the page's state must not be
        // written, so the report goes out on the next turn - and only if this is
        // still the link on screen.
        let source = self.source
        DispatchQueue.main.async { [weak self] in
            guard let self, self.source == source else { return }
            self.mediaState?(.failed, Constant.storySecond)
        }
    }

    /// Spins while there is nothing to show yet - the stream is still opening, or
    /// it has run dry mid-play - over the last frame rather than a black cover, so
    /// a stall reads as loading. Never for a video that failed.
    func updateBufferingState() {
        guard let playerItem,
              player?.currentItem === playerItem,
              !didFail,
              playerItem.status != .failed
        else {
            activityIndicator.stopAnimating()
            return
        }

        let isWaiting = playerItem.status != .readyToPlay
            || player?.timeControlStatus == .waitingToPlayAtSpecifiedRate

        isWaiting ? activityIndicator.startAnimating() : activityIndicator.stopAnimating()
    }

    func stopAndRestartVideo() {
        player?.seek(to: .zero)
    }

    func stopVideo() {
        if player?.timeControlStatus == .playing {
            player?.pause()
            player?.seek(to: .zero)
        }
    }

    func restartVideo() {
        if player?.timeControlStatus == .paused {
            player?.seek(to: .zero)
            player?.play()
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
        releasePlayer()
        self.player = nil
    }

    /// Posted on whatever thread the player was working on.
    @objc
    func failedToPlayToEndObserver(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, (notification.object as? AVPlayerItem) === self.playerItem else { return }
            self.handleFailure()
            self.updateBufferingState()
        }
    }
}

// MARK: - Setup Func

private extension PlayerView {
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

    /// Installed once, above the video. This used to build a fresh full-screen
    /// cover and spinner on every load and pin the spinner with `superview!`.
    func setupActivityIndicator() {
        activityIndicator.color = UIColor.lightGray.withAlphaComponent(0.7)
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
}
