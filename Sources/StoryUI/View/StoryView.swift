//
//  StoryView.swift
//  StoryUI (iOS)
//
//  Created by Tolga İskender on 28.04.2022.
//

import SwiftUI
import AVFoundation

public struct StoryView<Footer: View>: View {

    @StateObject private var viewModel = StoryViewModel()
    @Binding private var isPresented: Bool
    private var isPaused: Binding<Bool>

    // Private properties
    private var stories: [StoryUIModel]
    private var selectedIndex: Int
    private var footer: (StoryUIModel) -> Footer
    private var isDragToDismissEnabled: Bool
    private var transitionStyle: StoryTransitionStyle
    private var dismissStyle: StoryDismissStyle
    private var imageDuration: TimeInterval
    private var imageContentMode: StoryContentMode
    private var videoContentMode: StoryContentMode
    private var onDismissProgress: ((CGFloat) -> Void)?
    private var onDismiss: (() -> Void)?

    // Drag to dismiss
    @State private var dragOffset: CGFloat = 0
    @State private var isFlyingAway = false

    /// Stories and isPresented required, selectedIndex is optional default: 0
    /// - Parameters:
    ///   - stories: all stories to show
    ///   - selectedIndex: current story index selected by user
    ///   - isPresented: to hide and show for closing storyView
    ///   - isPaused: pauses the auto-advance timer and video playback, e.g. while the host presents a sheet on top of the story
    ///   - isDragToDismissEnabled: set false to suppress drag-to-dismiss, e.g. while the story is zoomed
    ///   - transitionStyle: how bundles look as they move between pages, on swipe and on auto-advance
    ///   - dismissStyle: how the story looks while being dragged away
    ///   - imageDuration: how long an image stays on screen before auto-advancing; a story can override
    ///     it via `StoryConfiguration(mediaType:imageDuration:)`. Video always runs its own length.
    ///   - imageContentMode: how images are scaled into the frame; per-story override via `StoryConfiguration`
    ///   - videoContentMode: how video is scaled into the frame; per-story override via `StoryConfiguration`
    ///   - onDismissProgress: 0...1 as the story is dragged away, for hosts that fade their own chrome
    ///   - onDismiss: called once a dismiss drag commits, after the fly-away animation
    ///   - footer: host-supplied overlay rendered at the bottom of the currently visible story
    public init(
        stories: [StoryUIModel],
        selectedIndex: Int = 0,
        isPresented: Binding<Bool>,
        isPaused: Binding<Bool> = .constant(false),
        isDragToDismissEnabled: Bool = true,
        transitionStyle: StoryTransitionStyle = .cube(),
        dismissStyle: StoryDismissStyle = .scale(),
        imageDuration: TimeInterval = 5,
        imageContentMode: StoryContentMode = .fit,
        videoContentMode: StoryContentMode = .fill,
        onDismissProgress: ((CGFloat) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder footer: @escaping (StoryUIModel) -> Footer
    ) {
        self.stories = stories
        self.selectedIndex = selectedIndex
        self._isPresented = isPresented
        self.isPaused = isPaused
        self.isDragToDismissEnabled = isDragToDismissEnabled
        self.transitionStyle = transitionStyle
        self.dismissStyle = dismissStyle
        self.imageDuration = imageDuration
        self.imageContentMode = imageContentMode
        self.videoContentMode = videoContentMode
        self.onDismissProgress = onDismissProgress
        self.onDismiss = onDismiss
        self.footer = footer
    }

    public var body: some View {
        if isPresented {
            ZStack {
                // Outside the transformed subtree and no longer opaque: as an
                // opaque child it hid whatever the host painted behind the story,
                // so a backdrop fade was invisible however the host animated it.
                Color.black
                    .opacity(transform.backdropOpacity)
                    .ignoresSafeArea()

                ZStack {
                    TabView(selection: $viewModel.currentStoryUser) {
                        ForEach(viewModel.stories) { model in
                            StoryDetailView(
                                viewModel: viewModel,
                                model: model,
                                isPresented: $isPresented,
                                isPaused: isPaused,
                                transitionStyle: transitionStyle,
                                imageDuration: imageDuration,
                                imageContentMode: imageContentMode,
                                videoContentMode: videoContentMode
                            )
                        }
                    }
                    VStack {
                        Spacer()
                        if let model = viewModel.getStoryModel() {
                            footer(model)
                        }
                    }
                    // Host chrome goes away entirely while holding; only the
                    // progress bar stays, since it is what shows the story frozen.
                    .opacity(chromeOpacity)
                    .animation(.easeOut(duration: 0.2), value: chromeOpacity)
                }
                .ignoresSafeArea()
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Story, footer and chrome move as one unit, like the host's
                // fullscreen image gallery. The modifier set is fixed for every
                // dismiss style so switching style never changes view identity.
                .clipShape(StoryRoundnessShape(roundness: transform.roundness))
                .overlay(
                    Color.black
                        .opacity(transform.dim)
                        .allowsHitTesting(false)
                )
                .scaleEffect(x: transform.scaleX, y: transform.scaleY)
                .rotationEffect(transform.rotation)
                .offset(y: transform.offset)
                .storyDismissGesture(
                    isEnabled: isDragToDismissEnabled && !isFlyingAway,
                    onChanged: dragChanged,
                    onEnded: dragEnded
                )
            }
            .ignoresSafeArea()
            .onAppear() {
                startStory()
            }
            .onDisappear() {
                stopVideo()
            }
        }
    }

    // MARK: Drag to dismiss

    private var screenSize: CGSize { UIScreen.main.bounds.size }

    /// One resolved value for the whole drag, so every modifier below reads from a
    /// single source and cannot disagree with the others mid-animation.
    private var transform: StoryDismissStyle.Transform {
        isFlyingAway
            ? dismissStyle.committedTransform(offset: dragOffset, size: screenSize)
            : dismissStyle.transform(offset: dragOffset, size: screenSize)
    }

    private var chromeOpacity: CGFloat {
        if viewModel.isHolding { return 0 }
        return max(0, 1 - viewModel.dismissProgress)
    }

    private func dragChanged(_ translation: CGFloat) {
        guard !isFlyingAway else { return }
        if !viewModel.isDragging {
            viewModel.beginDismissDrag()
        }
        dragOffset = translation
        let progress = min(1, abs(transform.offset) / Constant.dismissCommitDistance)
        viewModel.dismissProgress = progress
        onDismissProgress?(progress)
    }

    private func dragEnded(_ translation: CGFloat, _ velocity: CGFloat) {
        guard !isFlyingAway else { return }

        let commits = abs(transform.offset) > Constant.dismissCommitDistance
            || abs(velocity) > Constant.dismissCommitVelocity

        guard commits else {
            withAnimation(.spring(response: Constant.dismissSnapBackDuration, dampingFraction: 0.85)) {
                dragOffset = 0
            }
            onDismissProgress?(0)
            // Unfreezes page transitions once the spring settles, and resumes the
            // story a few seconds later rather than the instant the finger lifts.
            viewModel.cancelDismissDrag()
            return
        }

        isFlyingAway = true
        viewModel.commitDismissDrag()
        onDismissProgress?(1)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        withAnimation(.spring(response: 0.15, dampingFraction: 0.85)) {
            dragOffset = translation < 0 ? -screenSize.height : screenSize.height
        }

        // body is `if isPresented`, so the fly-away has to finish before the flip
        // - otherwise the story vanishes instead of leaving.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            stopVideo()
            onDismiss?()
            isPresented = false
        }
    }

