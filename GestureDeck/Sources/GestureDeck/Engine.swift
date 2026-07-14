import AVFoundation
import Vision

/// Watches the webcam with Apple's Vision hand-pose model (on-device, no
/// network) and emits debounced gestures: a pose fires once it has been
/// stable for `holdFrames`; changing to a different pose re-arms instantly,
/// and dropping the hands re-arms the same pose.
final class GestureEngine: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var statusText = "camera off"
    @Published var isWatching = false

    let session = AVCaptureSession()
    var holdFrames = 3
    var releaseFrames = 4
    var onGesture: ((Gesture) -> Void)?
    var onPose: ((String?) -> Void)?

    private let sessionQueue = DispatchQueue(label: "gd.session")
    private let videoQueue = DispatchQueue(label: "gd.video")
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()
    private var configured = false
    private var current: Gesture?
    private var hold = 0
    private var idle = 0
    private var lastFiredPose: Gesture?
    private var lastLabel: String?

    // ── lifecycle ────────────────────────────────────────────────────────

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.startSession() }
                    else { self?.statusText = "camera access denied" }
                }
            }
        default:
            statusText = "camera denied — System Settings → Privacy & Security → Camera"
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
            DispatchQueue.main.async {
                self.statusText = "paused"
                self.isWatching = false
                self.onPose?(nil)
            }
        }
    }

    private func startSession() {
        sessionQueue.async { [self] in
            if !configured {
                session.beginConfiguration()
                session.sessionPreset = .vga640x480
                guard let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device),
                      session.canAddInput(input) else {
                    session.commitConfiguration()
                    DispatchQueue.main.async { self.statusText = "no camera found" }
                    return
                }
                session.addInput(input)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: videoQueue)
                if session.canAddOutput(output) { session.addOutput(output) }
                session.commitConfiguration()
                // 30 fps so gestures land instantly
                if (try? device.lockForConfiguration()) != nil {
                    device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
                    device.unlockForConfiguration()
                }
                configured = true
            }
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async {
                self.statusText = "watching"
                self.isWatching = true
            }
        }
    }

    // ── per-frame ────────────────────────────────────────────────────────

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)
        try? handler.perform([request])
        let poses = (request.results ?? []).prefix(2).compactMap { classify($0) }

        var gesture: Gesture?
        var label: String?
        if poses.count == 2 {
            gesture = Self.combo(poses[0], poses[1])
            label = gesture.map { "\($0.icon) \($0.title)" }
                ?? "\(poses[0].icon)\(poses[1].icon) no pair action"
        } else if let p = poses.first {
            gesture = p
            label = "\(p.icon) \(p.title)"
        }
        step(gesture, label: label)
    }

    private func step(_ g: Gesture?, label: String?) {
        if let g {
            idle = 0
            if g == current { hold += 1 } else { current = g; hold = 1 }
            // fire as soon as the pose is stable; switching to a NEW pose
            // re-arms instantly — no need to drop the hand in between
            if hold >= holdFrames && g != lastFiredPose {
                lastFiredPose = g
                DispatchQueue.main.async { self.onGesture?(g) }
            }
        } else {
            current = nil
            hold = 0
            idle += 1
            if idle >= releaseFrames { lastFiredPose = nil }
        }
        if label != lastLabel {
            lastLabel = label
            DispatchQueue.main.async { self.onPose?(label) }
        }
    }

    // ── classification ───────────────────────────────────────────────────
    // Vision landmarks are normalized with the y axis pointing UP.

    private func classify(_ obs: VNHumanHandPoseObservation) -> Gesture? {
        guard let pts = try? obs.recognizedPoints(.all) else { return nil }
        func pt(_ j: VNHumanHandPoseObservation.JointName) -> CGPoint? {
            guard let p = pts[j], p.confidence > 0.3 else { return nil }
            return p.location
        }
        func d(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

        guard let wrist = pt(.wrist), let thumbTip = pt(.thumbTip),
              let indexMCP = pt(.indexMCP), let middleMCP = pt(.middleMCP),
              let littleMCP = pt(.littleMCP) else { return nil }
        let palmWidth = d(indexMCP, littleMCP)
        guard palmWidth > 0.02 else { return nil }

        // finger extended = tip clearly farther from the wrist than its PIP
        let joints: [(tip: VNHumanHandPoseObservation.JointName,
                      pip: VNHumanHandPoseObservation.JointName)] =
            [(.indexTip, .indexPIP), (.middleTip, .middlePIP),
             (.ringTip, .ringPIP), (.littleTip, .littlePIP)]
        var extended = [Bool](repeating: false, count: 4)
        var tips = [CGPoint?](repeating: nil, count: 4)
        for (i, j) in joints.enumerated() {
            guard let tip = pt(j.tip), let pip = pt(j.pip) else { continue }
            tips[i] = tip
            extended[i] = d(tip, wrist) > d(pip, wrist) * 1.15
        }
        let thumbOut = d(thumbTip, littleMCP) > palmWidth * 1.4
        let upright = middleMCP.y > wrist.y

        // OK sign: thumb–index pinch with the other three fingers extended
        if let indexTip = tips[0], d(thumbTip, indexTip) < palmWidth * 0.4,
           extended[1], extended[2], extended[3] {
            return .okSign
        }

        if !extended.contains(true) {
            let knuckleTop = max(indexMCP.y, middleMCP.y, littleMCP.y)
            if thumbTip.y > knuckleTop + palmWidth * 0.4 { return .thumbsUp }
            return upright ? .fist : nil
        }

        guard upright else { return nil }   // ignore hands on the keyboard

        if extended == [false, false, false, true], thumbOut { return .callMe }
        if extended == [true, false, false, true] { return .rock }

        // plain counts require fingertips actually above the wrist
        let raised = zip(extended, tips)
            .filter { ext, tip in ext && (tip.map { $0.y > wrist.y } ?? false) }
            .count
        switch raised {
        case 4: return thumbOut ? .palm : .four
        case 3: return .three
        case 2: return .two
        case 1: return .one
        default: return nil
        }
    }

    static func combo(_ a: Gesture, _ b: Gesture) -> Gesture? {
        if a == b {
            switch a {
            case .palm: return .twoPalms
            case .fist: return .twoFists
            case .thumbsUp: return .twoThumbsUp
            default: return nil
            }
        }
        let pair: Set<Gesture> = [a, b]
        if pair == [.palm, .fist] { return .palmAndFist }
        return nil
    }
}
