import AVFoundation
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
                cameraManager?.applyLandscapeRotation(to: connection, interfaceOrientation: orientation)
            }
        }
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        if uiView.previewLayer.session !== cameraManager.session {
            uiView.previewLayer.session = cameraManager.session
        }
        uiView.enforceHorizontalOrientation()
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
        enforceHorizontalOrientation()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        enforceHorizontalOrientation()
    }

    func enforceHorizontalOrientation() {
        guard let connection = previewLayer.connection else { return }

        // Default strictly to Landscape (Horizontal 16:9 feed)
        let orientation = window?.windowScene?.interfaceOrientation ?? .landscapeRight
        let effectiveOrientation: UIInterfaceOrientation = (orientation == .landscapeLeft) ? .landscapeLeft : .landscapeRight
        let angle: CGFloat = (effectiveOrientation == .landscapeLeft) ? 180.0 : 0.0

        if #available(iOS 17.0, *) {
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = (effectiveOrientation == .landscapeLeft) ? .landscapeLeft : .landscapeRight
            }
        }
        onOrientationChange?(effectiveOrientation)
    }
}

// MARK: - 9:16 Safe-Area Visual Framing Guide Overlay

/// Draws the full-screen camera preview with the exact centered 9:16 vertical crop guide,
/// subtle non-obstructive lateral dimming, delicate dashed boundaries, corner brackets,
/// and center optical reticle.
struct FramingGuideOverlay: View {
    let isRecording: Bool
    let showGrid: Bool

    var body: some View {
        GeometryReader { proxy in
            let screenSize = proxy.size
            let containerRect = CGRect(origin: .zero, size: screenSize)

            // Compute exact 16:9 feed layout with .resizeAspectFill (full screen edge-to-edge)
            let videoRect = aspectFillRect(
                aspectRatio: CGSize(width: 16, height: 9),
                insideRect: containerRect
            )

            // Exact 9:16 vertical crop rectangle centered in the middle of the 16:9 feed
            let verticalCropWidth = videoRect.height * (9.0 / 16.0)
            let verticalCropRect = CGRect(
                x: videoRect.midX - (verticalCropWidth / 2.0),
                y: max(0, videoRect.minY),
                width: verticalCropWidth,
                height: min(screenSize.height, videoRect.height)
            )

            let leftMaskWidth = max(0, verticalCropRect.minX)
            let rightMaskWidth = max(0, screenSize.width - verticalCropRect.maxX)

            ZStack {
                // 1. Soft Lateral Dimming (Exterior 16:9 margins kept fully readable with subtle contrast)
                if leftMaskWidth > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.20))
                        .frame(width: leftMaskWidth, height: screenSize.height)
                        .position(x: leftMaskWidth / 2.0, y: screenSize.height / 2.0)
                }

