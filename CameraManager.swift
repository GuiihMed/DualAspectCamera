import AVFoundation
import Combine
import CoreImage
import Metal
import Photos
import UIKit

enum CameraError: LocalizedError {
    case cameraUnavailable
    case permissionDenied(String)
    case writerFailedToStart
    case writerNotRecording
    case noFramesRecorded
    case writerFinishFailed
    case photoLibraryDenied

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "Main rear wide-angle camera is unavailable."
        case .permissionDenied(let resource):
            return "\(resource) permission was denied. Enable it in Settings."
        case .writerFailedToStart:
            return "Failed to start AVAssetWriter."
        case .writerNotRecording:
            return "Asset writer is not in writing state."
        case .noFramesRecorded:
            return "Recording stopped before any frames were captured."
        case .writerFinishFailed:
            return "Failed to finalize recorded video file."
        case .photoLibraryDenied:
            return "Photo Library access is required to save videos."
        }
    }
}

// MARK: - Single-Aspect Hardware Asset Writer Wrapper

/// Encapsulates a single `AVAssetWriter` pipeline (video + optional audio) for one aspect ratio.
/// All methods MUST be invoked exclusively on `CameraManager.processingQueue`.
final class AspectAssetWriter {
    let outputURL: URL
    let width: Int
    let height: Int

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private(set) var isSessionStarted: Bool = false

    init(
        outputURL: URL,
        width: Int,
        height: Int,
        averageBitRate: Int,
        audioSettings: [String: Any]?
    ) throws {
        self.outputURL = outputURL
        self.width = width
        self.height = height

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: averageBitRate,
            AVVideoExpectedSourceFrameRateKey: 30,
            AVVideoMaxKeyFrameIntervalKey: 30
        ]

        // Prefer hardware HEVC encoding for lower thermal & I/O load; fall back to H.264 if needed.
        var videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]
        if !writer.canApply(outputSettings: videoSettings, forMediaType: .video) {
            videoSettings[AVVideoCodecKey] = AVVideoCodecType.h264
        }

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true

        // Match native camera bi-planar YUV (420f) + IOSurface + Metal to avoid RGB conversions.
        let sourceBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vInput,
            sourcePixelBufferAttributes: sourceBufferAttributes
        )

        guard writer.canAdd(vInput) else {
            throw CameraError.writerFailedToStart
        }
        writer.add(vInput)

        if let audioSettings, writer.canApply(outputSettings: audioSettings, forMediaType: .audio) {
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true
            if writer.canAdd(aInput) {
                writer.add(aInput)
                self.audioInput = aInput
            } else {
                self.audioInput = nil
            }
        } else {
            self.audioInput = nil
        }

        guard writer.startWriting() else {
            throw writer.error ?? CameraError.writerFailedToStart
        }

        self.writer = writer
        self.videoInput = vInput
        self.pixelBufferAdaptor = adaptor
    }

    func startSessionIfNeeded(at presentationTime: CMTime) {
        guard !isSessionStarted, writer.status == .writing else { return }
        writer.startSession(atSourceTime: presentationTime)
        isSessionStarted = true
    }

    func appendVideo(
        sourceBuffer: CVPixelBuffer,
        sourceImage: CIImage,
        cropRect: CGRect,
        presentationTime: CMTime,
        ciContext: CIContext,
        allowZeroCopyPassthrough: Bool
    ) {
        startSessionIfNeeded(at: presentationTime)
        guard writer.status == .writing, videoInput.isReadyForMoreMediaData else { return }

        let srcWidth = CVPixelBufferGetWidth(sourceBuffer)
        let srcHeight = CVPixelBufferGetHeight(sourceBuffer)

        // Fast path: when source frame already matches target 16:9 dimensions, pass buffer zero-copy.
        if allowZeroCopyPassthrough,
           srcWidth == width,
           srcHeight == height,
           Int(cropRect.origin.x) == 0,
           Int(cropRect.origin.y) == 0 {
            pixelBufferAdaptor.append(sourceBuffer, withPresentationTime: presentationTime)
            return
        }

        guard let pool = pixelBufferAdaptor.pixelBufferPool else { return }
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outputBuffer)
        guard status == kCVReturnSuccess, let dstBuffer = outputBuffer else { return }

        // Preserve Rec.709 / P3 YCbCr matrix, primaries, and transfer function attachments.
        CVBufferPropagateAttachments(sourceBuffer, dstBuffer)

        // 1. Crop and shift origin to (0, 0) so CIContext aligns with the destination CVPixelBuffer.
        var processed = sourceImage
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(
                translationX: -cropRect.origin.x,
                y: -cropRect.origin.y
            ))

        // 2. Scale if writer target dimensions differ from cropRect size.
        let scaleX = CGFloat(width) / cropRect.width
        let scaleY = CGFloat(height) / cropRect.height
        if abs(scaleX - 1.0) > 0.001 || abs(scaleY - 1.0) > 0.001 {
            processed = processed.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        }

        let bounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        ciContext.render(processed, to: dstBuffer, bounds: bounds, colorSpace: nil)

        pixelBufferAdaptor.append(dstBuffer, withPresentationTime: presentationTime)
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard isSessionStarted,
              writer.status == .writing,
              let audioInput,
              audioInput.isReadyForMoreMediaData else { return }

        // Duplicate CMSampleBuffer metadata container so two AVAssetWriters never race on attachments.
        var copiedSampleBuffer: CMSampleBuffer?
        let copyStatus = CMSampleBufferCreateCopy(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleBufferOut: &copiedSampleBuffer
        )
        if copyStatus == noErr, let copiedSampleBuffer {
            audioInput.append(copiedSampleBuffer)
        }
    }

    func finish(completion: @escaping (Result<URL, Error>) -> Void) {
        guard writer.status == .writing else {
            completion(.failure(writer.error ?? CameraError.writerNotRecording))
            return
        }
        guard isSessionStarted else {
            writer.cancelWriting()
            completion(.failure(CameraError.noFramesRecorded))
            return
        }

        videoInput.markAsFinished()
        audioInput?.markAsFinished()

        let url = outputURL
        let assetWriter = writer
        assetWriter.finishWriting {
            if assetWriter.status == .completed {
                completion(.success(url))
            } else {
                completion(.failure(assetWriter.error ?? CameraError.writerFinishFailed))
            }
        }
    }
}

