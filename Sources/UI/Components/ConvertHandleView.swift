import SwiftUI

private enum CardConstants {
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 10
    static let completedHeight: CGFloat = 44
    static let processingHeight: CGFloat = 78
}

private enum AnimationConstants {
    static let springResponse: CGFloat = 0.6
    static let springDamping: CGFloat = 0.825
    static let morphSpringResponse: CGFloat = 1.5

    static var defaultSpring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }

    static var morphSpring: Animation {
        .spring(response: morphSpringResponse, dampingFraction: springDamping)
    }
}

private enum ProgressConstants {
    static let progressIncrement: Double = 0.01
    static let timerInterval: TimeInterval = 0.01667
    static let pausedCurveY: CGFloat = 0.90
    static let normalCurveY: CGFloat = 0.75
    static let completedWaveAmplitude: CGFloat = 2
    static let normalLineWidth: CGFloat = 1.5
    static let morphedLineWidth: CGFloat = 2.5
}

private enum MorphConstants {
    static let checkTransitionPoint: Double = 0.65
    static let lengthShrinkFactor: Double = 0.85
    static let rightEndShrinkFactor: Double = 0.75
}

extension Animation {
    static var cardAnimation: Animation { AnimationConstants.defaultSpring }
    static var morphAnimation: Animation { AnimationConstants.morphSpring }
}

struct ConvertHandleView: View {
    let panelId: UUID
    let filePath: String?

    @State private var isUploadCompleted: Bool = false
    @State private var isProcessingCompleted: Bool = false
    @State private var isDownloadCompleted: Bool = false
    @State private var startTime: Date?
    @State private var totalDuration: TimeInterval = 0
    @State private var isCloseHovered = false
    @State private var isCollapseHovered = false
    @State private var isContentCollapsed = false

    var body: some View {
        VStack(spacing: 0) {
            headerView

            if !isContentCollapsed {
                cardDivider
                UploadCardView(isUploadCompleted: $isUploadCompleted, isProcessingCompleted: $isProcessingCompleted, startTime: $startTime, filePath: filePath)

                if isUploadCompleted {
                    cardDivider
                    ServerProcessingView(isProcessingCompleted: $isProcessingCompleted)
                        .transition(.opacity)
                }

                if isProcessingCompleted {
                    cardDivider
                    DownloadCardView(isDownloadCompleted: $isDownloadCompleted)
                        .transition(.opacity)
                }

                if isDownloadCompleted {
                    cardDivider
                    StatisticsView(totalDuration: totalDuration)
                        .transition(.opacity)
                }
            }
        }
        .background(Color.overlayBackground)
        .cornerRadius(20)
        .frame(width: 250)
        .shadow(color: .overlayBackground.opacity(0.3), radius: 6, x: 0, y: 0)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.overlayBorder, lineWidth: 1.2)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.cardAnimation, value: [isUploadCompleted, isProcessingCompleted, isDownloadCompleted, isContentCollapsed])
        .onChange(of: isDownloadCompleted) { newValue in
            if newValue, let start = startTime {
                totalDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            Text("文件转换")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.overlayText)
                .lineLimit(1)
                .drawingGroup()

            Spacer()

            Button(action: toggleContentCollapse) {
                Image.systemSymbol("chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isCollapseHovered ? .overlayText : .overlaySecondaryText)
                    .rotationEffect(.degrees(isContentCollapsed ? 180 : 0))
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isCollapseHovered)
            .animation(.cardAnimation, value: isContentCollapsed)
            .onHover { hovering in
                isCollapseHovered = hovering
            }

            Button(action: closeCard) {
                Image.systemSymbol("xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isCloseHovered ? .overlayText : .overlaySecondaryText)
                    .animation(.easeInOut(duration: 0.2), value: isCloseHovered)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isCloseHovered = hovering
            }
        }
        .padding(.horizontal, CardConstants.horizontalPadding)
        .padding(.vertical, 12)
    }

    private var cardDivider: some View {
        Divider().background(Color.overlayBorder.opacity(0.6))
    }

    private func toggleContentCollapse() {
        withAnimation(.cardAnimation) {
            isContentCollapsed.toggle()
        }
    }

    private func closeCard() {
        OverlayController.shared.hideOverlay(uuid: panelId)
    }
}

struct UploadCardView: View {
    @Binding var isUploadCompleted: Bool
    @Binding var isProcessingCompleted: Bool
    @Binding var startTime: Date?
    let filePath: String?