                if rightMaskWidth > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.20))
                        .frame(width: rightMaskWidth, height: screenSize.height)
                        .position(x: verticalCropRect.maxX + (rightMaskWidth / 2.0), y: screenSize.height / 2.0)
                }

                // 2. Rule of Thirds Grid inside 9:16 vertical frame (when enabled)
                if showGrid {
                    ThirdsGridShape()
                        .stroke(
                            Color.white.opacity(0.18),
                            style: StrokeStyle(lineWidth: 0.8, dash: [3, 4])
                        )
                        .frame(width: verticalCropRect.width, height: verticalCropRect.height)
                        .position(x: verticalCropRect.midX, y: verticalCropRect.midY)
                }

                // 3. Precision Optical Reticle (Crosshair)
                CenterReticleShape()
                    .stroke(
                        Color.white.opacity(0.55),
                        lineWidth: 1.0
                    )
                    .frame(width: 20, height: 20)
                    .position(x: verticalCropRect.midX, y: verticalCropRect.midY)

                // 4. Centered 9:16 Safe-Area Dashed Framing Lines
                Rectangle()
                    .strokeBorder(
                        Color.white.opacity(isRecording ? 0.7 : 0.35),
                        style: StrokeStyle(lineWidth: 1.0, dash: [4, 4])
                    )
                    .frame(width: verticalCropRect.width, height: verticalCropRect.height)
                    .position(x: verticalCropRect.midX, y: verticalCropRect.midY)

                // Corner ticks on the 9:16 frame for fast framing alignment
                CornerTicksShape(tickLength: 18)
                    .stroke(
                        Color.white.opacity(isRecording ? 0.9 : 0.65),
                        style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
                    )
                    .frame(width: verticalCropRect.width, height: verticalCropRect.height)
                    .position(x: verticalCropRect.midX, y: verticalCropRect.midY)

                // 5. Minimalist Micro-Badges
                // 9:16 Vertical Tag
                Text("9:16 VERTICAL")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.7))
                    .position(
                        x: verticalCropRect.midX,
                        y: verticalCropRect.minY + 22
                    )

                // 16:9 Full Sensor Tag
                Text("16:9 FULL SENSOR")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .position(
                        x: verticalCropRect.midX,
                        y: verticalCropRect.maxY - 18
                    )
            }
        }
        .allowsHitTesting(false)
    }

    private func aspectFillRect(aspectRatio: CGSize, insideRect containerRect: CGRect) -> CGRect {
        let containerAspect = containerRect.width / containerRect.height
        let videoAspect = aspectRatio.width / aspectRatio.height
        let scale: CGFloat

        if containerAspect > videoAspect {
            scale = containerRect.width / aspectRatio.width
        } else {
            scale = containerRect.height / aspectRatio.height
        }

        let scaledWidth = aspectRatio.width * scale
        let scaledHeight = aspectRatio.height * scale
        let originX = containerRect.midX - (scaledWidth / 2.0)
        let originY = containerRect.midY - (scaledHeight / 2.0)

        return CGRect(x: originX, y: originY, width: scaledWidth, height: scaledHeight)
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

struct CameraView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var pinchStartZoom: CGFloat?
    @State private var showGrid: Bool = true
    @State private var isZoomExpanded: Bool = false
    @State private var isPulseAnimating: Bool = false
    @State private var simulatedAudioLevel: CGFloat = 0.5

    var body: some View {
        GeometryReader { proxy in
            let safeInsets = proxy.safeAreaInsets
            let horizontalMargin = max(20, max(safeInsets.leading, safeInsets.trailing))

            ZStack {
                Color.black.ignoresSafeArea()

                // 1. Full-screen Camera Preview + Pinch-to-Zoom Gesture
                CameraPreviewView(cameraManager: cameraManager)
                    .ignoresSafeArea()
                    .gesture(pinchToZoomGesture)

                // 2. Centered 9:16 Safe-Area Framing Guide over 16:9 feed
                FramingGuideOverlay(
                    isRecording: cameraManager.isRecording,
                    showGrid: showGrid
                )
                .ignoresSafeArea()

                // 3. Ergonomic, Ultra-Minimalist Monochromatic UI Controls
                VStack(spacing: 0) {
                    // Top Bar: Unified Consolidated Pro HUD
                    topUnifiedHUD
                        .padding(.top, max(10, safeInsets.top))
                        .padding(.horizontal, horizontalMargin)

                    Spacer()

                    // Bottom Row: Expanding Zoom Dial (Left) & Cinema Shutter (Right)
                    HStack(alignment: .bottom) {
                        // Left Thumb Zone: Contextual Expanding Zoom Control
                        expandingZoomControl
                            .padding(.leading, horizontalMargin)
                            .padding(.bottom, max(16, safeInsets.bottom))

                        Spacer()

                        // Toast Notification Banner (Centered)
                        if let banner = cameraManager.statusMessage {
                            statusToastView(banner)
                                .padding(.bottom, max(20, safeInsets.bottom))
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        Spacer()

                        // Right Thumb Zone: Monochromatic Cinema Shutter
                        cinemaShutterButton
                            .padding(.trailing, horizontalMargin)
                            .padding(.bottom, max(16, safeInsets.bottom))
                    }
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

    // MARK: - Top Unified Consolidated Pro HUD (Ultra-Minimalist Monochromatic)

    private var topUnifiedHUD: some View {
        HStack(spacing: 8) {
            // Format & Codec Info
            HStack(spacing: 4) {
                Text(cameraManager.activeResolutionLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("•")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.35))
                Text("30FPS")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                Text("•")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.35))
                Text("HEVC")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
            }
            .fixedSize()

            dividerLine

            // Central State: Recording Timecode or Dual Stream Badge
            if cameraManager.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .opacity(isPulseAnimating ? 0.3 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulseAnimating)
                        .onAppear { isPulseAnimating = true }
                        .onDisappear { isPulseAnimating = false }

                    Text(formattedTimecode(cameraManager.recordingDuration))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .fixedSize()
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("DUAL 16:9 + 9:16")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .fixedSize()
            }

            dividerLine

            // Pro Audio: Microphone + Dynamic VU Meter
            HStack(spacing: 4) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))

                // Micro VU Meter: 4 dynamic vertical bars
                HStack(spacing: 1.5) {
                    ForEach(0..<4, id: \.self) { index in
                        let threshold = CGFloat(index + 1) * 0.25
                        let isActive = simulatedAudioLevel >= threshold
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(isActive ? 0.95 : 0.25))
                            .frame(width: 2, height: CGFloat(4 + index * 2))
                    }
                }
                .frame(height: 10)
            }
            .fixedSize()

            dividerLine

            // Storage / Estimated Remaining Time
            HStack(spacing: 3) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                Text("1h 42m")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .fixedSize()

            dividerLine

            // Toggles: Grid & Torch (Strictly Monochromatic via Opacity)
            HStack(spacing: 6) {
                // Grid Toggle
                Button {
                    hapticFeedback(.light)
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showGrid.toggle()
                    }
                } label: {
                    Image(systemName: "grid")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .opacity(showGrid ? 1.0 : 0.4)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(showGrid ? 0.12 : 0.0), in: Circle())
                }

                // Torch Toggle
                if cameraManager.isTorchAvailable {
                    Button {
                        hapticFeedback(.light)
                        cameraManager.toggleTorch()
                    } label: {
                        Image(systemName: cameraManager.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .opacity(cameraManager.isTorchOn ? 1.0 : 0.4)
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(cameraManager.isTorchOn ? 0.12 : 0.0), in: Circle())
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Color.white.opacity(0.04)
                .background(.ultraThinMaterial)
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
        .environment(\.colorScheme, .dark)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1, height: 12)
    }

    // MARK: - Contextual Expanding Zoom Control (Lower-Left Thumb Zone)

    private var expandingZoomControl: some View {
        HStack(spacing: 4) {
            // Resting Pill Button (Current Zoom Factor)
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
                    .background(Color.white.opacity(0.10), in: Circle())
            }

            // Expanded Preset Dial (Springs open horizontally on tap)
            if isZoomExpanded {
                HStack(spacing: 4) {
                    ForEach(zoomPresets, id: \.self) { preset in
                        let isSelected = abs(cameraManager.zoomFactor - preset) < 0.12
                        Button {
                            hapticFeedback(.light)
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                cameraManager.setZoomFactor(preset)
                            }
                        } label: {
                            Text(presetLabel(for: preset))
                                .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
                                .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.65))
                                .frame(width: 28, height: 28)
                                .background(
                                    isSelected ? Color.white : Color.clear,
                                    in: Circle()
                                )
                        }
                    }
                }
                .padding(.horizontal, 4)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8, anchor: .leading).combined(with: .opacity),
                    removal: .scale(scale: 0.8, anchor: .leading).combined(with: .opacity)
                ))
            }
        }
        .padding(3)
        .background(
            Color.white.opacity(0.05)
                .background(.ultraThinMaterial)
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 3)
        .environment(\.colorScheme, .dark)
    }

    private var zoomPresets: [CGFloat] {
        var list: [CGFloat] = []
        if cameraManager.minZoomFactor < 0.9 {
            list.append(0.5)
        }
        list.append(contentsOf: [1.0, 2.0, 3.0, 5.0])
        return list.filter { $0 >= cameraManager.minZoomFactor && $0 <= cameraManager.maxZoomFactor }
    }

    private func presetLabel(for preset: CGFloat) -> String {
        if preset == 0.5 { return ".5" }
        return String(format: "%.0f", preset)
    }

    // MARK: - Monochromatic Cinema Shutter (Lower-Right Thumb Zone)

    private var cinemaShutterButton: some View {
        VStack(spacing: 6) {
            Button {
                hapticFeedback(.medium)
                cameraManager.toggleRecording()
            } label: {
                ZStack {
                    // Outer Fine Ring
                    Circle()
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 2.5)
                        .frame(width: 70, height: 70)

                    if cameraManager.isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        // Inner Pure White Disc (Morphs smoothly into rounded square on record)
                        RoundedRectangle(
                            cornerRadius: cameraManager.isRecording ? 5 : 27,
                            style: .continuous
                        )
                        .fill(Color.white)
                        .frame(
                            width: cameraManager.isRecording ? 26 : 54,
                            height: cameraManager.isRecording ? 26 : 54
                        )
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: cameraManager.isRecording)

                        // Subtle animated outer ping ring when recording
                        if cameraManager.isRecording {
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                                .frame(width: 76, height: 76)
                        }
                    }
                }
            }
            .disabled(!cameraManager.isSessionRunning || cameraManager.isSaving)
            .accessibilityLabel(cameraManager.isRecording ? "Stop Recording" : "Start Recording")

            // Minimalist Action Label
            Text(cameraManager.isSaving ? "SAVING" : (cameraManager.isRecording ? "STOP" : "REC"))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    // MARK: - Helpers & Animations

    private func startAudioVUSimulation() {
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            let random = CGFloat.random(in: 0.25...0.85)
            withAnimation(.easeInOut(duration: 0.12)) {
                self.simulatedAudioLevel = random
            }
        }
    }

    private func statusToastView(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)

            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.85), in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
        )
    }

    private func formattedTimecode(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    private func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}