private final class WriterBatchResult: @unchecked Sendable {
    var savedURLs: [URL] = []
    var finishErrors: [Error] = []
    private let lock = NSLock()

    func record(_ result: Result<URL, Error>) {
        lock.lock()
        defer { lock.unlock() }
        switch result {
        case .success(let url): savedURLs.append(url)
        case .failure(let error): finishErrors.append(error)
        }
    }
}

// MARK: - CameraManager

final class CameraManager: NSObject, ObservableObject, @unchecked Sendable {
    // MARK: Published UI State (Always updated on Main Thread)
    @Published private(set) var isSessionRunning: Bool = false
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var isSaving: Bool = false
    @Published private(set) var zoomFactor: CGFloat = 1.0
    @Published private(set) var minZoomFactor: CGFloat = 1.0
    @Published private(set) var maxZoomFactor: CGFloat = 5.0
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var activeResolutionLabel: String = "4K UHD"
    @Published private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    @Published var statusMessage: String?

    // MARK: Capture Pipeline Properties
    let session = AVCaptureSession()
    private let maxAllowedZoom: CGFloat = 5.0

    private let sessionQueue = DispatchQueue(
        label: "com.dualaspect.camera.sessionQueue",
        qos: .userInitiated
    )
    private let processingQueue = DispatchQueue(
        label: "com.dualaspect.camera.processingQueue",
        qos: .userInitiated
    )

    private var videoDevice: AVCaptureDevice?
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private var isConfigured = false
    private var hasAudioInput = false

