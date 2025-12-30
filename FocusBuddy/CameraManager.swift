import AVFoundation
import Vision
import AppKit

class CameraManager: NSObject, ObservableObject {
    @Published var isFaceDetected = false
    @Published var isAuthorized = false
    @Published var errorMessage: String?
    @Published var headAngle: Double = 0.0
    @Published var isWaving = false  // User is waving at the robot!
    @Published var isShowingStop = false  // User shows "stop" palm gesture

    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let processingQueue = DispatchQueue(label: "face.detection.queue", qos: .userInteractive)

    private var lastFaceDetectionTime: Date = Date()
    private var isProcessingFrame = false

    // Wave detection
    private var wristPositions: [(x: CGFloat, time: Date)] = []
    private var lastWaveDetected: Date = .distantPast
    private let waveDebounce: TimeInterval = 5.0  // Don't detect wave again for 5 seconds

    // Stop gesture detection
    private var lastStopDetected: Date = .distantPast
    private let stopDebounce: TimeInterval = 3.0  // Don't detect stop again for 3 seconds

    override init() {
        super.init()
    }

    func requestAuthorization() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            DispatchQueue.main.async {
                self.isAuthorized = true
            }
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.startSession()
                    } else {
                        self?.errorMessage = "Camera access required"
                        self?.showDeniedAlert()
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.errorMessage = "No camera access"
                self.showDeniedAlert()
            }
        @unknown default:
            DispatchQueue.main.async {
                self.errorMessage = "Camera error"
            }
        }
    }

    private func showDeniedAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "No Camera Access"
            alert.informativeText = "To use FocusBuddy, please allow camera access:\n\nSystem Settings → Privacy & Security → Camera → FocusBuddy"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")

            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            self?.setupCaptureSession()
        }
    }

    private func setupCaptureSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .medium

        var camera: AVCaptureDevice?
        camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)

        if camera == nil {
            camera = AVCaptureDevice.default(for: .video)
        }

        guard let camera = camera else {
            DispatchQueue.main.async {
                self.errorMessage = "No camera found"
            }
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)

            if session.canAddInput(input) {
                session.addInput(input)
            }

            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: processingQueue)
            output.alwaysDiscardsLateVideoFrames = true

            if session.canAddOutput(output) {
                session.addOutput(output)
            }

            self.captureSession = session
            self.videoOutput = output

            session.startRunning()

            DispatchQueue.main.async {
                self.isAuthorized = true
            }

        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }

    func timeSinceLastFace() -> TimeInterval {
        return Date().timeIntervalSince(lastFaceDetectionTime)
    }
}

