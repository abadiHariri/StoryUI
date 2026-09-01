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
    ///   - onDismissProgress: 0...1 as the story is dragged away, for hosts that fade their own chrome
    ///   - onDismiss: called once a dismiss drag commits, after the fly-away animation
    ///   - footer: host-supplied overlay rendered at the bottom of the currently visible story
    public init(
        stories: [StoryUIModel],
        selectedIndex: Int = 0,
        isPresented: Binding<Bool>,
        isPaused: Binding<Bool> = .constant(false),
        isDragToDismissEnabled: Bool = true,
        onDismissProgress: ((CGFloat) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder footer: @escaping (StoryUIModel) -> Footer
    ) {
        self.stories = stories
        self.selectedIndex = selectedIndex
        self._isPresented = isPresented
        self.isPaused = isPaused
        self.isDragToDismissEnabled = isDragToDismissEnabled
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
                    .opacity(backdropOpacity)
                    .ignoresSafeArea()

                ZStack {
                    TabView(selection: $viewModel.currentStoryUser) {
                        ForEach(viewModel.stories) { model in
                            StoryDetailView(
                                viewModel: viewModel,
                                model: model,
                                isPresented: $isPresented,
                                isPaused: isPaused
                            )
                        }
                    }
                    VStack {
                        Spacer()
                        if let model = viewModel.getStoryModel() {
                            footer(model)
                        }
                    }
                }
                .ignoresSafeArea()
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Story, footer and chrome move as one unit, like the host's
                // fullscreen image gallery.
                .scaleEffect(storyScale)
                .offset(y: dragOffset)
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

    private var dragDistance: CGFloat { abs(dragOffset) }

    private var storyScale: CGFloat {
        guard !isFlyingAway else { return Constant.dismissFinalScale }
        return max(Constant.dismissFinalScale, 1 - dragDistance / Constant.dismissScaleDivisor)
    }

    private var backdropOpacity: CGFloat {
        guard !isFlyingAway else { return 0 }
        return max(0, 1 - dragDistance / Constant.dismissOpacityDivisor)
    }

    private func dragChanged(_ translation: CGFloat) {
        guard !isFlyingAway else { return }
        // Freezes the story for the whole drag, the same way a press-and-hold does.
        if !viewModel.isDragging {
            viewModel.isDragging = true
        }
        dragOffset = translation
        onDismissProgress?(min(1, dragDistance / Constant.dismissCommitDistance))
    }

    private func dragEnded(_ translation: CGFloat, _ velocity: CGFloat) {
        guard !isFlyingAway else { return }

        let commits = abs(translation) > Constant.dismissCommitDistance
            || abs(velocity) > Constant.dismissCommitVelocity

        guard commits else {
            // Snap back, then let the story run again.
            withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                dragOffset = 0
            }
            onDismissProgress?(0)
            viewModel.isDragging = false
            return
        }

        isFlyingAway = true
        onDismissProgress?(1)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        withAnimation(.spring(response: 0.15, dampingFraction: 0.85)) {
            dragOffset = translation < 0 ? -UIScreen.main.bounds.height : UIScreen.main.bounds.height
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
        onDismissProgress: ((CGFloat) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.init(
            stories: stories,
            selectedIndex: selectedIndex,
            isPresented: isPresented,
            isPaused: isPaused,
            isDragToDismissEnabled: isDragToDismissEnabled,
            onDismissProgress: onDismissProgress,
            onDismiss: onDismiss
        ) { _ in EmptyView() }
    }
}
