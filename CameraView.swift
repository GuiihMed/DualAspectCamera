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
        view.previewLayer.videoGravity = .resizeAspect
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

/// Draws the full 16:9 horizontal frame with the exact centered 9:16 vertical crop guide and dimmed sides.
struct FramingGuideOverlay: View {
    let isRecording: Bool

    var body: some View {
        GeometryReader { proxy in
            let containerRect = CGRect(origin: .zero, size: proxy.size)
            // Compute the exact rendered 16:9 horizontal video frame inside the preview layer
            let videoRect = AVMakeRect(
                aspectRatio: CGSize(width: 16, height: 9),
                insideRect: containerRect
            )

            // Exact 9:16 vertical crop rectangle centered in the middle of the 16:9 feed
            let verticalCropWidth = videoRect.height * (9.0 / 16.0)
            let verticalSafeRect = CGRect(
                x: videoRect.midX - (verticalCropWidth / 2.0),
                y: videoRect.minY,
                width: verticalCropWidth,
                height: videoRect.height
            )

            let leftMaskWidth = max(0, verticalSafeRect.minX - videoRect.minX)
            let rightMaskWidth = max(0, videoRect.maxX - verticalSafeRect.maxX)

            ZStack {
                // 1. Dimmed left and right flanks (outside the 9:16 vertical safe zone)
                Rectangle()
                    .fill(Color.black.opacity(0.38))
                    .frame(width: leftMaskWidth, height: videoRect.height)
                    .position(
                        x: videoRect.minX + (leftMaskWidth / 2.0),
                        y: videoRect.midY
                    )

                Rectangle()
                    .fill(Color.black.opacity(0.38))
                    .frame(width: rightMaskWidth, height: videoRect.height)
                    .position(
                        x: verticalSafeRect.maxX + (rightMaskWidth / 2.0),
                        y: videoRect.midY
                    )

                // 2. Subtle outer 16:9 boundary line
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                    .frame(width: videoRect.width, height: videoRect.height)
                    .position(x: videoRect.midX, y: videoRect.midY)

                // 3. Centered 9:16 Vertical Safe-Area Box
                Rectangle()
                    .strokeBorder(
                        isRecording ? Color.yellow : Color.white,
                        lineWidth: 1.5
                    )
                    .frame(width: verticalSafeRect.width, height: verticalSafeRect.height)
                    .position(x: verticalSafeRect.midX, y: verticalSafeRect.midY)

                // Prominent Left Vertical Guide Line
                Path { path in
                    path.move(to: CGPoint(x: verticalSafeRect.minX, y: verticalSafeRect.minY))
                    path.addLine(to: CGPoint(x: verticalSafeRect.minX, y: verticalSafeRect.maxY))
                }
                .stroke(isRecording ? Color.yellow : Color.white, lineWidth: 2)

                // Prominent Right Vertical Guide Line
                Path { path in
                    path.move(to: CGPoint(x: verticalSafeRect.maxX, y: verticalSafeRect.minY))
                    path.addLine(to: CGPoint(x: verticalSafeRect.maxX, y: verticalSafeRect.maxY))
                }
                .stroke(isRecording ? Color.yellow : Color.white, lineWidth: 2)

                // Corner ticks on the 9:16 frame for fast framing alignment
                CornerTicksShape(tickLength: 18)
                    .stroke(
                        isRecording ? Color.yellow : Color.white,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: verticalSafeRect.width, height: verticalSafeRect.height)
                    .position(x: verticalSafeRect.midX, y: verticalSafeRect.midY)

                // Center crosshair dot inside the 9:16 frame
                Circle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 4, height: 4)
                    .position(x: verticalSafeRect.midX, y: verticalSafeRect.midY)

                // 4. Badges indicating the dual capture regions
                HStack(spacing: 4) {
                    Image(systemName: "iphone")
                        .font(.system(size: 9, weight: .bold))
                    Text("9:16 VERTICAL")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(isRecording ? Color.yellow : Color.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.6), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isRecording ? Color.yellow.opacity(0.6) : Color.white.opacity(0.3), lineWidth: 1)
                )
                .position(
                    x: verticalSafeRect.midX,
                    y: verticalSafeRect.minY + 22
                )
            }
        }
        .allowsHitTesting(false)
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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 1. Full-screen Camera Preview + Pinch-to-Zoom Gesture
            CameraPreviewView(cameraManager: cameraManager)
                .ignoresSafeArea()
                .gesture(pinchToZoomGesture)

            // 2. Centered 9:16 Safe-Area Framing Guide over full 16:9 feed
            FramingGuideOverlay(isRecording: cameraManager.isRecording)
                .ignoresSafeArea()

            // 3. Top & Edge Controls Overlay
            VStack {
                topStatusBar
                Spacer()
                if let banner = cameraManager.statusMessage {
                    statusBannerView(banner)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)

            HStack {
                edgeZoomControl
                Spacer()
                recordButtonPanel
            }
            .padding(.horizontal, 20)
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

    // MARK: - Top Camera Indicator Bar

    private var topStatusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(cameraManager.isRecording ? Color.red : Color.green)
                .frame(width: 7, height: 7)

            Text("Main Rear Camera Active")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            Text("• \(cameraManager.activeResolutionLabel) 16:9 + 9:16")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.65))

            if cameraManager.thermalState == .serious || cameraManager.thermalState == .critical {
                Text("• THERMAL THROTTLE (24 FPS)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Leading-Edge Vertical Zoom Slider

    private var edgeZoomControl: some View {
        VStack(spacing: 10) {
            Text(String(format: "%.1fx", cameraManager.zoomFactor))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.yellow)
                .frame(width: 46)

            Slider(
                value: Binding(
                    get: { Double(cameraManager.zoomFactor) },
                    set: { cameraManager.setZoomFactor(CGFloat($0)) }
                ),
                in: Double(cameraManager.minZoomFactor)...Double(cameraManager.maxZoomFactor)
            )
            .tint(.yellow)
            .frame(width: 165)
            .rotationEffect(.degrees(-90))
            .frame(width: 36, height: 165)

            Text(String(format: "%.0fx", cameraManager.minZoomFactor))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Trailing-Edge Floating Record / Stop Button

    private var recordButtonPanel: some View {
        VStack(spacing: 10) {
            if cameraManager.isRecording {
                Text(formattedDuration(cameraManager.recordingDuration))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.85), in: Capsule())
            }

            Button {
                cameraManager.toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 4)
                        .frame(width: 72, height: 72)

                    if cameraManager.isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        RoundedRectangle(
                            cornerRadius: cameraManager.isRecording ? 8 : 30,
                            style: .continuous
                        )
                        .fill(Color.red)
                        .frame(
                            width: cameraManager.isRecording ? 28 : 58,
                            height: cameraManager.isRecording ? 28 : 58
                        )
                        .animation(.easeInOut(duration: 0.18), value: cameraManager.isRecording)
                    }
                }
            }
            .disabled(!cameraManager.isSessionRunning || cameraManager.isSaving)
            .accessibilityLabel(cameraManager.isRecording ? "Stop Recording" : "Start Recording")

            Text(cameraManager.isRecording ? "Stop" : "Record")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func statusBannerView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.72), in: Capsule())
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