// MARK: - Video Output Delegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        // Skip if already processing a frame
        guard !isProcessingFrame else { return }
        isProcessingFrame = true

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            isProcessingFrame = false
            return
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        // Face detection request
        let faceRequest = VNDetectFaceLandmarksRequest()

        // Hand pose detection request
        let handRequest = VNDetectHumanHandPoseRequest()
        handRequest.maximumHandCount = 1

        do {
            try handler.perform([faceRequest, handRequest])

            // Process face
            if let faceObservations = faceRequest.results, !faceObservations.isEmpty,
               let face = faceObservations.first {
                let (isLooking, angle) = analyzeFace(face: face)

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if isLooking {
                        self.lastFaceDetectionTime = Date()
                    }
                    self.isFaceDetected = isLooking
                    self.headAngle = angle
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.isFaceDetected = false
                }
            }

            // Process hand for gesture detection
            if let handObservations = handRequest.results, !handObservations.isEmpty,
               let hand = handObservations.first {
                detectWave(hand: hand)
                detectStopGesture(hand: hand)
            }

        } catch {
            // Silently handle errors
        }

        isProcessingFrame = false
    }

    // MARK: - Wave Detection

    private func detectWave(hand: VNHumanHandPoseObservation) {
        // Don't detect if we just detected a wave
        guard Date().timeIntervalSince(lastWaveDetected) > waveDebounce else { return }

        do {
            // Get wrist position
            let wrist = try hand.recognizedPoint(.wrist)

            // Only track if confidence is high enough
            guard wrist.confidence > 0.7 else { return }

            let now = Date()

            // Add current position
            wristPositions.append((x: wrist.location.x, time: now))

            // Remove old positions (keep last 1 second)
            wristPositions = wristPositions.filter { now.timeIntervalSince($0.time) < 1.0 }

            // Need at least 5 positions to detect wave
            guard wristPositions.count >= 5 else { return }

            // Analyze for wave pattern (left-right-left or right-left-right)
            let isWaving = detectWavePattern()

            if isWaving {
                lastWaveDetected = now
                wristPositions.removeAll()

                DispatchQueue.main.async { [weak self] in
                    self?.isWaving = true

                    // Reset after animation time
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self?.isWaving = false
                    }
                }
            }

        } catch {
            // Hand point not available
        }
    }

    private func detectWavePattern() -> Bool {
        guard wristPositions.count >= 5 else { return false }

        // Calculate direction changes
        var directionChanges = 0
        var lastDirection: Int = 0  // -1 = left, 1 = right, 0 = none

        for i in 1..<wristPositions.count {
            let dx = wristPositions[i].x - wristPositions[i-1].x

            // Ignore small movements (need significant horizontal motion)
            guard abs(dx) > 0.06 else { continue }

            let direction = dx > 0 ? 1 : -1

            if lastDirection != 0 && direction != lastDirection {
                directionChanges += 1
            }

            lastDirection = direction
        }

        // Wave = at least 3 direction changes (need clear back-and-forth motion)
        return directionChanges >= 3
    }

    // MARK: - Peace Sign Detection ✌️ (for break toggle)

    private func detectStopGesture(hand: VNHumanHandPoseObservation) {
        // Don't detect if we just detected peace sign
        guard Date().timeIntervalSince(lastStopDetected) > stopDebounce else { return }

        do {
            // Get all finger tips
            let indexTip = try hand.recognizedPoint(.indexTip)
            let middleTip = try hand.recognizedPoint(.middleTip)
            let ringTip = try hand.recognizedPoint(.ringTip)
            let littleTip = try hand.recognizedPoint(.littleTip)

            // Get finger base points (MCP joints)
            let indexMCP = try hand.recognizedPoint(.indexMCP)
            let middleMCP = try hand.recognizedPoint(.middleMCP)
            let ringMCP = try hand.recognizedPoint(.ringMCP)
            let littleMCP = try hand.recognizedPoint(.littleMCP)

            // Check confidence
            let allPoints = [indexTip, middleTip, ringTip, littleTip, indexMCP, middleMCP, ringMCP, littleMCP]
            guard allPoints.allSatisfy({ $0.confidence > 0.5 }) else { return }

            // Peace sign = index and middle fingers extended, ring and little curled
            let indexExtended = indexTip.location.y > indexMCP.location.y + 0.06
            let middleExtended = middleTip.location.y > middleMCP.location.y + 0.06
            let ringCurled = ringTip.location.y < ringMCP.location.y + 0.03
            let littleCurled = littleTip.location.y < littleMCP.location.y + 0.03

            // Index and middle should be spread apart (V shape)
            let fingersSpread = abs(indexTip.location.x - middleTip.location.x) > 0.04

            // Both extended fingers should be at similar height
            let similarHeight = abs(indexTip.location.y - middleTip.location.y) < 0.08

            let isPeaceSign = indexExtended && middleExtended && ringCurled && littleCurled && fingersSpread && similarHeight

            if isPeaceSign {
                lastStopDetected = Date()

                DispatchQueue.main.async { [weak self] in
                    self?.isShowingStop = true

                    // Reset after short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self?.isShowingStop = false
                    }
                }
            }

        } catch {
            // Hand points not available
        }
    }

    // MARK: - Face Analysis

    private func analyzeFace(face: VNFaceObservation) -> (Bool, Double) {
        var totalAngle: Double = 0

        // Check yaw (left/right rotation)
        if let yaw = face.yaw?.doubleValue {
            totalAngle += abs(yaw)
            if abs(yaw) > 0.5 { // ~30 degrees
                return (false, totalAngle)
            }
        }

        // Check pitch (up/down)
        if let pitch = face.pitch?.doubleValue {
            totalAngle += abs(pitch)
            if abs(pitch) > 0.5 {
                return (false, totalAngle)
            }
        }

        // Check roll (head tilt)
        if let roll = face.roll?.doubleValue {
            totalAngle += abs(roll) * 0.5
            if abs(roll) > 0.7 { // ~40 degrees
                return (false, totalAngle)
            }
        }

        // Check eye landmarks
        if let landmarks = face.landmarks {
            if landmarks.leftEye == nil && landmarks.rightEye == nil {
                return (false, totalAngle)
            }
        }

        return (true, totalAngle)
    }
}
