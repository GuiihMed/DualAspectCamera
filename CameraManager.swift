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
            return "Camera is unavailable."
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

        CVBufferPropagateAttachments(sourceBuffer, dstBuffer)

        var processed = sourceImage
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(
                translationX: -cropRect.origin.x,
                y: -cropRect.origin.y
            ))

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
    // MARK: Published UI State
    @Published private(set) var isSessionRunning: Bool = false
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var isSaving: Bool = false
    @Published private(set) var zoomFactor: CGFloat = 1.0
    @Published private(set) var minZoomFactor: CGFloat = 0.5
    @Published private(set) var maxZoomFactor: CGFloat = 10.0
    @Published private(set) var isUltraWideAvailable: Bool = false
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published private(set) var activeResolutionLabel: String = "4K UHD"
    @Published private(set) var sessionPreset: AVCaptureSession.Preset = .hd4K3840x2160
    @Published private(set) var activeFPS: Int32 = 30
    @Published private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    @Published var statusMessage: String?
    @Published private(set) var isTorchAvailable: Bool = false
    @Published private(set) var isTorchOn: Bool = false
    @Published private(set) var isFrontCamera: Bool = false
    @Published private(set) var currentExposureBias: Float = 0.0
    @Published private(set) var minExposureBias: Float = -2.0
    @Published private(set) var maxExposureBias: Float = 2.0
    @Published private(set) var latestThumbnail: UIImage? = nil

    // MARK: Capture Pipeline Properties
    let session = AVCaptureSession()
    private var wideBaseZoomMultiplier: CGFloat = 1.0

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
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private var hasAudioInput = false

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

    // Writer State
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

            fetchLatestPhotoThumbnail()
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

        // Discover best rear camera system: Triple Camera -> Dual Wide -> Standard Wide
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInWideAngleCamera
            ],
            mediaType: .video,
            position: .back
        )

        guard let rearCamera = discoverySession.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            publishStatus(CameraError.cameraUnavailable.localizedDescription)
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: rearCamera)
            guard session.canAddInput(videoInput) else {
                publishStatus("Unable to attach camera input.")
                return
            }
            session.addInput(videoInput)
            self.videoDevice = rearCamera
        } catch {
            publishStatus("Camera input error: \(error.localizedDescription)")
            return
        }

        // Resolution preset
        let initialPreset: AVCaptureSession.Preset = session.canSetSessionPreset(.hd4K3840x2160) ? .hd4K3840x2160 : (session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high)
        session.sessionPreset = initialPreset
        let resolutionText = (initialPreset == .hd4K3840x2160) ? "4K UHD" : ((initialPreset == .hd1920x1080) ? "1080p FHD" : "HD")

        configureCameraHardwareDefaults(rearCamera, fps: 30)

        // Ultra-wide check: on triple/dualWide camera, switchover to 1.0x wide lens is usually at hardware zoom 2.0.
        let isVirtualMulti = (rearCamera.deviceType == .builtInTripleCamera || rearCamera.deviceType == .builtInDualWideCamera)
        let switchFactors = rearCamera.virtualDeviceSwitchOverVideoZoomFactors
        let baseMultiplier: CGFloat = (isVirtualMulti && !switchFactors.isEmpty) ? CGFloat(switchFactors[0].doubleValue) : (isVirtualMulti ? 2.0 : 1.0)
        self.wideBaseZoomMultiplier = baseMultiplier

        let hasUltraWide = isVirtualMulti || (baseMultiplier > 1.0)
        let minUserZoom: CGFloat = hasUltraWide ? 0.5 : 1.0
        let maxUserZoom: CGFloat = min(10.0, rearCamera.maxAvailableVideoZoomFactor / max(1.0, baseMultiplier))
        let hasTorch = rearCamera.hasTorch && rearCamera.isTorchAvailable

        let minBias = rearCamera.minExposureTargetBias
        let maxBias = rearCamera.maxExposureTargetBias

        DispatchQueue.main.async {
            self.isUltraWideAvailable = hasUltraWide
            self.minZoomFactor = minUserZoom
            self.maxZoomFactor = max(minUserZoom, maxUserZoom)
            self.zoomFactor = 1.0
            self.sessionPreset = initialPreset
            self.activeResolutionLabel = resolutionText
            self.activeFPS = 30
            self.isTorchAvailable = hasTorch
            self.isTorchOn = (rearCamera.torchMode == .on)
            self.minExposureBias = minBias
            self.maxExposureBias = maxBias
            self.currentExposureBias = 0.0
        }

        // Set initial hardware zoom to 1.0x user factor (wide lens)
        setZoomFactor(1.0)

        // Video frame output
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
                    connection.preferredVideoStabilizationMode = .standard
                }
            }
        }

        // Photo capture output for high-res stills
        if session.canAddOutput(photoOutput) {
            photoOutput.isHighResolutionCaptureEnabled = true
            if #available(iOS 13.0, *) {
                photoOutput.maxPhotoQualityPrioritization = .balanced
            }
            session.addOutput(photoOutput)
        }

        // Optional audio capture output
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

    // MARK: - Orientation Sync

    func updateInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.processingQueue.async {
                guard !self.isRecordingRequested else { return }
                if let connection = self.videoDataOutput.connection(with: .video) {
                    self.applyRotation(to: connection, interfaceOrientation: orientation)
                }
            }
        }
    }

    func applyRotation(to connection: AVCaptureConnection, interfaceOrientation: UIInterfaceOrientation) {
        let angle: CGFloat
        switch interfaceOrientation {
        case .portrait: angle = 90.0
        case .portraitUpsideDown: angle = 270.0
        case .landscapeLeft: angle = 180.0
        case .landscapeRight: angle = 0.0
        default: angle = 90.0
        }

        if #available(iOS 17.0, *) {
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else {
            if connection.isVideoOrientationSupported {
                switch interfaceOrientation {
                case .portrait: connection.videoOrientation = .portrait
                case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
                case .landscapeLeft: connection.videoOrientation = .landscapeLeft
                case .landscapeRight: connection.videoOrientation = .landscapeRight
                default: connection.videoOrientation = .portrait
                }
            }
        }
    }

    func applyLandscapeRotation(to connection: AVCaptureConnection, interfaceOrientation: UIInterfaceOrientation) {
        applyRotation(to: connection, interfaceOrientation: interfaceOrientation)
    }

    // MARK: - Zoom Control (0.5x Ultra-Wide to 10.0x Telephoto)

    func setZoomFactor(_ requestedUserZoom: CGFloat) {
        let clampedUserZoom = min(max(requestedUserZoom, minZoomFactor), maxZoomFactor)
        DispatchQueue.main.async {
            self.zoomFactor = clampedUserZoom
        }

        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }

            // Convert user zoom to hardware zoom
            let hardwareZoom: CGFloat
            if self.wideBaseZoomMultiplier > 1.0 {
                if clampedUserZoom <= 0.55 {
                    hardwareZoom = 1.0 // Physical Ultra-Wide Lens
                } else {
                    hardwareZoom = clampedUserZoom * self.wideBaseZoomMultiplier
                }
            } else {
                hardwareZoom = clampedUserZoom
            }

            let hardwareMin = device.minAvailableVideoZoomFactor
            let hardwareMax = device.maxAvailableVideoZoomFactor
            let finalClamped = min(max(hardwareZoom, hardwareMin), hardwareMax)

            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = finalClamped
                device.unlockForConfiguration()
            } catch {
                self.publishStatus("Zoom error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Exposure Control (Controle de Luz)

    func setExposureBias(normalized: CGFloat) {
        // normalized is 0.0 (darkest) to 1.0 (brightest), with 0.5 neutral (0.0 EV)
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            let minBias = device.minExposureTargetBias
            let maxBias = device.maxExposureTargetBias

            let targetBias: Float
            if normalized < 0.5 {
                targetBias = Float(1.0 - (normalized * 2.0)) * minBias
            } else {
                targetBias = Float((normalized - 0.5) * 2.0) * maxBias
            }
            let clamped = min(max(targetBias, minBias), maxBias)

            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(clamped, completionHandler: nil)
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.currentExposureBias = clamped
                }
            } catch {
                self.publishStatus("Exposure error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Resolution & FPS Control (Alterar Qualidade)

    func setResolutionPreset(_ preset: AVCaptureSession.Preset) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isRecording else {
                self.publishStatus("Cannot change quality while recording.")
                return
            }
            self.session.beginConfiguration()
            if self.session.canSetSessionPreset(preset) {
                self.session.sessionPreset = preset
                let label: String
                switch preset {
                case .hd4K3840x2160: label = "4K UHD"
                case .hd1920x1080: label = "1080p FHD"
                case .hd1280x720: label = "720p HD"
                default: label = "High"
                }
                DispatchQueue.main.async {
                    self.sessionPreset = preset
                    self.activeResolutionLabel = label
                    self.statusMessage = "Qualidade: \(label)"
                    self.autoClearStatusBanner()
                }
            }
            self.session.commitConfiguration()
        }
    }

    func setFrameRate(_ fps: Int32) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            self.configureCameraHardwareDefaults(device, fps: fps)
            DispatchQueue.main.async {
                self.activeFPS = fps
                self.statusMessage = "Taxa de quadros: \(fps) FPS"
                self.autoClearStatusBanner()
            }
        }
    }

    // MARK: - Cinema Mode (24 FPS + Cinematic Stabilization)

    func enableCinemaMode(_ enabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            let targetFPS: Int32 = enabled ? 24 : 30
            self.configureCameraHardwareDefaults(device, fps: targetFPS)

            if let connection = self.videoDataOutput.connection(with: .video),
               connection.isVideoStabilizationSupported {
                if enabled {
                    if #available(iOS 13.0, *) {
                        connection.preferredVideoStabilizationMode = .cinematicExtended
                    } else {
                        connection.preferredVideoStabilizationMode = .cinematic
                    }
                } else {
                    connection.preferredVideoStabilizationMode = .standard
                }
            }

            DispatchQueue.main.async {
                self.activeFPS = targetFPS
                self.statusMessage = enabled ? "Modo Cinema Ativo (24 FPS)" : "Modo Vídeo (30 FPS)"
                self.autoClearStatusBanner()
            }
        }
    }

    // MARK: - Camera Switching (Front / Back)

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isRecording else {
                self.publishStatus("Cannot flip camera while recording.")
                return
            }

            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }

            if let currentInput = self.session.inputs.first(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true }) {
                self.session.removeInput(currentInput)
            }

            let newPosition: AVCaptureDevice.Position = self.isFrontCamera ? .back : .front
            let newDevice: AVCaptureDevice?
            if newPosition == .front {
                newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            } else {
                let discovery = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
                    mediaType: .video,
                    position: .back
                )
                newDevice = discovery.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            }

            guard let device = newDevice, let newInput = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(newInput) else {
                self.publishStatus("Failed to switch camera.")
                return
            }

            self.session.addInput(newInput)
            self.videoDevice = device
            self.configureCameraHardwareDefaults(device, fps: self.activeFPS)

            let isFront = (newPosition == .front)
            let isVirtual = (device.deviceType == .builtInTripleCamera || device.deviceType == .builtInDualWideCamera)
            let switchFactors = device.virtualDeviceSwitchOverVideoZoomFactors
            let baseMult: CGFloat = (isVirtual && !switchFactors.isEmpty) ? CGFloat(switchFactors[0].doubleValue) : (isVirtual ? 2.0 : 1.0)
            self.wideBaseZoomMultiplier = baseMult

            DispatchQueue.main.async {
                self.isFrontCamera = isFront
                self.minZoomFactor = (isFront || !isVirtual) ? 1.0 : 0.5
                self.maxZoomFactor = isFront ? 3.0 : 10.0
                self.zoomFactor = 1.0
                self.isTorchAvailable = device.hasTorch && device.isTorchAvailable
                self.minExposureBias = device.minExposureTargetBias
                self.maxExposureBias = device.maxExposureTargetBias
                self.currentExposureBias = 0.0
            }
        }
    }

    // MARK: - Flash / Torch Control

    func toggleTorch() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                let targetMode: AVCaptureDevice.TorchMode = (device.torchMode == .on) ? .off : .on
                if device.isTorchModeSupported(targetMode) {
                    device.torchMode = targetMode
                    let isOn = (targetMode == .on)
                    DispatchQueue.main.async {
                        self.isTorchOn = isOn
                    }
                }
                device.unlockForConfiguration()
            } catch {
                self.publishStatus("Torch error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Photo Capture (Foto Rápida e Modo FOTO)

    func capturePhoto() {
        guard session.isRunning else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let photoSettings = AVCapturePhotoSettings()
            if #available(iOS 16.0, *) {
                photoSettings.maxPhotoDimensions = CMVideoDimensions(width: 3840, height: 2160)
            }
            if let device = self.videoDevice, device.hasFlash && device.isFlashAvailable {
                photoSettings.flashMode = self.isTorchOn ? .on : .auto
            }
            self.photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }

    // MARK: - Gallery Thumbnail & Photos Access

    func fetchLatestPhotoThumbnail() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            guard status == .authorized || status == .limited else { return }
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 1
            let assets = PHAsset.fetchAssets(with: fetchOptions)
            guard let latestAsset = assets.firstObject else { return }

            let imageManager = PHImageManager.default()
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = false
            requestOptions.deliveryMode = .highQualityFormat

            imageManager.requestImage(
                for: latestAsset,
                targetSize: CGSize(width: 140, height: 140),
                contentMode: .aspectFill,
                options: requestOptions
            ) { image, _ in
                if let image {
                    DispatchQueue.main.async {
                        self?.latestThumbnail = image
                    }
                }
            }
        }
    }

    func openPhotosApp() {
        if let url = URL(string: "photos-redirect://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
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
                self.cleanupTempFiles(urls)

                DispatchQueue.main.async {
                    self.isSaving = false
                    if success {
                        self.statusMessage = "Vídeos 16:9 & 9:16 salvos no Fotos"
                        self.autoClearStatusBanner()
                        self.fetchLatestPhotoThumbnail()
                    } else {
                        self.statusMessage = "Erro ao salvar: \(error?.localizedDescription ?? "Desconhecido")"
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

            let targetFPS: Int32 = (state == .serious || state == .critical) ? 24 : 30
            self.sessionQueue.async {
                if let device = self.videoDevice {
                    self.configureCameraHardwareDefaults(device, fps: targetFPS)
                }
            }
        }
    }

    // MARK: - Crop Geometry Helpers

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
            guard let self, self.statusMessage != nil else { return }
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

        let horizontalCropRect = Self.centeredEvenCropRect(in: frameSize, targetAspect: 16.0 / 9.0)
        let verticalCropRect = Self.centeredEvenCropRect(in: frameSize, targetAspect: 9.0 / 16.0)

        let sourceCIImage = CIImage(cvPixelBuffer: pixelBuffer, options: [.colorSpace: NSNull()])

        vWriter.appendVideo(
            sourceBuffer: pixelBuffer,
            sourceImage: sourceCIImage,
            cropRect: verticalCropRect,
            presentationTime: presentationTime,
            ciContext: ciContext,
            allowZeroCopyPassthrough: false
        )

        hWriter.appendVideo(
            sourceBuffer: pixelBuffer,
            sourceImage: sourceCIImage,
            cropRect: horizontalCropRect,
            presentationTime: presentationTime,
            ciContext: ciContext,
            allowZeroCopyPassthrough: true
        )

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
        guard let hWriter = horizontalWriter,
              let vWriter = verticalWriter,
              hWriter.isSessionStarted,
              vWriter.isSessionStarted else { return }

        hWriter.appendAudio(sampleBuffer)
        vWriter.appendAudio(sampleBuffer)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate (Photo Capture)

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            publishStatus("Photo error: \(error.localizedDescription)")
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let originalImage = UIImage(data: data) else {
            publishStatus("Failed to decode photo.")
            return
        }

        let cropped16x9 = cropImageToAspect(originalImage, targetAspect: 16.0 / 9.0)
        let cropped9x16 = cropImageToAspect(originalImage, targetAspect: 9.0 / 16.0)

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self else { return }
            guard status == .authorized || status == .limited else {
                self.publishStatus(CameraError.photoLibraryDenied.localizedDescription)
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: cropped16x9)
                PHAssetChangeRequest.creationRequestForAsset(from: cropped9x16)
            }, completionHandler: { success, err in
                DispatchQueue.main.async {
                    if success {
                        self.latestThumbnail = cropped9x16
                        self.statusMessage = "Foto salva (16:9 e 9:16)"
                        self.autoClearStatusBanner()
                    } else if let err {
                        self.statusMessage = "Erro ao salvar foto: \(err.localizedDescription)"
                    }
                }
            })
        }
    }

    private func cropImageToAspect(_ image: UIImage, targetAspect: CGFloat) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let rect = Self.centeredEvenCropRect(in: CGSize(width: width, height: height), targetAspect: targetAspect)
        guard let croppedCg = cgImage.cropping(to: rect) else { return image }
        return UIImage(cgImage: croppedCg, scale: image.scale, orientation: image.imageOrientation)
    }
}
