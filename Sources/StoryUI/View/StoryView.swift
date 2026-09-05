//
//  StoryView.swift
//  StoryUI (iOS)
//
//  Created by Tolga İskender on 28.04.2022.
//

import SwiftUI
import AVFoundation

/// The story viewer, generic over the host's own model.
///
/// `Item` is whatever type the host conformed to `StoryUIRepresentable`. It goes
/// in through `stories` and comes back out through `footer` unchanged - there is
/// no model to build, nothing to map and nothing to look back up.
public struct StoryView<Item: StoryUIRepresentable, Footer: View>: View {

    @StateObject private var viewModel = StoryViewModel<Item>()
    @Binding private var isPresented: Bool
    private var isPaused: Binding<Bool>

    // Private properties
    private var stories: [Item]
    private var selectedIndex: Int
    private var footer: (Item) -> Footer
    private var isDragToDismissEnabled: Bool
    private var transitionStyle: StoryTransitionStyle
    private var dismissStyle: StoryDismissStyle
    private var imageDuration: TimeInterval
    private var imageContentMode: StoryContentMode
    private var videoContentMode: StoryContentMode
    private var onDismissProgress: ((CGFloat) -> Void)?
    private var onDismiss: (() -> Void)?

    /// Index into `stories` of the bundle currently on screen. Kept in step with
    /// `viewModel.currentStoryUser` so the footer lookup is O(1) per render.
    @State private var currentItemIndex: Int = 0

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
    ///   - onDismiss: called on EVERY path that closes the story - a committed dismiss
    ///     drag, the close button, and running past the last story - and always BEFORE
    ///     `isPresented` flips. A host that presents this view itself should tear its
    ///     presentation down here rather than by observing `isPresented`: `body` is
    ///     `if isPresented`, so the flip removes this subtree, and an `onChange` edge on
    ///     the binding can be coalesced away when the main thread is loaded - leaving the
    ///     presentation mounted with nothing left to remove it.
    ///   - footer: host-supplied overlay rendered at the bottom of the currently visible story
    public init(
        stories: [Item],
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
        @ViewBuilder footer: @escaping (Item) -> Footer
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
            // Everything that changes with the finger lives in the container, so
            // this body no longer depends on the drag offset. A drag frame updates
            // two modifiers in there instead of rebuilding the TabView, the
            // ForEach over every bundle and the footer, 60-120 times a second.
            StoryDismissContainer(
                style: dismissStyle,
                isDragToDismissEnabled: isDragToDismissEnabled,
                onTouchActiveChanged: viewModel.setTouchActive,
                onDragBegan: viewModel.beginDismissDrag,
                onDragCancelled: viewModel.cancelDismissDrag,
                onDragCommitted: viewModel.commitDismissDrag,
                onProgress: onDismissProgress,
                onDismiss: {
                    stopVideo()
                    requestDismiss()
                }
            ) {
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
                                videoContentMode: videoContentMode,
                                onDismiss: onDismiss
                            )
                            .addGeometryGroup()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .addGeometryGroup()
                        }
                    }
                    .addGeometryGroup()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .addGeometryGroup()
                    
                    VStack {
                        
                        if let item = currentItem {
                            footer(item)
                        }
                        
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .addGeometryGroup()
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .ignoresSafeArea()
            .onAppear() {
                startStory()
            }
            // Once per page change, so `currentItem` stays an index lookup during
            // the drag rather than a scan of the host's array on every frame.
            .onChange(of: viewModel.currentStoryUser) { _ in
                updateCurrentItemIndex()
            }
            .onDisappear() {
                stopVideo()
            }
        }
    }

    /// The host's own model for the bundle on screen, handed straight back to the
    /// footer closure - no id lookup on the host's side, no cast.
    ///
    /// Read from `stories` - the array the host is passing in RIGHT NOW - rather
    /// than from the snapshot in `viewModel`, which is built once on appear and
    /// deliberately never rebuilt (rebuilding it would throw away every bundle's
    /// runtime state and reset the pager). So when the host's own source of truth
    /// changes - a like lands, a count updates - the footer re-renders with it.
    ///
    /// The common path is one index and one `storyId` read. The scan is only the
    /// fallback for when the host has reordered the array underneath us.
    private var currentItem: Item? {
        if stories.indices.contains(currentItemIndex),
           stories[currentItemIndex].storyId == viewModel.currentStoryUser {
            return stories[currentItemIndex]
        }
        return stories.first { $0.storyId == viewModel.currentStoryUser }
    }

    /// Resolved once per page change rather than once per render.
    private func updateCurrentItemIndex() {
        currentItemIndex = stories.firstIndex { $0.storyId == viewModel.currentStoryUser } ?? 0
    }

    /// Builds the runtime state for every bundle, exactly once.
    ///
    /// This is the only place a `StoryUIModel` is ever created. It pairs each of
    /// the host's models with the state the viewer mutates while it plays; the
    /// host's model itself is carried along untouched. `storyId` and `storyMedia`
    /// are read exactly once per bundle here, so both are free to be computed
    /// properties that rebuild on access.
    private func startStory() {
        let bundles = stories.map { StoryUIModel($0) }

        // A bundle with no media has nothing to show, no duration to run and no
        // index to clamp to - `getCurrentIndex()` would return -1 and the page
        // would trap on its first render. Skipping it here is what lets a host
        // hand over its raw array without pre-filtering it.
        let playable = bundles.enumerated().filter { !$0.element.stories.isEmpty }
        guard !playable.isEmpty else { return }

        viewModel.stories = playable.map { $0.element }

        // `selectedIndex` indexes what the HOST passed, so resolve it there first
        // and then map it across the filter. Landing on the next playable bundle
        // (rather than on the first) is what keeps the tapped story correct when
        // an earlier bundle was skipped.
        let requested = stories.indices.contains(selectedIndex) ? selectedIndex : .zero
        let index = playable.firstIndex { $0.offset >= requested } ?? playable.count - 1

        viewModel.currentStoryUser = viewModel.stories[index].id
        viewModel.stories[index].isSeen = true
        updateCurrentItemIndex()
    }

    /// The single exit. Every path that closes the story - this one, the close button
    /// and running past the last story - goes through here, so the host is told before
    /// the binding flips and can remove its own presentation directly.
    private func requestDismiss() {
        onDismiss?()
        isPresented = false
    }

    private func stopVideo() {
        // `NotificationCenter.default.removeObserver(self)` used to follow this.
        // `self` is a struct, so it was bridged into a fresh `__SwiftValue` box - a
        // full copy of the view value, `stories` and closures included - to remove a
        // registration `StoryView` never makes. Observers of this notification are
        // owned by `PlayerView`, which removes its own.
        NotificationCenter.default.post(name: .stopVideo, object: nil)
    }
}

public extension StoryView where Footer == EmptyView {
    init(
        stories: [Item],
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

fileprivate extension View {

   
    
    @ViewBuilder func addGeometryGroup() -> some View {
        if #available(iOS 17.0, *) {
            geometryGroup()
        } else {
            self
        }
    }
}
   
