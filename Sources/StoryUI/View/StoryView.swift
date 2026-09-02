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
    @State private var storySize: CGSize = .zero
    /// A finger is down right now. Distinct from `viewModel.isDragging`, which
    /// stays true through the snap-back animation after the finger has lifted.
    @State private var isDragActive = false

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
                    // Hidden while holding, and for the whole dismiss drag.
                    // Driven by booleans, never by the per-frame drag offset:
                    // an implicit animation re-triggered every frame queues
                    // overlapping animations and is itself a source of judder.
                    .opacity(viewModel.isHolding || viewModel.isDragging ? 0 : 1)
                    .animation(.easeOut(duration: 0.2), value: viewModel.isHolding)
                    .animation(.easeOut(duration: 0.2), value: viewModel.isDragging)
                }
                .ignoresSafeArea()
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Measured rather than assumed: UIScreen.main.bounds is the device,
                // not this view. Any mismatch skews the circle styles (which square
                // the frame using width/height) and the fly-away distance.
                // Read before the transforms below, so it stays the layout size.
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { storySize = proxy.size }
                            .onChange(of: proxy.size) { storySize = $0 }
                    }
                )
                // Story, footer and chrome move as one unit, like the host's
                // fullscreen image gallery.
                .modifier(StoryDismissTransformModifier(style: dismissStyle, transform: transform))
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

    private var effectiveSize: CGSize {
        storySize.width > 0 && storySize.height > 0 ? storySize : UIScreen.main.bounds.size
    }

    /// One resolved value for the whole drag, so every modifier below reads from a
    /// single source and cannot disagree with the others mid-animation.
    private var transform: StoryDismissStyle.Transform {
        dismissStyle.transform(offset: dragOffset, size: effectiveSize, rubberBand: !isFlyingAway)
    }

    private func dragChanged(_ translation: CGFloat) {
        guard !isFlyingAway else { return }
        if !isDragActive {
            isDragActive = true
            // Keyed on the finger, not on `isDragging`: starting a second drag
            // during the snap-back would otherwise skip this, leaving the pending
            // unfreeze and resume to fire in the middle of the new drag.
            viewModel.beginDismissDrag()
        }
        // The snap-back spring may still be running. Without this the assignment
        // inherits that animation and the story eases toward the finger instead of
        // tracking it, arriving in a catch-up lurch.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragOffset = translation
        }
        // Reported straight to the host, never stored in the observed object: a
        // @Published write here would re-render every StoryDetailView - and every
        // GeometryReader and AVPlayer in them - on every frame of the drag.
        onDismissProgress?(min(1, abs(transform.offset) / Constant.dismissCommitDistance))
    }

    private func dragEnded(_ translation: CGFloat, _ velocity: CGFloat) {
        isDragActive = false
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

        // Adopt the current ON-SCREEN position before turning the rubber band off,
        // so switching to un-banded offsets is continuous rather than a step.
        let settled = transform.offset
        isFlyingAway = true
        var adopt = Transaction()
        adopt.disablesAnimations = true
        withTransaction(adopt) { dragOffset = settled }

        viewModel.commitDismissDrag()
        onDismissProgress?(1)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        withAnimation(.spring(response: 0.15, dampingFraction: 0.85)) {
            dragOffset = settled < 0 ? -effectiveSize.height : effectiveSize.height
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
