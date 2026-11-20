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
/// draws over the safe area itself, so the pager must not adjust for it. Placed
/// inside a page; it does nothing when no paging scroll view encloses it.
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
        // The page is attached to the pager on the next turn, not yet here.
        DispatchQueue.main.async { [weak self] in
            self?.stopPagerInsetAdjustment()
        }
    }

    private func stopPagerInsetAdjustment() {
        var view = superview
        while let current = view {
            if let scrollView = current as? UIScrollView, scrollView.isPagingEnabled {
                if scrollView.contentInsetAdjustmentBehavior != .never {
                    scrollView.contentInsetAdjustmentBehavior = .never
                }
                return
            }
            view = current.superview
        }
    }
}
