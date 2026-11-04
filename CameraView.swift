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
/// with ZERO black obscuring masks (100% clear camera feed), crisp vertical framing lines,
/// optional rule-of-thirds grid, and center optical reticle.
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

            ZStack {
                // 1. Rule of Thirds Grid inside the 9:16 vertical frame (when toggled ON)
                if showGrid {
                    ThirdsGridShape()
                        .stroke(
                            isRecording ? Color.yellow.opacity(0.4) : Color.white.opacity(0.3),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                        .frame(width: verticalCropRect.width, height: verticalCropRect.height)
                        .position(x: verticalCropRect.midX, y: verticalCropRect.midY)
                }

                // 2. Precision Center Optical Reticle (Crosshair)
                CenterReticleShape()
                    .stroke(
                        isRecording ? Color.yellow.opacity(0.85) : Color.white.opacity(0.7),
                        lineWidth: 1.2
                    )
                    .frame(width: 22, height: 22)
                    .position(x: verticalCropRect.midX, y: verticalCropRect.midY)

                // 3. Centered 9:16 Vertical Safe-Area Box (Crisp framing lines)
                Rectangle()
                    .strokeBorder(
                        isRecording ? Color.yellow.opacity(0.85) : Color.white.opacity(0.65),
                        lineWidth: 1.2
                    )
                    .frame(width: verticalCropRect.width, height: verticalCropRect.height)
                    .position(x: verticalCropRect.midX, y: verticalCropRect.midY)

                // Prominent Left Vertical Guide Line
                Path { path in
                    path.move(to: CGPoint(x: verticalCropRect.minX, y: verticalCropRect.minY))
                    path.addLine(to: CGPoint(x: verticalCropRect.minX, y: verticalCropRect.maxY))
                }
                .stroke(isRecording ? Color.yellow : Color.white, lineWidth: 2)

                // Prominent Right Vertical Guide Line
                Path { path in
                    path.move(to: CGPoint(x: verticalCropRect.maxX, y: verticalCropRect.minY))
                    path.addLine(to: CGPoint(x: verticalCropRect.maxX, y: verticalCropRect.maxY))
                }
                .stroke(isRecording ? Color.yellow : Color.white, lineWidth: 2)

                // Corner ticks on the 9:16 frame for fast framing alignment
                CornerTicksShape(tickLength: 22)
                    .stroke(
                        isRecording ? Color.yellow : Color.white,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: verticalCropRect.width, height: verticalCropRect.height)
                    .position(x: verticalCropRect.midX, y: verticalCropRect.midY)

                // 4. Badges indicating the dual capture regions
                // 9:16 Vertical Tag (Top center of vertical box)
                HStack(spacing: 5) {
                    Image(systemName: "iphone")
                        .font(.system(size: 9, weight: .bold))
                    Text("9:16 VERTICAL")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(isRecording ? Color.yellow : Color.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(Color.black.opacity(0.65), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isRecording ? Color.yellow.opacity(0.6) : Color.white.opacity(0.3), lineWidth: 0.8)
                )
                .position(
                    x: verticalCropRect.midX,
                    y: verticalCropRect.minY + 24
                )

                // 16:9 Full Sensor Tag (Bottom of preview)
                HStack(spacing: 4) {
                    Image(systemName: "tv")
                        .font(.system(size: 9, weight: .medium))
                    Text("16:9 4K FULL FRAME")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Color.white.opacity(0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.55), in: Capsule())
                .position(
                    x: verticalCropRect.midX,
                    y: verticalCropRect.maxY - 20
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

        // Vertical lines
        path.move(to: CGPoint(x: oneThirdX, y: rect.minY))
        path.addLine(to: CGPoint(x: oneThirdX, y: rect.maxY))
        path.move(to: CGPoint(x: twoThirdX, y: rect.minY))
        path.addLine(to: CGPoint(x: twoThirdX, y: rect.maxY))

        // Horizontal lines
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

        // Horizontal arms
        path.move(to: CGPoint(x: midX - arm, y: midY))
        path.addLine(to: CGPoint(x: midX - gap, y: midY))
        path.move(to: CGPoint(x: midX + gap, y: midY))
        path.addLine(to: CGPoint(x: midX + arm, y: midY))

        // Vertical arms
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
    @State private var isPulseAnimating: Bool = false

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

                // 2. Centered 9:16 Safe-Area Framing Guide over full 16:9 feed (Zero black masks)
                FramingGuideOverlay(
                    isRecording: cameraManager.isRecording,
                    showGrid: showGrid
                )
                .ignoresSafeArea()

                // 3. Ergonomic, Responsive UI Controls
                VStack(spacing: 0) {
                    // Top Bar: Centered Pro HUD
                    topProHUD
                        .padding(.top, max(10, safeInsets.top))
                        .padding(.horizontal, horizontalMargin)

                    Spacer()

                    // Middle / Bottom Controls (Left Zoom Dock & Right Shutter Dock)
                    HStack(alignment: .bottom) {
                        // Left Thumb Zone: Compact Lens / Zoom Dock
                        leftZoomDock
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

                        // Right Thumb Zone: Cinema Shutter & Recording Controls
                        rightShutterDock
                            .padding(.trailing, horizontalMargin)
                            .padding(.bottom, max(16, safeInsets.bottom))
                    }
                }
            }
        }
        .statusBarHidden(true)
        .onAppear {
            cameraManager.start()
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

    // MARK: - Top Pro Cinema HUD (Compact & Collision-Free)

    private var topProHUD: some View {
        HStack(spacing: 10) {
            // Left Tag: Resolution & Codec Info
            HStack(spacing: 5) {
                Text(cameraManager.activeResolutionLabel)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                Text("30FPS")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
                Text("HEVC")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.yellow, in: RoundedRectangle(cornerRadius: 3))
            }
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))

            Spacer()

            // Center: Recording Indicator or Dual Stream Badge
            if cameraManager.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .opacity(isPulseAnimating ? 0.3 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulseAnimating)
                        .onAppear { isPulseAnimating = true }
                        .onDisappear { isPulseAnimating = false }

                    Text("REC")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.red)

                    Text(formattedTimecode(cameraManager.recordingDuration))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.75), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.red.opacity(0.6), lineWidth: 1))
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.yellow)
                    Text("DUAL REC: 16:9 + 9:16")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
            }

            Spacer()

            // Right Group: Audio, Torch, Grid
            HStack(spacing: 6) {
                // Mic Tag
                HStack(spacing: 3) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green)
                    Text("MIC")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())

                // Torch Toggle
                if cameraManager.isTorchAvailable {
                    Button {
                        hapticFeedback(.light)
                        cameraManager.toggleTorch()
                    } label: {
                        Image(systemName: cameraManager.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(cameraManager.isTorchOn ? Color.yellow : Color.white.opacity(0.75))
                            .frame(width: 28, height: 28)
                            .background(cameraManager.isTorchOn ? Color.yellow.opacity(0.25) : Color.white.opacity(0.1), in: Circle())
                    }
                }

                // Grid Toggle
                Button {
                    hapticFeedback(.light)
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showGrid.toggle()
                    }
                } label: {
                    Image(systemName: "grid")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(showGrid ? Color.yellow : Color.white.opacity(0.75))
                        .frame(width: 28, height: 28)
                        .background(showGrid ? Color.yellow.opacity(0.25) : Color.white.opacity(0.1), in: Circle())
                }

                // Thermal Warning
                if cameraManager.thermalState == .serious || cameraManager.thermalState == .critical {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text("24FPS")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                    .fixedSize()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2), in: Capsule())
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Left Thumb Zone: Compact Zoom Dock (Anchored Bottom-Left)

    private var leftZoomDock: some View {
        VStack(spacing: 6) {
            // Active Zoom Factor Readout
            Text(String(format: "%.1fx", cameraManager.zoomFactor))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.yellow)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.7), in: Capsule())

            // Quick Lens Preset Buttons
            VStack(spacing: 5) {
                ForEach(zoomPresets, id: \.self) { preset in
                    let isSelected = abs(cameraManager.zoomFactor - preset) < 0.12
                    Button {
                        hapticFeedback(.light)
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                            cameraManager.setZoomFactor(preset)
                        }
                    } label: {
                        Text(presetLabel(for: preset))
                            .font(.system(size: 11, weight: isSelected ? .heavy : .semibold, design: .monospaced))
                            .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.9))
                            .frame(width: 32, height: 32)
                            .background(
                                isSelected ? Color.yellow : Color.white.opacity(0.15),
                                in: Circle()
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
        )
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

    // MARK: - Right Thumb Zone: Cinema Shutter & Recording Dock

    private var rightShutterDock: some View {
        VStack(spacing: 8) {
            // Cinema Shutter Button
            Button {
                hapticFeedback(.medium)
                cameraManager.toggleRecording()
            } label: {
                ZStack {
                    // Outer Ring with shadow
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 4)
                        .frame(width: 72, height: 72)
                        .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 2)

                    if cameraManager.isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        // Inner Record Shutter Disc / Rounded Stop Square
                        RoundedRectangle(
                            cornerRadius: cameraManager.isRecording ? 7 : 28,
                            style: .continuous
                        )
                        .fill(
                            LinearGradient(
                                colors: cameraManager.isRecording
                                    ? [Color.red, Color(red: 0.85, green: 0.1, blue: 0.1)]
                                    : [Color(red: 1.0, green: 0.25, blue: 0.25), Color.red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(
                            width: cameraManager.isRecording ? 28 : 56,
                            height: cameraManager.isRecording ? 28 : 56
                        )
                        .shadow(color: cameraManager.isRecording ? Color.red.opacity(0.6) : Color.clear, radius: 8)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: cameraManager.isRecording)
                    }
                }
            }
            .disabled(!cameraManager.isSessionRunning || cameraManager.isSaving)
            .accessibilityLabel(cameraManager.isRecording ? "Stop Recording" : "Start Recording")

            // Status Caption under Shutter
            Text(cameraManager.isSaving ? "SAVING" : (cameraManager.isRecording ? "STOP" : "REC"))
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(cameraManager.isRecording ? Color.red : Color.white.opacity(0.85))
        }
    }

    // MARK: - Toast Banner & Feedback

    private func statusToastView(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.green)

            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.8), in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8)
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