    private func startStory() {
        guard !stories.isEmpty else { return }

        viewModel.stories = stories

        let index = stories.indices.contains(selectedIndex) ? selectedIndex : .zero
        let storyUser = stories[index]

        viewModel.currentStoryUser = storyUser.id

        if !storyUser.stories.isEmpty {
            viewModel.stories[index].isSeen = true
        }
    }

    private func stopVideo() {
        NotificationCenter.default.post(name: .stopVideo, object: nil)
        NotificationCenter.default.removeObserver(self)
    }
}

public extension StoryView where Footer == EmptyView {
    init(
        stories: [StoryUIModel],
        selectedIndex: Int = 0,
        isPresented: Binding<Bool>,
        isPaused: Binding<Bool> = .constant(false),
        isDragToDismissEnabled: Bool = true,
        transitionStyle: StoryTransitionStyle = .cube(),
        dismissStyle: StoryDismissStyle = .scale(),
        imageDuration: TimeInterval = 5,
        imageContentMode: StoryContentMode = .fit,
        videoContentMode: StoryContentMode = .fill,
        onDismissProgress: ((CGFloat) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.init(
            stories: stories,
            selectedIndex: selectedIndex,
            isPresented: isPresented,
            isPaused: isPaused,
            isDragToDismissEnabled: isDragToDismissEnabled,
            transitionStyle: transitionStyle,
            dismissStyle: dismissStyle,
            imageDuration: imageDuration,
            imageContentMode: imageContentMode,
            videoContentMode: videoContentMode,
            onDismissProgress: onDismissProgress,
            onDismiss: onDismiss
        ) { _ in EmptyView() }
    }
}
