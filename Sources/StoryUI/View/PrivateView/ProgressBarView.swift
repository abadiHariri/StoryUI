//
//  ProgressView.swift
//  StoryUI (iOS)
//
//  Created by Tolga İskender on 29.04.2022.
//

import SwiftUI

struct ProgressBarView: View {
    var timerProgress: CGFloat
    var index: Int
    
    var body: some View {
        GeometryReader { proxy in
            
            let width = proxy.size.width
            let progress = timerProgress - CGFloat(index)
            let perfectProgress = min(max(progress, 0), 1)
            
            Capsule()
                .fill(.gray.opacity(0.5))
                .overlay (
                    Capsule()
                        .fill(.white)
                        .frame(width: width * perfectProgress)
                    
                    ,alignment: .leading
                )
                // The timer only ticks 10x a second, which reads as stepping.
                // Interpolating across each tick costs nothing and makes the bar
                // continuous; progress is linear in time, so linear is exact
                // rather than merely smooth.
                .animation(.linear(duration: Constant.timerTick), value: perfectProgress)
        }
        .frame(height: Constant.progressBarHeight)
    }
}
