//
//  StoryCloseButton.swift
//  StoryUI
//
//  Created by Abdulrahman Hariri on 21/11/2026.
//

import SwiftUI

/// The close button drawn when the host gives none: a plain white cross.
public struct StoryCloseButton: View {

    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button {
            action()
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
