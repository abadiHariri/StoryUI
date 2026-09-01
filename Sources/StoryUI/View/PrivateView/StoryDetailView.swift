//
//  SwiftUIView.swift
//
//
//  Created by Tolga İskender on 1.05.2022.
//

import SwiftUI
import AVKit

struct StoryDetailView: View {
    // MARK: Public Properties
    @ObservedObject var viewModel: StoryViewModel

    @State var model: StoryUIModel
    @Binding var isPresented: Bool
    @Binding var isPaused: Bool

    @State var timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @State var timerProgress: CGFloat = 0

    // MARK: Private Properties
    @ObservedObject private var keyboardManager = KeyboardManager()
    @State private var state: MediaState = .notStarted
    @State private var player = AVPlayer()
    @State private var animate = false
    @State private var startAnimate = false
    @State private var lastAppliedPauseState: Bool = false
    @State private var isTapDisabled: Bool = false

    // MARK: Press-and-hold to pause
    /// True from touch-down until lift, drift past `holdMovementTolerance`, or
    /// system cancellation. `@GestureState` reverts on all three, which is the
    /// entire release + interruption path - no timers, nothing to leak when the
    /// host tears the story down mid-drag.
    @GestureState private var isPressing: Bool = false
    /// When the current touch went down; nil when no finger is on the story.
    @State private var pressStartedAt: Date?
    /// True only once a press has outlasted `Constant.holdToPauseDuration`, i.e.
    /// the story is paused *because of* the hold. The input to `effectivePaused`.
    @State private var isHolding: Bool = false
    /// Latched when a hold engages. Swallows the trailing tap that fires when the
    /// finger lifts.
    @State private var suppressNextTap: Bool = false

    var body: some View {

        GeometryReader { proxy in
            let index = getCurrentIndex()
            let story = model.stories[index]
            ZStack {
                if model.stories.count > index {
                    VStack(spacing: 8) {
                        getStoryView(with: index, story: story)
                            .overlay(
                                tapStory()
                            )
                    }
                }
            }
            .ignoresSafeArea()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .overlay(
                getProgressBar(with: index)
                ,alignment: .top
            )
            .rotation3DEffect(
                getAngle(proxy: proxy),
                axis: (x: 0, y: 1, z: 0),
                anchor: proxy.frame(in: .global).minX > 0 ? .leading : .trailing,
                perspective: 2.5
            )
        }
        .onChange(of: viewModel.currentStoryUser) { newValue in
            NotificationCenter.default.post(name: .stopVideo, object: nil)
            resetProgress()
            playVideo()
        }
        .onChange(of: isPressing) { pressing in
            // isPressing is local @GestureState, so unlike `isPaused` this
            // onChange IS reliable - it never crosses the custom fullscreen
            // window boundary that motivated the polling below.
            if pressing {
                // A brand new touch sequence. Clear the swallow latch here so it
                // can never outlive the press that set it.
                suppressNextTap = false
                pressStartedAt = Date()
            } else {
                pressStartedAt = nil
                // Resume on the same runloop turn as the lift rather than up to
                // 100ms later. Safe because it goes through the one edge detector.
                endHoldIfNeeded()
            }
        }
        .onDisappear {
            // Page recycling or a completed drag-to-dismiss can tear the view
            // down mid-hold. Nothing to resume afterwards, but leave no latch.
            endHoldIfNeeded()
        }
        .onReceive(timer) { _ in
            // Level-triggered, so it is self-healing: if a release edge were ever
            // dropped, the next tick recomputes the hold from `isPressing` alone
            // and clears it within 100ms.
            updateHoldState()
            // Checked every tick (rather than relying solely on onChange(of:))
            // since isPaused is often a computed Binding crossing into the
            // custom fullscreen window, where onChange doesn't reliably fire.
            applyPauseStateIfNeeded()
            guard !effectivePaused else { return }
            startProgress()
        }
    }
}

// MARK: Private Configuration
private extension StoryDetailView {

    @ViewBuilder
    func getStoryView(with index: Int, story: Story) -> some View {
        switch story.config.mediaType {
        case .image:
            ImageView(imageURL: story.mediaURL) {
                start(index: index)
            }
            .onAppear {
                resetAVPlayer()
            }
        case .video:
            VideoView(
                videoURL: story.mediaURL,
                state: $state,
                player: player
            ) { media, duration in
                model.stories[index].duration = duration
                start(index: index)
                state = media
            }
            .onChange(of: state) { _ in
                playVideo()
            }
        }
    }

    @ViewBuilder
    func getProgressBar(with index: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Constant.progressBarSpacing) {
                ForEach(model.stories.indices) { index in
                    ProgressBarView(
                        timerProgress: timerProgress,
                        index: index
                    )
                }
            }
            .padding(.horizontal, 16)