    // Metal-backed CIContext with unmanaged color space to avoid costly YUV->LinearRGB->YUV conversions.
    private let ciContext: CIContext = {
        let options: [CIContextOption: Any] = [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull(),
            .cacheIntermediates: false
        ]
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: metalDevice, options: options)
        }
        return CIContext(options: options)
    }()

    // Writer State (Accessed exclusively on processingQueue)
    private var isRecordingRequested = false
    private var horizontalWriter: AspectAssetWriter?
    private var verticalWriter: AspectAssetWriter?
    private var cachedAudioSettings: [String: Any]?
    private var recordingStartPTS: CMTime?
    private var lastPublishedSecond: Int = -1

    private var thermalObserver: NSObjectProtocol?

    override init() {
        super.init()
        observeThermalState()
    }

    deinit {
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
        }
    }

    // MARK: - Lifecycle & Permissions

    func start() {
        Task {
            let videoGranted = await requestCapturePermission(for: .video)
            guard videoGranted else {
                publishStatus(CameraError.permissionDenied("Camera").localizedDescription)
                return
            }
            let audioGranted = await requestCapturePermission(for: .audio)

            await MainActor.run {
                UIApplication.shared.isIdleTimerDisabled = true
            }

            sessionQueue.async { [weak self] in
                guard let self else { return }
                self.configureSessionIfNeeded(includeAudio: audioGranted)
                if !self.session.isRunning {
                    self.session.startRunning()
                    let running = self.session.isRunning
                    DispatchQueue.main.async {
                        self.isSessionRunning = running
                    }
                }
            }
        }
    }

    func stop() {
        if isRecording {
            stopRecording()
        }
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = false
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    private func requestCapturePermission(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: mediaType)
        default:
            return false
        }
    }

    // MARK: - AVCaptureSession Configuration

    private func configureSessionIfNeeded(includeAudio: Bool) {
        guard !isConfigured else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Explicitly select the main rear wide-angle camera.
        guard let rearCamera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            publishStatus(CameraError.cameraUnavailable.localizedDescription)
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: rearCamera)
            guard session.canAddInput(videoInput) else {
                publishStatus("Unable to attach rear camera input.")
                return
            }
            session.addInput(videoInput)
            self.videoDevice = rearCamera
        } catch {
            publishStatus("Camera input error: \(error.localizedDescription)")
            return
        }

        // Highest available 16:9 resolution preset (preferring 4K 3840x2160).
        let resolutionText: String
        if session.canSetSessionPreset(.hd4K3840x2160) {
            session.sessionPreset = .hd4K3840x2160
            resolutionText = "4K UHD"
        } else if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
            resolutionText = "1080p FHD"
        } else {
            session.sessionPreset = .high
            resolutionText = "High"
        }

        configureCameraHardwareDefaults(rearCamera, fps: 30)

        let minZoom = rearCamera.minAvailableVideoZoomFactor
        let maxZoom = min(maxAllowedZoom, rearCamera.maxAvailableVideoZoomFactor)
        DispatchQueue.main.async {
            self.minZoomFactor = minZoom
            self.maxZoomFactor = maxZoom
            self.zoomFactor = rearCamera.videoZoomFactor
            self.activeResolutionLabel = resolutionText
        }

        // Video frame interception output (bi-planar 420f YUV, dropping late frames under load).
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        ]
        videoDataOutput.setSampleBufferDelegate(self, queue: processingQueue)

        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            if let connection = videoDataOutput.connection(with: .video) {
                applyLandscapeRotation(to: connection, interfaceOrientation: .landscapeRight)
                if connection.isVideoStabilizationSupported {
                    // Use .standard instead of .cinematicExtended to avoid large 4K frame lookahead buffers.
                    connection.preferredVideoStabilizationMode = .standard
                }
            }
        }

        // Optional audio capture output for synchronized audio in both output files.
        if includeAudio,
           let micDevice = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: micDevice),
           session.canAddInput(micInput) {
            session.addInput(micInput)
            audioDataOutput.setSampleBufferDelegate(self, queue: processingQueue)
            if session.canAddOutput(audioDataOutput) {
                session.addOutput(audioDataOutput)
                hasAudioInput = true
            }
        }

        let recommendedAudio = hasAudioInput
            ? (audioDataOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mp4) ?? Self.fallbackAudioSettings)
            : nil
        processingQueue.async { [weak self] in
            self?.cachedAudioSettings = recommendedAudio
        }

        isConfigured = true
    }

    private func configureCameraHardwareDefaults(_ device: AVCaptureDevice, fps: Int32) {
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }

            let targetDuration = CMTime(value: 1, timescale: fps)
            let supportsTargetFPS = device.activeFormat.videoSupportedFrameRateRanges.contains { range in
                CMTimeCompare(range.minFrameDuration, targetDuration) <= 0 &&
                CMTimeCompare(targetDuration, range.maxFrameDuration) <= 0
            }
            if supportsTargetFPS {
                device.activeVideoMinFrameDuration = targetDuration
                device.activeVideoMaxFrameDuration = targetDuration
            }
            device.unlockForConfiguration()
        } catch {
            publishStatus("Device configuration failed: \(error.localizedDescription)")
        }
    }

    private static let fallbackAudioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 128_000
    ]

    // MARK: - Orientation Sync (Landscape 16:9 Capture)

    func updateInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        guard orientation == .landscapeLeft || orientation == .landscapeRight else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.processingQueue.async {
                // Never rotate capture buffer geometry mid-recording.
                guard !self.isRecordingRequested else { return }
                if let connection = self.videoDataOutput.connection(with: .video) {
                    self.applyLandscapeRotation(to: connection, interfaceOrientation: orientation)
                }
            }
        }
    }

    func applyLandscapeRotation(to connection: AVCaptureConnection, interfaceOrientation: UIInterfaceOrientation) {
        // Rear camera native sensor orientation (0°) corresponds to .landscapeRight (camera top-left).
        let angle: CGFloat = (interfaceOrientation == .landscapeLeft) ? 180.0 : 0.0
        if #available(iOS 17.0, *) {
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = (interfaceOrientation == .landscapeLeft)
                    ? .landscapeLeft
                    : .landscapeRight
            }
        }
    }

    // MARK: - Real-Time Hardware Zoom

    /// Adjusts `videoZoomFactor` safely during preview or active recording without interrupting capture.
    func setZoomFactor(_ requestedFactor: CGFloat) {
        let uiClamped = min(max(requestedFactor, minZoomFactor), maxZoomFactor)
        if Thread.isMainThread {
            self.zoomFactor = uiClamped
        } else {
            DispatchQueue.main.async { self.zoomFactor = uiClamped }
        }

        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            let hardwareMin = device.minAvailableVideoZoomFactor
            let hardwareMax = min(self.maxAllowedZoom, device.maxAvailableVideoZoomFactor)
            let clamped = min(max(requestedFactor, hardwareMin), hardwareMax)

            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {
                self.publishStatus("Zoom adjustment error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Recording Control

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isRecording, !isSaving else { return }

        DispatchQueue.main.async {
            self.statusMessage = nil
            self.recordingDuration = 0
            self.isRecording = true
        }

        processingQueue.async { [weak self] in
            guard let self else { return }
            self.horizontalWriter = nil
            self.verticalWriter = nil
            self.recordingStartPTS = nil
            self.lastPublishedSecond = -1
            self.isRecordingRequested = true
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        DispatchQueue.main.async {
            self.isRecording = false
            self.isSaving = true
        }

        processingQueue.async { [weak self] in
            guard let self else { return }
            self.isRecordingRequested = false

            let hWriter = self.horizontalWriter
            let vWriter = self.verticalWriter
            self.horizontalWriter = nil
            self.verticalWriter = nil
            self.recordingStartPTS = nil

            guard let hWriter, let vWriter else {
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.statusMessage = "Recording was too short to save."
                }
                return
            }

            let group = DispatchGroup()
            let batchResult = WriterBatchResult()

            group.enter()
            hWriter.finish { result in
                batchResult.record(result)
                group.leave()
            }

            group.enter()
            vWriter.finish { result in
                batchResult.record(result)
                group.leave()
            }

            group.notify(queue: .global(qos: .userInitiated)) { [weak self] in
                guard let self else { return }
                let urls = batchResult.savedURLs
                let errors = batchResult.finishErrors

                if !errors.isEmpty || urls.count < 2 {
                    self.cleanupTempFiles(urls)
                    let msg = errors.first?.localizedDescription ?? "Failed to finalize dual video."
                    DispatchQueue.main.async {
                        self.isSaving = false
                        self.statusMessage = msg
                    }
                    return
                }
                self.saveVideosToPhotoLibrary(urls: urls)
            }
        }
    }

    // MARK: - Saving to Photo Gallery

    private func saveVideosToPhotoLibrary(urls: [URL]) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self else { return }
            guard status == .authorized || status == .limited else {
                self.cleanupTempFiles(urls)
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.statusMessage = CameraError.photoLibraryDenied.localizedDescription
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                for url in urls {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }
            }, completionHandler: { [weak self] success, error in
                guard let self else { return }
                // Delete temporary sandbox .mp4 files immediately after PhotoKit imports them.
                self.cleanupTempFiles(urls)

                DispatchQueue.main.async {
                    self.isSaving = false
                    if success {
                        self.statusMessage = "Saved 16:9 & 9:16 videos to Photos"
                        self.autoClearStatusBanner()
                    } else {
                        self.statusMessage = "Save error: \(error?.localizedDescription ?? "Unknown")"
                    }
                }
            })
        }
    }

    private func cleanupTempFiles(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Thermal Management Observer

    private func observeThermalState() {
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let state = ProcessInfo.processInfo.thermalState
            self.thermalState = state

            // Proactively step frame rate down to 24 fps under serious/critical thermal pressure.
            let targetFPS: Int32 = (state == .serious || state == .critical) ? 24 : 30
            self.sessionQueue.async {
                if let device = self.videoDevice {
                    self.configureCameraHardwareDefaults(device, fps: targetFPS)
                }
            }
        }
    }

    // MARK: - Crop Geometry Helpers

    /// Computes a centered crop rectangle aligned to 2-pixel boundaries (required for 4:2:0 YpCbCr chroma).
    static func centeredEvenCropRect(in sourceSize: CGSize, targetAspect: CGFloat) -> CGRect {
        let srcAspect = sourceSize.width / sourceSize.height
        let rawWidth: CGFloat
        let rawHeight: CGFloat

        if srcAspect > targetAspect {
            rawHeight = sourceSize.height
            rawWidth = sourceSize.height * targetAspect
        } else {
            rawWidth = sourceSize.width
            rawHeight = sourceSize.width / targetAspect
        }

        let evenWidth = CGFloat((Int((rawWidth / 2.0).rounded()) * 2))
        let evenHeight = CGFloat((Int((rawHeight / 2.0).rounded()) * 2))
        let clampedWidth = min(evenWidth, CGFloat((Int(sourceSize.width) / 2) * 2))
        let clampedHeight = min(evenHeight, CGFloat((Int(sourceSize.height) / 2) * 2))

        // Align origin to even pixel coordinates to avoid splitting 2x2 UV chroma blocks.
        let originX = CGFloat((Int((sourceSize.width - clampedWidth) / 2.0) / 2) * 2)
        let originY = CGFloat((Int((sourceSize.height - clampedHeight) / 2.0) / 2) * 2)

        return CGRect(x: originX, y: originY, width: clampedWidth, height: clampedHeight)
    }

    private func initializeWritersForFrame(size: CGSize) throws {
        let horizontalRect = Self.centeredEvenCropRect(in: size, targetAspect: 16.0 / 9.0)
        let verticalRect = Self.centeredEvenCropRect(in: size, targetAspect: 9.0 / 16.0)

        let timestamp = Int(Date().timeIntervalSince1970)
        let tempDir = FileManager.default.temporaryDirectory
        let horizontalURL = tempDir.appendingPathComponent("DualCam_16x9_\(timestamp)_\(UUID().uuidString.prefix(6)).mp4")
        let verticalURL = tempDir.appendingPathComponent("DualCam_9x16_\(timestamp)_\(UUID().uuidString.prefix(6)).mp4")

        // Scale target HEVC bitrate proportionally to pixel count (~3.4 bits/pixel/sec at 30fps -> ~28 Mbps for 4K 16:9).
        let hPixels = Int(horizontalRect.width * horizontalRect.height)
        let vPixels = Int(verticalRect.width * verticalRect.height)
        let hBitrate = max(6_000_000, Int(Double(hPixels) * 3.4))
        let vBitrate = max(4_000_000, Int(Double(vPixels) * 3.4))

        horizontalWriter = try AspectAssetWriter(
            outputURL: horizontalURL,
            width: Int(horizontalRect.width),
            height: Int(horizontalRect.height),
            averageBitRate: hBitrate,
            audioSettings: cachedAudioSettings
        )
        verticalWriter = try AspectAssetWriter(
            outputURL: verticalURL,
            width: Int(verticalRect.width),
            height: Int(verticalRect.height),
            averageBitRate: vBitrate,
            audioSettings: cachedAudioSettings
        )
    }

    private func publishStatus(_ message: String) {
        DispatchQueue.main.async {
            self.statusMessage = message
        }
    }

    private func autoClearStatusBanner() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, self.statusMessage == "Saved 16:9 & 9:16 videos to Photos" else { return }
            self.statusMessage = nil
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate & AVCaptureAudioDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Drain temporary CoreImage / CoreMedia bridged objects immediately at the end of every frame.
        autoreleasepool {
            guard isRecordingRequested, CMSampleBufferDataIsReady(sampleBuffer) else { return }

            if output === videoDataOutput {
                handleVideoSampleBuffer(sampleBuffer)
            } else if output === audioDataOutput {
                handleAudioSampleBuffer(sampleBuffer)
            }
        }
    }

    private func handleVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        let rawWidth = CVPixelBufferGetWidth(pixelBuffer)
        let rawHeight = CVPixelBufferGetHeight(pixelBuffer)
        let frameSize = CGSize(width: rawWidth, height: rawHeight)

        // Lazily initialize both AVAssetWriters using the exact incoming sensor buffer dimensions.
        if horizontalWriter == nil || verticalWriter == nil {
            do {
                try initializeWritersForFrame(size: frameSize)
                recordingStartPTS = presentationTime
            } catch {
                isRecordingRequested = false
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.statusMessage = "Failed to start writers: \(error.localizedDescription)"
                }
                return
            }
        }

        guard let hWriter = horizontalWriter, let vWriter = verticalWriter else { return }

        // Compute centered 16:9 (Horizontal) and 9:16 (Vertical) crop rects.
        let horizontalCropRect = Self.centeredEvenCropRect(in: frameSize, targetAspect: 16.0 / 9.0)
        let verticalCropRect = Self.centeredEvenCropRect(in: frameSize, targetAspect: 9.0 / 16.0)

        let sourceCIImage = CIImage(cvPixelBuffer: pixelBuffer, options: [.colorSpace: NSNull()])

        // 1. Center-crop to 9:16 Vertical and encode via vertical AVAssetWriter.
        vWriter.appendVideo(
            sourceBuffer: pixelBuffer,
            sourceImage: sourceCIImage,
            cropRect: verticalCropRect,
            presentationTime: presentationTime,
            ciContext: ciContext,
            allowZeroCopyPassthrough: false
        )

        // 2. Crop/passthrough to 16:9 Horizontal and encode via horizontal AVAssetWriter.
        hWriter.appendVideo(
            sourceBuffer: pixelBuffer,
            sourceImage: sourceCIImage,
            cropRect: horizontalCropRect,
            presentationTime: presentationTime,
            ciContext: ciContext,
            allowZeroCopyPassthrough: true
        )

        // Throttle elapsed recording duration updates to 1 Hz on the main thread.
        if let startPTS = recordingStartPTS {
            let elapsed = CMTimeGetSeconds(CMTimeSubtract(presentationTime, startPTS))
            let wholeSeconds = max(0, Int(elapsed))
            if wholeSeconds != lastPublishedSecond {
                lastPublishedSecond = wholeSeconds
                DispatchQueue.main.async {
                    self.recordingDuration = elapsed
                }
            }
        }
    }

    private func handleAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // Only write audio once the first video frame has started the writer session.
        guard let hWriter = horizontalWriter,
              let vWriter = verticalWriter,
              hWriter.isSessionStarted,
              vWriter.isSessionStarted else { return }

        hWriter.appendAudio(sampleBuffer)
        vWriter.appendAudio(sampleBuffer)
    }
}