    var body: some View {
        ProgressCardView(
            isCompleted: $isUploadCompleted,
            titleProcessing: "Uploading 3 files",
            titleCompleted: "已上传完毕",
            showControls: true,
            autoStart: false,
            onStart: {
                isProcessingCompleted = false
                startTime = Date()
            },
            filePath: filePath
        )
    }
}

struct ProgressCardView: View {
    @Binding var isCompleted: Bool
    let titleProcessing: String
    let titleCompleted: String
    let showControls: Bool
    let autoStart: Bool
    let onStart: (() -> Void)?
    var filePath: String?

    @State private var progress: Double = 0.0
    @State private var isPaused: Bool = false
    @State private var vStackOffset: CGFloat = -10
    @State private var timer: Timer?
    @State private var isCompletedState: Bool = false
    @State private var morphProgress: Double = 0.0
    @State private var curveYPosition: CGFloat = ProgressConstants.normalCurveY
    @State private var lineColor: Color = .overlayPrimary
    @State private var isPauseHovered: Bool = false
    @State private var isCancelHovered: Bool = false
    @State private var fileIcon: NSImage?

    init(
        isCompleted: Binding<Bool>,
        titleProcessing: String,
        titleCompleted: String,
        showControls: Bool = false,
        autoStart: Bool = true,
        onStart: (() -> Void)? = nil,
        filePath: String? = nil
    ) {
        _isCompleted = isCompleted
        self.titleProcessing = titleProcessing
        self.titleCompleted = titleCompleted
        self.showControls = showControls
        self.autoStart = autoStart
        self.onStart = onStart
        self.filePath = filePath
    }

    private var waveAmplitude: CGFloat {
        progress >= 1.0 ? ProgressConstants.completedWaveAmplitude : 0
    }

    private var lineWidth: CGFloat {
        morphProgress > 0
            ? ProgressConstants.normalLineWidth * (1 - morphProgress) + ProgressConstants.morphedLineWidth * morphProgress
            : ProgressConstants.normalLineWidth
    }

    private var timeRemaining: Int {
        max(0, Int((1.0 - progress) / ProgressConstants.progressIncrement * ProgressConstants.timerInterval))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.overlayBackground

                Color.overlayText.opacity(0.05)
                    .frame(width: geo.size.width * progress)
                    .opacity(isCompletedState ? 0 : 1)
                    .animation(nil, value: isCompletedState)

                MorphingProgressLine(
                    progress: progress,
                    yPosition: curveYPosition,
                    waveAmplitude: waveAmplitude,
                    morphProgress: morphProgress
                )
                .stroke(lineColor, lineWidth: lineWidth)
                .frame(width: geo.size.width, height: geo.size.height)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        // if let icon = fileIcon {
                        //     Image(nsImage: icon)
                        //         .resizable()
                        //         .frame(width: 16, height: 16)
                        // }

                        Text(isCompletedState ? titleCompleted : titleProcessing)
                            .font(.system(size: isCompletedState ? 12 : 14, weight: .regular))
                            .foregroundColor(.overlayText)
                            .lineLimit(1)
                            .drawingGroup()

                        Spacer()

                        if showControls && !isCompletedState {
                            HStack(spacing: 8) {
                                Button(action: { isPaused.toggle() }) {
                                    Image(systemName: isPaused ? "play" : "pause")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(isPauseHovered ? .overlayText : .overlaySecondaryText)
                                        .frame(width: 15, height: 15)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isPauseHovered)
                                .onHover { hovering in
                                    isPauseHovered = hovering
                                }

                                Button(action: {}) {
                                    Image.systemSymbol("xmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(isCancelHovered ? .overlayText : .overlaySecondaryText)
                                }
                                .buttonStyle(.plain)
                                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isCancelHovered)
                                .onHover { hovering in
                                    isCancelHovered = hovering
                                }
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, CardConstants.horizontalPadding)
                    .padding(.top, isCompletedState ? CardConstants.verticalPadding : CardConstants.horizontalPadding)
                    .padding(.bottom, isCompletedState ? CardConstants.verticalPadding : (showControls ? 5 : 8))

                    if !isCompletedState {
                        HStack(spacing: showControls ? 2 : 6) {
                            Text("\(Int(progress * 100))%").font(.system(size: 12, design: .monospaced)).drawingGroup()
                            Text("·")
                                .opacity(0.6).drawingGroup()
                            Text("\(timeRemaining)")
                                .font(.system(size: showControls ? 12 : 14, design: .monospaced))
                                .foregroundColor(Color.overlaySecondaryText).drawingGroup()
                            Text("seconds left").drawingGroup()
                        }
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.overlaySecondaryText)
                        .padding(.horizontal, CardConstants.horizontalPadding)
                        .padding(.bottom, CardConstants.horizontalPadding)
                        .animation(.cardAnimation, value: isCompletedState)
                    }
                }
                .offset(y: vStackOffset)
            }
        }
        .frame(height: isCompletedState ? CardConstants.completedHeight : CardConstants.processingHeight)
        .onAppear {
            // if let path = filePath {
            //     fileIcon = NSWorkspace.shared.icon(forFile: path)
            // }
            if autoStart {
                startProgress()
            }
        }
        .onTapGesture {
            if !autoStart && (progress == 0.0 || progress >= 1.0) {
                startProgress()
            }
        }
        .onChange(of: progress) { newValue in
            if newValue >= 1.0 {
                withAnimation(.morphAnimation) {
                    vStackOffset = 0
                    morphProgress = 1.0
                    isCompletedState = true
                }
                isCompleted = true
            }
        }
        .onChange(of: isPaused) { newValue in
            withAnimation(.cardAnimation) {
                curveYPosition = newValue ? ProgressConstants.pausedCurveY : ProgressConstants.normalCurveY
                lineColor = newValue ? .overlayBorder : .overlayPrimary
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func startProgress() {
        progress = 0.0
        vStackOffset = -10
        isPaused = false
        isCompletedState = false
        isCompleted = false
        morphProgress = 0.0
        curveYPosition = ProgressConstants.normalCurveY
        lineColor = .overlayPrimary
        onStart?()
        timer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: ProgressConstants.timerInterval, repeats: true) { _ in
            if !isPaused, progress < 1.0 {
                progress += ProgressConstants.progressIncrement
                if progress >= 1.0 {
                    timer?.invalidate()
                }
            }
        }
    }
}

