//
//  PagerInsetAdjustment.swift
//  StoryUI
//
//  Created by Abdulrahman Hariri on 21/11/2026.
//

import SwiftUI
import UIKit

/// SwiftUI's page `TabView` pages with a collection view that adjusts its content
/// inset for the safe area on its scrolling axis. Across a side inset (the foldable
/// iPhone's status column) that centred every page in the safe part, so each page
/// sat shifted by half the inset with the next one showing at the edge. The story
/// draws over the safe area itself, so the pager must not adjust for it. Without the
/// adjustment the pager keeps its page through a rotation, a fold or a window resize
/// on its own. Placed inside a page; it does nothing when no paging scroll view
/// encloses it.
struct PagerInsetAdjustment: UIViewRepresentable {

    func makeUIView(context: Context) -> PagerInsetAdjustmentView {
        PagerInsetAdjustmentView()
    }

    func updateUIView(_ uiView: PagerInsetAdjustmentView, context: Context) {}
}

final class PagerInsetAdjustmentView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        // Before the pager settles its first page when the page is already inside it,
        // else on the next turn.
        if !stopPagerInsetAdjustment() {
            DispatchQueue.main.async { [weak self] in
                self?.stopPagerInsetAdjustment()
            }
        }
    }

    @discardableResult
    private func stopPagerInsetAdjustment() -> Bool {
        var view = superview
        while let current = view {
            if let scrollView = current as? UIScrollView, scrollView.isPagingEnabled {
                guard scrollView.contentInsetAdjustmentBehavior != .never else { return true }
                scrollView.contentInsetAdjustmentBehavior = .never
                // A page settled with the inset sits half of it off: back on a whole page.
                let width = scrollView.bounds.width
                if width > 0, !scrollView.isDragging, !scrollView.isDecelerating {
                    let page = (scrollView.contentOffset.x / width).rounded()
                    scrollView.setContentOffset(CGPoint(x: page * width, y: scrollView.contentOffset.y), animated: false)
                }
                return true
            }
            view = current.superview
        }
        return false
    }
}
