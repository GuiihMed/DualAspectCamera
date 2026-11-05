import AVFoundation
import Photos
import SwiftUI
import UIKit

// MARK: - Full-Screen AVCaptureVideoPreviewLayer Wrapper

struct CameraPreviewView: UIViewRepresentable {
    let cameraManager: CameraManager

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.backgroundColor = .black
        view.previewLayer.session = cameraManager.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onOrientationChange = { [weak cameraManager] orientation in
            cameraManager?.updateInterfaceOrientation(orientation)
            if let connection = view.previewLayer.connection {
                cameraManager?.applyRotation(to: connection, interfaceOrientation: orientation)
            }
        }
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        if uiView.previewLayer.session !== cameraManager.session {
            uiView.previewLayer.session = cameraManager.session
        }
        uiView.enforceOrientation()
    }
}

final class PreviewContainerView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    var onOrientationChange: ((UIInterfaceOrientation) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        enforceOrientation()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        enforceOrientation()
    }

    func enforceOrientation() {
        guard let connection = previewLayer.connection else { return }

        let orientation = window?.windowScene?.interfaceOrientation ?? .portrait
        let angle: CGFloat
        switch orientation {
        case .portrait:
            angle = 90.0
        case .portraitUpsideDown:
            angle = 270.0
        case .landscapeLeft:
            angle = 180.0
        case .landscapeRight:
            angle = 0.0
        @unknown default:
            angle = 90.0
        }

        if #available(iOS 17.0, *) {
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else {
            if connection.isVideoOrientationSupported {
                switch orientation {
                case .portrait: connection.videoOrientation = .portrait
                case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
                case .landscapeLeft: connection.videoOrientation = .landscapeLeft
                case .landscapeRight: connection.videoOrientation = .landscapeRight
                default: connection.videoOrientation = .portrait
                }
            }
        }
        onOrientationChange?(orientation)
    }
}

// MARK: - Adaptive Crop Guides (Landscape 16:9 & Portrait 9:16)

struct AdaptiveCropGuides: View {
    let isLandscape: Bool
    let isRecording: Bool
    let isCinemaMode: Bool
    let showGrid: Bool