            closeIcon()
        }
    }

    @ViewBuilder
    func closeIcon() -> some View {
        HStack {
            Spacer()
            Button {
                isPresented.toggle()
            } label: {
                Image(systemName: "xmark")
                    .renderingMode(.template)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .padding(.horizontal, 8)
                    .padding(.top)
            }
        }
    }


    @ViewBuilder
    func tapStory() -> some View {
        // spacing: 0 - the default 8pt gap was a dead strip down the middle of
        // the screen where taps did nothing, and would be one for holds too.
        HStack(spacing: 0) {
            Rectangle()
                .fill(.black.opacity(0.01))
                .onTapGesture {
                    tapPreviousStory()
                }
            Rectangle()
                .fill(.black.opacity(0.01))
                .onTapGesture {
                    tapNextStory()
                }
        }
        // On the CONTAINER, not on each Rectangle: one press signal for the whole
        // media area, and a parent gesture composing with its children's is
        // well-defined where two gesture modifiers on one view are not.
        // .simultaneousGesture requires nothing to fail and blocks nothing, so
        // tap-to-advance, the TabView page pan and a host's drag-to-dismiss all
        // keep exactly the behaviour they have today.
        // Never use .highPriorityGesture here - it would let this pre-empt the
        // child taps and ask SwiftUI to win arbitration against the page pan.
        .simultaneousGesture(holdToPauseGesture)
    }

    /// A `LongPressGesture` that can never succeed, used purely as a touch-down /
    /// touch-up signal.
    ///
    /// The `updating` closure deliberately ignores `currentState` and writes an
    /// unconditional `true`, so the only behaviour relied on is `@GestureState`'s
    /// documented revert-on-end-or-cancel - not what `LongPressGesture.Value`
    /// happens to mean mid-press.
    ///
    /// Because it never recognizes it performs no action, never competes with the
    /// tap gestures, and `maximumDistance` keeps being enforced for the *entire*
    /// touch rather than only up to recognition (which is where UIKit's
    /// `UILongPressGestureRecognizer.allowableMovement` gives up).
    var holdToPauseGesture: some Gesture {
        LongPressGesture(
            minimumDuration: Constant.holdGestureMaxDuration,
            maximumDistance: Constant.holdMovementTolerance
        )
        .updating($isPressing) { _, state, _ in
            state = true
        }
    }

    /// Host pause OR press-and-hold. The single source of truth for "should this
    /// story be frozen right now". Every pause decision reads this and nothing
    /// else - that is what makes releasing a hold unable to resume a story the
    /// host is holding paused.
    var effectivePaused: Bool {
        isPaused || isHolding
    }

    /// Level-triggered on `isPressing`, so a dropped release edge heals itself.
    func updateHoldState() {
        let shouldHold: Bool = {
            guard isPressing, let started = pressStartedAt else { return false }
            return Date().timeIntervalSince(started) >= Constant.holdToPauseDuration
        }()
        guard shouldHold != isHolding else { return }
        isHolding = shouldHold
        // Invariant: the swallow latch is armed exactly when the story actually
        // paused from a hold - same line, same condition. A press that never
        // crossed the threshold arms nothing and pauses nothing.
        if shouldHold { suppressNextTap = true }
    }

    func endHoldIfNeeded() {
        guard isHolding else { return }
        isHolding = false
        applyPauseStateIfNeeded()
    }

    /// The ONE writer of `lastAppliedPauseState` and the ONE caller of
    /// `configureProgress(with:)`. Idempotent, so the eager release path and the
    /// 0.1s tick can never double-apply, and neither can resume behind a host
    /// pause: with `isPaused` true there is simply no edge to act on.
    func applyPauseStateIfNeeded() {
        let paused = effectivePaused
        guard paused != lastAppliedPauseState else { return }
        lastAppliedPauseState = paused
        configureProgress(with: paused)
    }

    /// `isHolding`       -> the tap was delivered before the release edge ran.
    /// `suppressNextTap` -> a hold engaged during the sequence that produced it.
    ///
    /// Clearing on consume *as well as* at the next touch-down bounds the damage
    /// to exactly one tap in the pathological case where a touch-down is
    /// coalesced away (a synthetic/UI-test tap in a single runloop turn).
    func shouldSwallowTapAfterHold() -> Bool {
        guard isHolding || suppressNextTap else { return false }
        suppressNextTap = false
        return true
    }

    func getAngle(proxy: GeometryProxy) -> Angle {
        let rotation: CGFloat = 45
        let progress = proxy.frame(in: .global).minX / proxy.size.width
        let degrees = rotation * progress
        return Angle(degrees: degrees)
    }

    func resetProgress() {
        timerProgress = 0
    }

    func getPreviousStory() {

        if let first = viewModel.stories.first, first.id != model.id {

            let bundleIndex = viewModel.stories.firstIndex { currentBundle in
                return model.id == currentBundle.id
            } ?? 0

            withAnimation {
                viewModel.currentStoryUser = viewModel.stories[bundleIndex - 1].id
            }
        } else {
            let index = getCurrentIndex()
            let story = getStory(with: index)
            if story.config.mediaType == .video {
                NotificationCenter.default.post(name: .stopAndRestartVideo, object: nil)
                resetProgress()
            }
        }
        return
    }

    func getNextStory() {
        let index = getCurrentIndex()
        let story = getStory(with: index)

        if let last = model.stories.last, last.id == story.id {
            if let lastBundle = viewModel.stories.last, lastBundle.id == model.id {
                withAnimation {
                    dissmis()
                }
            } else {
                let bundleIndex = viewModel.stories.firstIndex { currentBundle in
                    return model.id == currentBundle.id
                } ?? 0

                withAnimation {
                    viewModel.currentStoryUser = viewModel.stories[bundleIndex + 1].id
                }
            }
        }
    }

    func startProgress() {
        guard !effectivePaused else { return }

        let index = getCurrentIndex()
        let story = getStory(with: index)

        if viewModel.currentStoryUser == model.id {
            if !model.isSeen {
                model.isSeen = true
            }
            if timerProgress < CGFloat(model.stories.count) {
                if story.isReady {
                    getProgressBarFrame(duration: story.duration)
                }
            } else {
                updateStory()
            }
        }
    }

    func updateStory(direction: StoryDirectionEnum = .next) {
        if direction == .previous {
            getPreviousStory()
        } else {
            getNextStory()
        }
    }

    func tapNextStory() {
        guard !shouldSwallowTapAfterHold() else { return }
        configureTapScreen()
        guard !isTapDisabled else { return }
        if (timerProgress + 1) > CGFloat(model.stories.count) {
            //next user
            updateStory()
        } else {
            //next Story
            timerProgress = CGFloat(Int(timerProgress + 1))
        }
    }

    func tapPreviousStory() {
        guard !shouldSwallowTapAfterHold() else { return }
        configureTapScreen()
        guard !isTapDisabled else { return }
        if (timerProgress - 1) < 0 {
            updateStory(direction: .previous)
        } else {
            timerProgress = CGFloat(Int(timerProgress - 1))
        }
    }

    func start(index: Int) {
        if !model.stories[index].isReady {
            model.stories[index].isReady = true
        }
    }

    func getProgressBarFrame(duration: Double) {
        let calculatedDuration = viewModel.getVideoProgressBarFrame(duration: duration)
        timerProgress += (0.01 / calculatedDuration)
    }

    func dissmis() {
        isPresented = false
        NotificationCenter.default.post(name: .replaceCurrentItem, object: nil)
    }

    func getCurrentIndex() -> Int {
        return min(Int(timerProgress), model.stories.count - 1)
    }

    func getStory(with index: Int) -> Story {
        return model.stories[index]
    }

    func resetAVPlayer() {
        Task {
            player.pause()
        }
        player = AVPlayer()
    }

    func pauseVideo() {
        player.pause()
    }

    func playVideo() {
        // playVideo() is also reached from .onChange(of: viewModel.currentStoryUser)
        // and .onChange(of: state) (driven by PlayerView's timeControlStatus KVO
        // in VideoLoader), neither of which consults the pause state. Without this
        // guard a video that finishes buffering *during* a pause resumes audio
        // behind a frozen progress bar.
        guard !effectivePaused else { return }

        let index = getCurrentIndex()
        let currentUser = viewModel.currentStoryUser == model.id
        let video = model.stories[index].config.mediaType == .video
        let isReady = state == .ready || state == .started

        if isReady, currentUser, video {
            player.automaticallyWaitsToMinimizeStalling = false
            Task {
                player.play()
            }
        }
    }

    func configureTapScreen() {
        switch (keyboardManager.isKeyboardOpen, isPaused) {
        case (true, _):
            isTapDisabled = true
        case (false, true):
            isTapDisabled = true
        default:
            isTapDisabled = false
        }
    }

    func configureProgress(with state: Bool) {
        let index = getCurrentIndex()
        let story = model.stories[index]
        let mediaType = story.config.mediaType
        if state, mediaType == .video {
            pauseVideo()
        } else if !state, mediaType == .video {
            guard viewModel.currentStoryUser == model.id else { return }
            playVideo()
        }
    }
}