struct MorphingProgressLine: Shape {
    var progress: Double
    var yPosition: CGFloat
    var waveAmplitude: CGFloat
    var morphProgress: Double

    var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<Double, Double>, Double>, Double> {
        get {
            AnimatablePair(
                AnimatablePair(
                    AnimatablePair(progress, Double(yPosition)),
                    Double(waveAmplitude),
                ),
                morphProgress,
            )
        }
        set {
            progress = newValue.first.first.first
            yPosition = CGFloat(newValue.first.first.second)
            waveAmplitude = CGFloat(newValue.first.second)
            morphProgress = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        if morphProgress < 0.01 {
            drawProgressLine(in: rect, path: &path)
        } else {
            drawCheckmark(in: rect, path: &path)
        }

        return path
    }

    private func drawProgressLine(in rect: CGRect, path: inout Path) {
        let yPos = rect.height * yPosition
        let endX = rect.width * progress
        let wavelength: CGFloat = 120
        let step: CGFloat = 2

        path.move(to: CGPoint(x: 0, y: yPos))

        var x: CGFloat = 0
        while x < endX {
            let nextX = min(x + step, endX)
            let y = yPos + sin((x / wavelength) * .pi * 2) * waveAmplitude
            path.addLine(to: CGPoint(x: nextX, y: y))
            x = nextX
        }
    }

    private func drawCheckmark(in rect: CGRect, path: inout Path) {
        let checkmarkCenterX: CGFloat = rect.width - 22
        let checkmarkCenterY: CGFloat = rect.height / 2
        let lineStartY = rect.height * yPosition
        let lineEndX = rect.width * progress
        let lineStartX: CGFloat = 0
        let size: CGFloat = 12

        let point1 = CGPoint(x: checkmarkCenterX - size * 0.4, y: checkmarkCenterY)
        let point2 = CGPoint(x: checkmarkCenterX - size * 0.1, y: checkmarkCenterY + size * 0.4)
        let point3 = CGPoint(x: checkmarkCenterX + size * 0.5, y: checkmarkCenterY - size * 0.45)

        if morphProgress < 1.0 {
            let easeProgress = easeInOutCubic(morphProgress)
            let targetLength = size * 1.2
            let originalLength = lineEndX - lineStartX
            let currentLength = originalLength * (1 - easeProgress * MorphConstants.lengthShrinkFactor) + targetLength * (easeProgress * MorphConstants.lengthShrinkFactor)
            let currentEndX = lineEndX * (1 - easeProgress * MorphConstants.rightEndShrinkFactor) + checkmarkCenterX * (easeProgress * MorphConstants.rightEndShrinkFactor)
            let currentStartX = currentEndX - currentLength
            let currentY = lineStartY * (1 - easeProgress) + checkmarkCenterY * easeProgress

            if morphProgress < MorphConstants.checkTransitionPoint {
                path.move(to: CGPoint(x: currentStartX, y: currentY))
                path.addLine(to: CGPoint(x: currentEndX, y: currentY))
            } else {
                let checkProgress = (morphProgress - MorphConstants.checkTransitionPoint) / (1 - MorphConstants.checkTransitionPoint)
                let smoothCheckProgress = easeInOutCubic(checkProgress)
                let lineLeft = CGPoint(x: currentStartX, y: currentY)
                let lineRight = CGPoint(x: currentEndX, y: currentY)

                let p1 = interpolate(from: lineLeft, to: point1, progress: smoothCheckProgress)
                let p2 = interpolate(from: CGPoint(x: (lineLeft.x + lineRight.x) / 2, y: currentY), to: point2, progress: smoothCheckProgress)
                let p3 = interpolate(from: lineRight, to: point3, progress: smoothCheckProgress)

                path.move(to: p1)
                path.addLine(to: p2)
                path.addLine(to: p3)
            }
        } else {
            path.move(to: point1)
            path.addLine(to: point2)
            path.addLine(to: point3)
        }
    }

    private func interpolate(from start: CGPoint, to end: CGPoint, progress: Double) -> CGPoint {
        CGPoint(
            x: start.x * (1 - progress) + end.x * progress,
            y: start.y * (1 - progress) + end.y * progress
        )
    }

    private func easeInOutCubic(_ t: Double) -> Double {
        if t < 0.5 {
            return 4 * t * t * t
        } else {
            let f = (2 * t) - 2
            return 1 + (f * f * f) / 2
        }
    }
}

struct ServerProcessingView: View {
    @Binding var isProcessingCompleted: Bool
    @State private var isProcessing: Bool = true
    @State private var rotationAngle: Double = 0
    @State private var morphProgress: Double = 0.0
    @State private var lineColor: Color = .overlayPrimary
    @State private var timer: Timer?