    var body: some View {
        GeometryReader { proxy in
            let screenSize = proxy.size

            if isLandscape {
                // LANDSCAPE: 16:9 full sensor feed with centered 9:16 vertical crop guide + lateral 30% dimming
                let verticalCropWidth = screenSize.height * (9.0 / 16.0)
                let verticalCropRect = CGRect(
                    x: (screenSize.width - verticalCropWidth) / 2.0,
                    y: 0,
                    width: verticalCropWidth,
                    height: screenSize.height
                )
                let lateralWidth = max(0, verticalCropRect.minX)

                ZStack {
                    // Lateral Dimming (30%)
                    if lateralWidth > 0 {
                        Rectangle()
                            .fill(Color.black.opacity(0.30))
                            .frame(width: lateralWidth, height: screenSize.height)
                            .position(x: lateralWidth / 2.0, y: screenSize.height / 2.0)

                        Rectangle()
                            .fill(Color.black.opacity(0.30))
                            .frame(width: lateralWidth, height: screenSize.height)
                            .position(x: verticalCropRect.maxX + (lateralWidth / 2.0), y: screenSize.height / 2.0)
                    }

                    // Centered 9:16 Frame
                    Rectangle()
                        .strokeBorder(
                            Color.white.opacity(isRecording ? 0.85 : 0.35),
                            style: StrokeStyle(lineWidth: 1.0, dash: [4, 4])
                        )
                        .frame(width: verticalCropRect.width, height: verticalCropRect.height)
                        .position(x: verticalCropRect.midX, y: verticalCropRect.midY)

                    // Corner Brackets
                    CornerTicksShape(tickLength: 18)
                        .stroke(
                            Color.white.opacity(isRecording ? 0.95 : 0.7),
                            style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                        )
                        .frame(width: verticalCropRect.width, height: verticalCropRect.height)
                        .position(x: verticalCropRect.midX, y: verticalCropRect.midY)

                    // Reticle
                    CenterReticleShape()
                        .stroke(Color.white.opacity(0.55), lineWidth: 1.0)
                        .frame(width: 20, height: 20)
                        .position(x: verticalCropRect.midX, y: verticalCropRect.midY)

                    // Rule of Thirds
                    if showGrid {
                        ThirdsGridShape()
                            .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
                            .frame(width: verticalCropRect.width, height: verticalCropRect.height)
                            .position(x: verticalCropRect.midX, y: verticalCropRect.midY)
                    }

                    // Top Safe Zone Tag
                    Text("9:16")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.10), in: Capsule())
                        .position(x: verticalCropRect.midX, y: verticalCropRect.minY + 24)
                }
            } else {
                // PORTRAIT: 9:16 vertical full height with centered 16:9 crop guide + top/bottom 30% dimming
                let horizontalCropHeight = screenSize.width * (9.0 / 16.0)
                let horizontalCropRect = CGRect(
                    x: 0,
                    y: (screenSize.height - horizontalCropHeight) / 2.0,
                    width: screenSize.width,
                    height: horizontalCropHeight
                )
                let verticalMargin = max(0, horizontalCropRect.minY)

                ZStack {
                    // Top & Bottom Dimming (30%)
                    if verticalMargin > 0 {
                        Rectangle()
                            .fill(Color.black.opacity(0.30))
                            .frame(width: screenSize.width, height: verticalMargin)
                            .position(x: screenSize.width / 2.0, y: verticalMargin / 2.0)

                        Rectangle()
                            .fill(Color.black.opacity(0.30))
                            .frame(width: screenSize.width, height: verticalMargin)
                            .position(x: screenSize.width / 2.0, y: horizontalCropRect.maxY + (verticalMargin / 2.0))
                    }

                    // Centered 16:9 Frame
                    Rectangle()
                        .strokeBorder(
                            Color.white.opacity(isRecording ? 0.85 : 0.35),
                            style: StrokeStyle(lineWidth: 1.0, dash: [4, 4])
                        )
                        .frame(width: horizontalCropRect.width, height: horizontalCropRect.height)
                        .position(x: horizontalCropRect.midX, y: horizontalCropRect.midY)

                    // Corner Brackets
                    CornerTicksShape(tickLength: 18)
                        .stroke(
                            Color.white.opacity(isRecording ? 0.95 : 0.7),
                            style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                        )
                        .frame(width: horizontalCropRect.width, height: horizontalCropRect.height)
                        .position(x: horizontalCropRect.midX, y: horizontalCropRect.midY)

                    // Reticle
                    CenterReticleShape()
                        .stroke(Color.white.opacity(0.55), lineWidth: 1.0)
                        .frame(width: 20, height: 20)
                        .position(x: horizontalCropRect.midX, y: horizontalCropRect.midY)

                    // Rule of Thirds
                    if showGrid {
                        ThirdsGridShape()
                            .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
                            .frame(width: horizontalCropRect.width, height: horizontalCropRect.height)
                            .position(x: horizontalCropRect.midX, y: horizontalCropRect.midY)
                    }

                    // 16:9 Tag
                    Text("16:9")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.10), in: Capsule())
                        .position(x: horizontalCropRect.midX, y: horizontalCropRect.minY + 20)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Shapes for Guides & Reticles

private struct ThirdsGridShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let oneThirdX = rect.minX + rect.width / 3.0
        let twoThirdX = rect.minX + (rect.width * 2.0 / 3.0)
        let oneThirdY = rect.minY + rect.height / 3.0
        let twoThirdY = rect.minY + (rect.height * 2.0 / 3.0)

        path.move(to: CGPoint(x: oneThirdX, y: rect.minY))
        path.addLine(to: CGPoint(x: oneThirdX, y: rect.maxY))
        path.move(to: CGPoint(x: twoThirdX, y: rect.minY))
        path.addLine(to: CGPoint(x: twoThirdX, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX, y: oneThirdY))
        path.addLine(to: CGPoint(x: rect.maxX, y: oneThirdY))
        path.move(to: CGPoint(x: rect.minX, y: twoThirdY))
        path.addLine(to: CGPoint(x: rect.maxX, y: twoThirdY))

        return path
    }
}

