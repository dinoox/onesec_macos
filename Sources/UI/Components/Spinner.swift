//
//  Spinner.swift
//  OnesecCore
//
//  Created by 王晓雨 on 2025/10/16.
//

import SwiftUI

struct Spinner: View {
    let color: Color
    let size: CGFloat
    
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}
