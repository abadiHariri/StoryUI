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
        .onReceive(timer) { _ in
            // Checked every tick (rather than relying solely on onChange(of:))
            // since isPaused is often a computed Binding crossing into the
            // custom fullscreen window, where onChange doesn't reliably fire.
            if isPaused != lastAppliedPauseState {
                lastAppliedPauseState = isPaused
                configureProgress(with: isPaused)
            }
            guard !isPaused else { return }
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
        HStack {
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
        guard !isPaused else { return }

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