    private var lineWidth: CGFloat {
        morphProgress > 0
            ? ProgressConstants.normalLineWidth * (1 - morphProgress) + ProgressConstants.morphedLineWidth * morphProgress
            : ProgressConstants.normalLineWidth
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.overlayBackground

                if !isProcessing {
                    MorphingProgressLine(
                        progress: 1.0,
                        yPosition: 0.5,
                        waveAmplitude: 0,
                        morphProgress: morphProgress
                    )
                    .stroke(lineColor, lineWidth: lineWidth)
                    .frame(width: geo.size.width, height: geo.size.height)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(isProcessing ? "等待服务器处理" : "已处理完毕")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.overlayText)
                            .drawingGroup()

                        Spacer()

                        if isProcessing {
                            Circle()
                                .trim(from: 0, to: 0.7)
                                .stroke(Color.overlayPrimary, lineWidth: 2.4)
                                .frame(width: 12, height: 12)
                                .rotationEffect(.degrees(rotationAngle))
                                .onAppear {
                                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                        rotationAngle = 360
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, CardConstants.horizontalPadding)
                    .padding(.top, isProcessing ? 0 : CardConstants.verticalPadding)
                    .padding(.bottom, isProcessing ? 0 : CardConstants.verticalPadding)

                    if isProcessing {
                        Text("服务器正在处理您的文件...")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.overlaySecondaryText)
                            .padding(.horizontal, CardConstants.horizontalPadding)
                            .drawingGroup()
                    }
                }
            }
        }
        .frame(height: isProcessing ? CardConstants.processingHeight - 10 : CardConstants.completedHeight)
        .onAppear {
            isProcessing = true
            isProcessingCompleted = false
            morphProgress = 0.0
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                withAnimation(.cardAnimation) {
                    isProcessing = false
                }
                withAnimation(.morphAnimation) {
                    morphProgress = 1.0
                }
                isProcessingCompleted = true
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
}

struct DownloadCardView: View {
    @Binding var isDownloadCompleted: Bool

    var body: some View {
        ProgressCardView(
            isCompleted: $isDownloadCompleted,
            titleProcessing: "获取文件中",
            titleCompleted: "已下载完毕",
            showControls: false,
            autoStart: true
        )
    }
}

struct StatisticsView: View {
    let totalDuration: TimeInterval

    private var formattedDuration: String {
        let minutes = Int(totalDuration) / 60
        let seconds = Int(totalDuration) % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("总耗时")
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(Color.overlaySecondaryText)
                .drawingGroup()

            Spacer()

            Text(formattedDuration)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(Color.overlaySecondaryText).drawingGroup()
        }
        .padding(.horizontal, CardConstants.horizontalPadding)
        .padding(.vertical, CardConstants.verticalPadding)
        .frame(height: CardConstants.completedHeight - 15)
        .background(Color.overlayBackground)
    }
}
