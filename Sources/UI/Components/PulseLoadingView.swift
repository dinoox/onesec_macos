import SwiftUI

struct PulseLoadingView: View {
    @State var scale: [CGFloat] = Array(repeating: 1.0, count: 4)

    var body: some View {
        if #available(macOS 12.0, *) {
            ZStack {
                ForEach(0 ..< 4) { item in
                    Circle()
                        .foregroundStyle(starlightYellow)
                        .frame(width: 6 * CGFloat(item + 1), height: 6 * CGFloat(item + 1))
                        .opacity(1 - (0.25 * CGFloat(item)))
                        .shadow(color: .black, radius: 10, x: 0, y: 5)
                        .scaleEffect(scale[item])
                        .animation(
                            .easeInOut(duration: 1)
                                .repeatForever(autoreverses: true)
                                .delay(0.1 * Double(item)),
                            value: scale[item],
                        )
                }
            }
            .onAppear {
                for i in 0 ..< scale.count {
                    DispatchQueue.main.asyncAfter(deadline: .now() + (0.1 * Double(i))) {
                        scale[i] = 1.2
                    }
                }
            }
        } else {}
    }
}

#Preview {
    PulseLoadingView()
}
