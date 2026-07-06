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

    /// Stories and isPresented required, selectedIndex is optional default: 0
    /// - Parameters:
    ///   - stories: all stories to show
    ///   - selectedIndex: current story index selected by user
    ///   - isPresented: to hide and show for closing storyView
    ///   - isPaused: pauses the auto-advance timer and video playback, e.g. while the host presents a sheet on top of the story
    ///   - footer: host-supplied overlay rendered at the bottom of the currently visible story
    public init(
        stories: [StoryUIModel],
        selectedIndex: Int = 0,
        isPresented: Binding<Bool>,
        isPaused: Binding<Bool> = .constant(false),
        @ViewBuilder footer: @escaping (StoryUIModel) -> Footer
    ) {
        self.stories = stories
        self.selectedIndex = selectedIndex
        self._isPresented = isPresented
        self.isPaused = isPaused
        self.footer = footer
    }

    public var body: some View {
        if isPresented {
            ZStack {
                Color.black
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
            .onAppear() {
                startStory()
            }
            .onDisappear() {
                stopVideo()
            }
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
        isPaused: Binding<Bool> = .constant(false)
    ) {
        self.init(
            stories: stories,
            selectedIndex: selectedIndex,
            isPresented: isPresented,
            isPaused: isPaused
        ) { _ in EmptyView() }
    }
}