private struct CenterReticleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        let midY = rect.midY
        let arm: CGFloat = 8
        let gap: CGFloat = 3

        path.move(to: CGPoint(x: midX - arm, y: midY))
        path.addLine(to: CGPoint(x: midX - gap, y: midY))
        path.move(to: CGPoint(x: midX + gap, y: midY))
        path.addLine(to: CGPoint(x: midX + arm, y: midY))

        path.move(to: CGPoint(x: midX, y: midY - arm))
        path.addLine(to: CGPoint(x: midX, y: midY - gap))
        path.move(to: CGPoint(x: midX, y: midY + gap))
        path.addLine(to: CGPoint(x: midX, y: midY + arm))

        return path
    }
}

private struct CornerTicksShape: Shape {
    let tickLength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let t = min(tickLength, min(rect.width, rect.height) * 0.25)

        // Top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + t))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.minY))

        // Top-right
        path.move(to: CGPoint(x: rect.maxX - t, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + t))

        // Bottom-left
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - t))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY))

        // Bottom-right
        path.move(to: CGPoint(x: rect.maxX - t, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - t))

        return path
    }
}

// MARK: - Main Camera SwiftUI View

enum CameraCaptureMode: String, CaseIterable {
    case foto = "FOTO"
    case video = "VÍDEO"
    case cine = "CINE"
}

struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var pinchStartZoom: CGFloat?
    @State private var showGrid: Bool = true
    @State private var isZoomExpanded: Bool = false
    @State private var isPulseAnimating: Bool = false
    @State private var simulatedAudioLevel: CGFloat = 0.5
    @State private var exposureValue: CGFloat = 0.5
    @State private var isAdjustingExposure: Bool = false
    @State private var activeMode: CameraCaptureMode = .video
    @State private var isFlashing: Bool = false

    var body: some View {
        GeometryReader { proxy in
            let safeInsets = proxy.safeAreaInsets
            let isLandscape = proxy.size.width > proxy.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                // 1. Full-screen Camera Preview + Pinch-to-Zoom Gesture
                CameraPreviewView(cameraManager: cameraManager)
                    .ignoresSafeArea()
                    .gesture(pinchToZoomGesture)

                // 2. Adaptive Crop Guides (Landscape vs Portrait)
                AdaptiveCropGuides(
                    isLandscape: isLandscape,
                    isRecording: cameraManager.isRecording,
                    isCinemaMode: (activeMode == .cine),
                    showGrid: showGrid
                )
                .ignoresSafeArea()

                // 3. Shutter Flash Animation Effect
                if isFlashing {
                    Color.white.opacity(0.85)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                // 4. Ultra-Thin Lateral Exposure Slider
                lateralExposureSlider(screenHeight: proxy.size.height)
                    .position(
                        x: isLandscape ? proxy.size.width - max(28, safeInsets.trailing + 12) : proxy.size.width - 18,
                        y: proxy.size.height / 2.0
                    )

                // 5. Main Responsive UI Layout
                if isLandscape {
                    landscapeLayout(proxy: proxy, safeInsets: safeInsets)
                } else {
                    portraitLayout(proxy: proxy, safeInsets: safeInsets)
                }

                // 6. Status Banner Toast
                if let status = cameraManager.statusMessage {
                    VStack {
                        Spacer()
                        Text(status)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.black.opacity(0.75), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8))
                            .padding(.bottom, isLandscape ? 20 : max(100, safeInsets.bottom + 80))
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    .animation(.easeInOut(duration: 0.25), value: cameraManager.statusMessage)
                }
            }
        }
        .statusBarHidden(true)
        .onAppear {
            cameraManager.start()
            startAudioVUSimulation()
        }
        .onDisappear {
            cameraManager.stop()
        }
        .onChange(of: activeMode) { newMode in
            cameraManager.enableCinemaMode(newMode == .cine)
        }
    }

    // MARK: - Portrait Layout

    private func portraitLayout(proxy: GeometryProxy, safeInsets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            // Top Settings Bar
            topSettingsBar
                .padding(.top, max(12, safeInsets.top))
                .padding(.horizontal, 16)

            Spacer()

            // Floating Zoom Pill
            HStack {
                floatingZoomControl
                    .padding(.leading, max(16, safeInsets.leading))
                    .padding(.bottom, 12)
                Spacer()
            }

            // Bottom Control Dock
            bottomControlDock
                .padding(.bottom, max(14, safeInsets.bottom))
        }
    }

    // MARK: - Landscape Layout (Dock on Right side for thumb ergonomics)

    private func landscapeLayout(proxy: GeometryProxy, safeInsets: EdgeInsets) -> some View {
        HStack(spacing: 0) {
            // Left Zone: Zoom Control + Safe Margins
            VStack {
                Spacer()
                floatingZoomControl
                    .padding(.leading, max(20, safeInsets.leading))
                    .padding(.bottom, max(16, safeInsets.bottom))
            }

            Spacer()

            // Center: Top Settings Bar anchored at the physical top
            VStack {
                topSettingsBar
                    .padding(.top, max(10, safeInsets.top))
                Spacer()
            }

            Spacer()

            // Right Zone: Shutter, Carousel, Gallery Dock
            VStack(spacing: 16) {
                Spacer()
                landscapeControlDock
                    .padding(.trailing, max(20, safeInsets.trailing))
                Spacer()
            }
        }
    }

    // MARK: - Synchronized Pinch-to-Zoom Gesture

    private var pinchToZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let baseZoom = pinchStartZoom ?? cameraManager.zoomFactor
                if pinchStartZoom == nil {
                    pinchStartZoom = baseZoom
                }
                cameraManager.setZoomFactor(baseZoom * scale)
            }
            .onEnded { _ in
                pinchStartZoom = nil
            }
    }

    // MARK: - Top Settings Bar (Quality Dropdown, Mic VU, Toggles)

    private var qualityDropdownMenu: some View {
        Menu {
            Section("Resolução") {
                Button {
                    cameraManager.setResolutionPreset(.hd4K3840x2160)
                } label: {
                    Label("4K UHD (3840×2160)", systemImage: cameraManager.sessionPreset == .hd4K3840x2160 ? "checkmark" : "")
                }
                Button {
                    cameraManager.setResolutionPreset(.hd1920x1080)
                } label: {
                    Label("1080p FHD (1920×1080)", systemImage: cameraManager.sessionPreset == .hd1920x1080 ? "checkmark" : "")
                }
                Button {
                    cameraManager.setResolutionPreset(.hd1280x720)
                } label: {
                    Label("720p HD (1280×720)", systemImage: cameraManager.sessionPreset == .hd1280x720 ? "checkmark" : "")
                }
            }

            Section("Taxa de Quadros (FPS)") {
                Button {
                    cameraManager.setFrameRate(60)
                } label: {
                    Label("60 FPS (Ultra Fluido)", systemImage: cameraManager.activeFPS == 60 ? "checkmark" : "")
                }
                Button {
                    cameraManager.setFrameRate(30)
                } label: {
                    Label("30 FPS (Padrão)", systemImage: cameraManager.activeFPS == 30 ? "checkmark" : "")
                }
                Button {
                    cameraManager.setFrameRate(24)
                } label: {
                    Label("24 FPS (Cinema)", systemImage: cameraManager.activeFPS == 24 ? "checkmark" : "")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(cameraManager.activeResolutionLabel) · \(cameraManager.activeFPS)FPS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.10), in: Capsule())
        }
    }

    @ViewBuilder
    private var recordingStatusPill: some View {
        if cameraManager.isRecording {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .opacity(isPulseAnimating ? 0.3 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulseAnimating)
                    .onAppear { isPulseAnimating = true }
                    .onDisappear { isPulseAnimating = false }

                Text(formattedTimecode(cameraManager.recordingDuration))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.red.opacity(0.20), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.red.opacity(0.4), lineWidth: 0.8))
        }
    }

    private var audioVUMeterPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "mic.fill")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.8))

            HStack(spacing: 1.5) {
                ForEach(0..<3, id: \.self) { idx in
                    let threshold = CGFloat(Double(idx + 1) * 0.33)
                    let isActive = simulatedAudioLevel >= threshold
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(isActive ? 1.0 : 0.25))
                        .frame(width: 2, height: CGFloat(4.0 + Double(idx) * 2.5))
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var topTogglesGroup: some View {
        HStack(spacing: 8) {
            // Grid Toggle
            Button {
                hapticFeedback(.light)
                withAnimation(.easeInOut(duration: 0.15)) { showGrid.toggle() }
            } label: {
                Image(systemName: "grid")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .opacity(showGrid ? 1.0 : 0.4)
                    .frame(width: 24, height: 24)
            }

            // Torch Toggle
            if cameraManager.isTorchAvailable {
                Button {
                    hapticFeedback(.light)
                    cameraManager.toggleTorch()
                } label: {
                    Image(systemName: cameraManager.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(cameraManager.isTorchOn ? .yellow : .white)
                        .opacity(cameraManager.isTorchOn ? 1.0 : 0.4)
                        .frame(width: 24, height: 24)
                }
            }

            // Camera Switch (Front/Back)
            Button {
                hapticFeedback(.medium)
                cameraManager.switchCamera()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 24, height: 24)
            }
        }
    }

    private var topSettingsBar: some View {
        HStack(spacing: 8) {
            qualityDropdownMenu

            if cameraManager.isRecording {
                dividerLine
                recordingStatusPill
            }

            dividerLine
            audioVUMeterPill
            dividerLine
            topTogglesGroup
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Color.white.opacity(0.05)
                .background(.ultraThinMaterial)
        )
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
        .environment(\.colorScheme, .dark)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 12)
    }

    // MARK: - Ultra-Thin Lateral Exposure Slider (Controle de Luz)

    private func lateralExposureSlider(screenHeight: CGFloat) -> some View {
        HStack(spacing: 4) {
            // EV Readout while dragging
            if isAdjustingExposure {
                Text(String(format: "%+.1f EV", cameraManager.currentExposureBias))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.75), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.7))
                    .transition(.opacity)
            }

            ZStack(alignment: .top) {
                // Track: 2px thickness with 12% opacity at rest; 4px on touch
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(isAdjustingExposure ? 0.85 : 0.12))
                    .frame(width: isAdjustingExposure ? 4 : 2, height: 160)
                    .animation(.easeInOut(duration: 0.2), value: isAdjustingExposure)

                // Sun Indicator Thumb
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .offset(y: (1.0 - exposureValue) * 136)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isAdjustingExposure = true
                        let clamped = min(max(1.0 - (value.location.y / 160.0), 0.0), 1.0)
                        exposureValue = clamped
                        cameraManager.setExposureBias(normalized: clamped)
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.35)) {
                            isAdjustingExposure = false
                        }
                    }
            )
        }
        .frame(height: 180)
    }

    // MARK: - Floating Expanding Zoom Control (0.5x Ultra-Wide to 5x)

    private var floatingZoomControl: some View {
        HStack(spacing: 4) {
            Button {
                hapticFeedback(.light)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                    isZoomExpanded.toggle()
                }
            } label: {
                Text(String(format: "%.1f×", cameraManager.zoomFactor))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.12), in: Circle())
            }

            if isZoomExpanded {
                HStack(spacing: 3) {
                    let presets: [CGFloat] = cameraManager.isUltraWideAvailable ? [0.5, 1.0, 2.0, 3.0, 5.0] : [1.0, 2.0, 3.0, 5.0]
                    ForEach(presets, id: \.self) { preset in
                        let isSelected = abs(cameraManager.zoomFactor - preset) < 0.15
                        Button {
                            hapticFeedback(.light)
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                cameraManager.setZoomFactor(preset)
                                isZoomExpanded = false
                            }
                        } label: {
                            Text(preset == 0.5 ? ".5" : String(format: "%.0f", preset))
                                .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
                                .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.8))
                                .frame(width: 28, height: 28)
                                .background(isSelected ? Color.white : Color.clear, in: Circle())
                        }
                    }
                }
                .padding(.horizontal, 4)
                .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
            }
        }
        .padding(3)
        .background(
            Color.white.opacity(0.06)
                .background(.ultraThinMaterial)
        )
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Mode Carousel (FOTO | VÍDEO | CINE)

    private var modeCarousel: some View {
        HStack(spacing: 22) {
            ForEach(CameraCaptureMode.allCases, id: \.self) { mode in
                let isSelected = activeMode == mode
                Button {
                    hapticFeedback(.light)
                    withAnimation(.easeInOut(duration: 0.2)) { activeMode = mode }
                } label: {
                    VStack(spacing: 3) {
                        Text(mode.rawValue)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .monospaced))
                            .foregroundStyle(.white)
                            .opacity(isSelected ? 1.0 : 0.4)

                        Circle()
                            .fill(isSelected ? Color.white : Color.clear)
                            .frame(width: 3.5, height: 3.5)
                    }
                }
            }
        }
    }

    // MARK: - Bottom Control Dock (Portrait)

    private var bottomControlDock: some View {
        VStack(spacing: 14) {
            // Mode Carousel
            modeCarousel

            // Capture Triad: [Gallery] - [Shutter REC/Photo] - [Quick Photo / Flip]
            HStack {
                // 1. Gallery Thumbnail
                galleryButton

                Spacer()

                // 2. Main Shutter Button
                mainShutterButton

                Spacer()

                // 3. Quick Photo Button
                quickPhotoButton
            }
            .frame(maxWidth: 320)
        }
    }

    // MARK: - Landscape Control Dock (Right side)

    private var landscapeControlDock: some View {
        VStack(spacing: 16) {
            // Mode Carousel (compact vertical stack)
            VStack(spacing: 10) {
                ForEach(CameraCaptureMode.allCases, id: \.self) { mode in
                    let isSelected = activeMode == mode
                    Button {
                        hapticFeedback(.light)
                        withAnimation(.easeInOut(duration: 0.2)) { activeMode = mode }
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
                            .foregroundStyle(.white)
                            .opacity(isSelected ? 1.0 : 0.4)
                    }
                }
            }

            // Main Shutter
            mainShutterButton

            // Bottom row: Gallery & Quick Photo
            HStack(spacing: 14) {
                galleryButton
                quickPhotoButton
            }
        }
    }

    // MARK: - Gallery Button

    private var galleryButton: some View {
        Button {
            hapticFeedback(.light)
            cameraManager.openPhotosApp()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 44, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))

                if let thumbnail = cameraManager.latestThumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Main Shutter Button (Photo vs Video vs Cine)

    private var mainShutterButton: some View {
        Button {
            if activeMode == .foto {
                triggerPhotoCapture()
            } else {
                hapticFeedback(.medium)
                cameraManager.toggleRecording()
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 3)
                    .frame(width: 72, height: 72)

                if cameraManager.isSaving {
                    ProgressView().tint(.white)
                } else if activeMode == .foto {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 58, height: 58)
                } else {
                    RoundedRectangle(
                        cornerRadius: cameraManager.isRecording ? 6 : 28,
                        style: .continuous
                    )
                    .fill(cameraManager.isRecording ? Color.red : Color.white)
                    .frame(
                        width: cameraManager.isRecording ? 28 : 56,
                        height: cameraManager.isRecording ? 28 : 56
                    )
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: cameraManager.isRecording)

                    if cameraManager.isRecording {
                        Circle()
                            .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                            .frame(width: 78, height: 78)
                    }
                }
            }
        }
        .disabled(!cameraManager.isSessionRunning || cameraManager.isSaving)
    }

    // MARK: - Quick Photo Button

    private var quickPhotoButton: some View {
        Button {
            triggerPhotoCapture()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))

                Image(systemName: "camera.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
            }
        }
    }

    private func triggerPhotoCapture() {
        hapticFeedback(.heavy)
        withAnimation(.easeIn(duration: 0.08)) {
            isFlashing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeOut(duration: 0.2)) {
                isFlashing = false
            }
        }
        cameraManager.capturePhoto()
    }

    // MARK: - Helpers

    private func startAudioVUSimulation() {
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            let random = CGFloat.random(in: 0.25...0.85)
            withAnimation(.easeInOut(duration: 0.12)) {
                self.simulatedAudioLevel = random
            }
        }
    }

    private func formattedTimecode(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}
