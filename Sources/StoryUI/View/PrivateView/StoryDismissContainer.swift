//
//  StoryDismissContainer.swift
//  StoryUI
//
//  Owns the drag-to-dismiss gesture and every piece of state that changes with
//  the finger, so that `StoryView.body` does not.
//
//  `StoryView.body` used to read `dragOffset` twice - once for the backdrop's
//  opacity, once for the transform modifier - and `dragChanged` writes that
//  `@State` on every pan callback. So a drag invalidated the WHOLE body 60-120
//  times a second: the `TabView`, the `ForEach` over every bundle, and the
//  footer, all rebuilt per frame for a value only two modifiers actually use.
//
//  The content is built ONCE, by the parent, and handed over as a value. When the
//  offset changes only this view's `body` re-runs, and it re-applies modifiers to
//  content it already has - SwiftUI never re-evaluates the parent's ViewBuilder.
//  A drag frame therefore updates two modifiers instead of rebuilding the page set.
//
//  Everything here moved across unchanged; the callbacks let the container stay
//  independent of the model layer and of `StoryViewModel`'s generic parameter.
//

import SwiftUI
import UIKit

struct StoryDismissContainer<Content: View>: View {

    let style: StoryDismissStyle
    /// The host's `isDragToDismissEnabled`. Combined with `isFlyingAway` here.
    let isDragToDismissEnabled: Bool

    /// A finger is on the story, on either axis - page swipes included.
    let onTouchActiveChanged: (Bool) -> Void
    /// A dismiss drag started moving.
    let onDragBegan: () -> Void
    /// Released without committing; the story springs back.
    let onDragCancelled: () -> Void
    /// Committed; nothing resumes.
    let onDragCommitted: () -> Void
    /// 0...1 as the story is dragged away, for hosts that fade their own chrome.
    let onProgress: ((CGFloat) -> Void)?
    /// The fly-away animation has finished and the story should now go.
    let onDismiss: () -> Void

    private let content: Content

    init(
        style: StoryDismissStyle,
        isDragToDismissEnabled: Bool,
        onTouchActiveChanged: @escaping (Bool) -> Void,
        onDragBegan: @escaping () -> Void,
        onDragCancelled: @escaping () -> Void,
        onDragCommitted: @escaping () -> Void,
        onProgress: ((CGFloat) -> Void)?,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.isDragToDismissEnabled = isDragToDismissEnabled
        self.onTouchActiveChanged = onTouchActiveChanged
        self.onDragBegan = onDragBegan
        self.onDragCancelled = onDragCancelled
        self.onDragCommitted = onDragCommitted
        self.onProgress = onProgress
        self.onDismiss = onDismiss
        self.content = content()
    }

    @State private var dragOffset: CGFloat = 0
    @State private var isFlyingAway = false
    /// A finger is down right now. Distinct from the view model's `isDragging`,
    /// which stays true through the snap-back animation after the finger lifts.
    @State private var isDragActive = false

    var body: some View {
        ZStack {
            // Outside the transformed subtree and no longer opaque: as an opaque
            // child it hid whatever the host painted behind the story, so a
            // backdrop fade was invisible however the host animated it.
            Color.black
                .opacity(transform.backdropOpacity)
                .ignoresSafeArea()

            content
                // Story, footer and chrome move as one unit, like the host's
                // fullscreen image gallery.
                .modifier(StoryDismissTransformModifier(style: style, transform: transform))
                .storyDismissGesture(
                    isEnabled: isDragToDismissEnabled && !isFlyingAway,
                    onActiveChanged: touchActiveChanged,
                    onChanged: dragChanged,
                    onEnded: dragEnded
                )
        }
        .onAppear {
            // Nothing may survive a presentation at a non-zero offset.
            dragOffset = 0
            isDragActive = false
            isFlyingAway = false
        }
    }

    // MARK: Drag to dismiss

    private var effectiveSize: CGSize { UIScreen.main.bounds.size }

    /// One resolved value for the whole drag, so every modifier above reads from a
    /// single source and cannot disagree with the others mid-animation.
    private var transform: StoryDismissStyle.Transform {
        style.transform(offset: dragOffset, size: effectiveSize, rubberBand: !isFlyingAway)
    }

    /// The pan can stop without ever delivering `.ended` to our handler - our own
    /// recognizer being disabled mid-drag does exactly that. When it happened,
    /// `dragOffset` was left stranded at whatever it had reached, so the story sat
    /// permanently shifted and permanently scaled: the progress bar ended up above
    /// the safe area, and every later frame kept paying for a non-identity
    /// transform. This is the safety net that guarantees it always returns to rest.
    private func touchActiveChanged(_ active: Bool) {
        onTouchActiveChanged(active)
        guard !active, !isFlyingAway, dragOffset != 0 else { return }
        settleDrag()
    }

    private func settleDrag() {
        isDragActive = false
        withAnimation(.spring(response: Constant.dismissSnapBackDuration, dampingFraction: 0.85)) {
            dragOffset = 0
        }
        onProgress?(0)
        onDragCancelled()
    }

    private func dragChanged(_ translation: CGFloat) {
        guard !isFlyingAway else { return }
        if !isDragActive {
            isDragActive = true
            // Keyed on the finger, not on `isDragging`: starting a second drag
            // during the snap-back would otherwise skip this, leaving the pending
            // unfreeze and resume to fire in the middle of the new drag.
            onDragBegan()
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
        onProgress?(min(1, abs(transform.offset) / Constant.dismissCommitDistance))
    }

    private func dragEnded(_ translation: CGFloat, _ velocity: CGFloat) {
        isDragActive = false
        guard !isFlyingAway else { return }

        let commits = abs(transform.offset) > Constant.dismissCommitDistance
            || abs(velocity) > Constant.dismissCommitVelocity

        guard commits else {
            // Unfreezes page transitions once the spring settles, and resumes the
            // story a few seconds later rather than the instant the finger lifts.
            settleDrag()
            return
        }

        // Adopt the current ON-SCREEN position before turning the rubber band off,
        // so switching to un-banded offsets is continuous rather than a step.
        let settled = transform.offset
        isFlyingAway = true
        var adopt = Transaction()
        adopt.disablesAnimations = true
        withTransaction(adopt) { dragOffset = settled }

        onDragCommitted()
        onProgress?(1)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        withAnimation(.spring(response: 0.15, dampingFraction: 0.85)) {
            dragOffset = settled < 0 ? -effectiveSize.height : effectiveSize.height
        }

        // `StoryView.body` is `if isPresented`, so the fly-away has to finish
        // before the flip - otherwise the story vanishes instead of leaving.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onDismiss()
        }
    }
}
