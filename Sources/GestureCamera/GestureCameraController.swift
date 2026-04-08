import Foundation
import simd

/// Manages camera position and orientation via three input channels:
///   - **Motion**: yaw and pitch from device attitude (no roll, ever)
///   - **Pan gesture**: translate along the camera's local X/Y plane
///   - **WASD**: continuous movement each `update(deltaTime:)` tick
///
/// Orientation is stored as separate scalar yaw and pitch values. The orientation
/// quaternion in `transform` is derived from these each frame, which makes roll
/// impossible regardless of input order or magnitude.
@MainActor
public final class GestureCameraController: ObservableObject {

    @Published public private(set) var transform: CameraTransform
    @Published public private(set) var isMotionEnabled: Bool = false

    /// Movement speed in world units per second.
    public var movementSpeed: Float = 3.0

    /// Smoothing time constant (seconds) for attitude changes.
    /// Higher = more dampening, more lag.
    public var attitudeSmoothingTime: Float = 0.04

    /// When true, `update(deltaTime:)` skips all position changes and clears
    /// any active movement state. Set this while UI overlays (settings, menus)
    /// are on screen so the camera doesn't drift.
    public var isPaused: Bool = false {
        didSet { if isPaused { clearMovementState() } }
    }

    /// When false, accelerometer step detection is disabled and the camera
    /// will not translate via physical movement. Orientation (yaw/pitch) is unaffected.
    @Published public var isMotionTranslationEnabled: Bool = true {
        didSet { if !isMotionTranslationEnabled { motionForwardAxis = 0; motionLateralAxis = 0; motionVerticalAxis = 0 } }
    }

    /// Inverts both yaw and pitch axes for touch rotation gestures.
    @Published public var invertTouchGestures: Bool = true

    /// Threshold for forward/backward step detection. Lower = more sensitive. Range 0.1 … 1.0.
    public var forwardImpulseThreshold: Double {
        get { motionDriver.forwardImpulseThreshold }
        set { motionDriver.forwardImpulseThreshold = newValue }
    }

    /// Threshold for left/right step detection. Lower = more sensitive. Range 0.1 … 1.0.
    public var lateralImpulseThreshold: Double {
        get { motionDriver.lateralImpulseThreshold }
        set { motionDriver.lateralImpulseThreshold = newValue }
    }

    /// Threshold for up/down impulse detection (world-vertical). Higher default avoids
    /// false triggers from walking bounce. Lower = more sensitive. Range 0.1 … 1.0.
    public var verticalImpulseThreshold: Double {
        get { motionDriver.verticalImpulseThreshold }
        set { motionDriver.verticalImpulseThreshold = newValue }
    }

    /// True while any WASD/arrow button is actively held.
    /// Use this to suppress auto-hide timers in your overlay UI.
    @Published public private(set) var isMoving: Bool = false

    /// Fired when an impulse is detected. Clears automatically after 0.3 s.
    @Published public private(set) var lastImpulse: ImpulseEvent?

    // MARK: - Private state

    private let motionDriver: MotionCameraDriver

    // Camera orientation as independent scalars — the only source of truth for rotation.
    // transform.orientation is rebuilt from these every frame.
    private var cameraYaw:   Float = 0   // radians, positive = look right
    private var cameraPitch: Float = 0   // radians, positive = look up, clamped ±85°

    // Motion baseline: orientation at the moment motion was enabled (or re-baselined).
    private var motionBaseYaw:   Float = 0
    private var motionBasePitch: Float = 0

    // Motion target: updated by the motion callback, smoothed toward in update().
    private var motionTargetYaw:   Float?
    private var motionTargetPitch: Float?

    // WASD held-key flags
    private var moveForward  = false
    private var moveBackward = false
    private var moveLeft     = false
    private var moveRight    = false
    private var moveUp       = false
    private var moveDown     = false

    // Motion impulse axis states: -1, 0, or +1
    private var motionForwardAxis:   Int = 0
    private var motionLateralAxis:   Int = 0
    private var motionVerticalAxis:  Int = 0

    // MARK: - Init

    public init(
        initialTransform: CameraTransform = .identity,
        motionDriver: MotionCameraDriver = MotionCameraDriver()
    ) {
        self.transform = initialTransform
        self.motionDriver = motionDriver

        // Extract initial yaw/pitch from the identity orientation.
        extractYawPitch(from: initialTransform.orientation)

        motionDriver.onAttitudeUpdate = { [weak self] yawDelta, pitchDelta in
            guard let self else { return }
            let targetYaw   = self.motionBaseYaw   + yawDelta
            let targetPitch = (self.motionBasePitch + pitchDelta).clamped(to: -.pi/2 + 0.05 ... .pi/2 - 0.05)
            self.motionTargetYaw   = targetYaw
            self.motionTargetPitch = targetPitch
        }

        // When interface orientation changes the driver re-latches its reference.
        // Update our motion base to the current camera values so the camera doesn't jump.
        motionDriver.onRebaseline = { [weak self] in
            guard let self else { return }
            self.motionBaseYaw   = self.cameraYaw
            self.motionBasePitch = self.cameraPitch
        }

        motionDriver.onTranslationImpulse = { [weak self] fwdDelta, latDelta, vertDelta in
            guard let self, self.isMotionTranslationEnabled else { return }
            self.applyTranslationImpulse(forwardDelta: fwdDelta, lateralDelta: latDelta, verticalDelta: vertDelta)
        }
    }

    // MARK: - Motion toggle

    public func toggleMotion() {
        if isMotionEnabled {
            motionDriver.stop()
            motionTargetYaw   = nil
            motionTargetPitch = nil
            motionForwardAxis  = 0
            motionLateralAxis  = 0
            motionVerticalAxis = 0
            isMotionEnabled    = false
        } else {
            motionBaseYaw   = cameraYaw
            motionBasePitch = cameraPitch
            motionTargetYaw   = nil
            motionTargetPitch = nil
            motionDriver.start()
            isMotionEnabled = true
        }
    }

    // MARK: - WASD input

    public enum MoveDirection {
        case forward, backward, left, right, up, down
    }

    public func setMoving(_ direction: MoveDirection, active: Bool) {
        switch direction {
        case .forward:  moveForward  = active
        case .backward: moveBackward = active
        case .left:     moveLeft     = active
        case .right:    moveRight    = active
        case .up:       moveUp       = active
        case .down:     moveDown     = active
        }
        isMoving = moveForward || moveBackward || moveLeft || moveRight || moveUp || moveDown
    }

    // MARK: - Touch rotation gesture

    /// Rotate the camera via a drag gesture (yaw and pitch only, never roll).
    /// Call from a UIPanGestureRecognizer with deltas zeroed each frame.
    public func applyRotationGesture(dx: Float, dy: Float, sensitivity: Float = 0.005) {
        let sign: Float = invertTouchGestures ? -1 : 1
        cameraYaw   -= dx * sensitivity * sign
        cameraPitch += dy * sensitivity * sign
        cameraPitch  = cameraPitch.clamped(to: -.pi/2 + 0.05 ... .pi/2 - 0.05)
    }

    // MARK: - Per-frame update

    /// Must be called every frame on the main thread.
    public func update(deltaTime dt: Float) {
        guard dt > 0 else { return }

        // --- Smooth orientation toward motion target ---
        if let ty = motionTargetYaw, let tp = motionTargetPitch {
            let alpha = 1 - exp(-dt / attitudeSmoothingTime)

            // Shortest-path yaw interpolation
            var yawDiff = ty - cameraYaw
            if yawDiff >  .pi { yawDiff -= 2 * .pi }
            if yawDiff < -.pi { yawDiff += 2 * .pi }
            cameraYaw   += yawDiff * alpha
            cameraPitch += (tp - cameraPitch) * alpha
        }

        // Rebuild orientation from yaw + pitch — roll is impossible this way.
        // forward = (sin(yaw)*cos(pitch), sin(pitch), -cos(yaw)*cos(pitch))
        transform.orientation =
            simd_quatf(angle: -cameraYaw,   axis: SIMD3<Float>(0, 1, 0)) *
            simd_quatf(angle:  cameraPitch, axis: SIMD3<Float>(1, 0, 0))

        // --- Position ---
        guard !isPaused else { return }

        // WASD and motion impulse always move along world-horizontal axes so that
        // looking up/down doesn't affect the movement direction.
        // Derive horizontal forward/right from yaw only (no pitch component).
        let hForward = SIMD3<Float>( sin(cameraYaw), 0, -cos(cameraYaw))
        let hRight   = SIMD3<Float>( cos(cameraYaw), 0,  sin(cameraYaw))

        var velocity = SIMD3<Float>.zero

        if moveForward  { velocity += hForward }
        if moveBackward { velocity -= hForward }
        if moveRight    { velocity += hRight }
        if moveLeft     { velocity -= hRight }
        if moveUp       { velocity.y += 1 }
        if moveDown     { velocity.y -= 1 }

        velocity += hForward               * Float(motionForwardAxis)
        velocity += hRight                 * Float(motionLateralAxis)
        velocity += SIMD3<Float>(0, 1, 0)  * Float(motionVerticalAxis)

        if simd_length_squared(velocity) > 0 {
            transform.position += simd_normalize(velocity) * movementSpeed * dt
        }
    }

    // MARK: - Private

    private func clearMovementState() {
        moveForward  = false; moveBackward = false
        moveLeft     = false; moveRight    = false
        moveUp       = false; moveDown     = false
        motionForwardAxis = 0; motionLateralAxis = 0; motionVerticalAxis = 0
        isMoving = false
    }

    private func extractYawPitch(from orientation: simd_quatf) {
        let fwd = orientation.act(SIMD3<Float>(0, 0, -1))
        cameraYaw   = atan2(fwd.x, -fwd.z)
        cameraPitch = asin(max(-1, min(1, fwd.y)))
    }

    private func applyTranslationImpulse(forwardDelta: Int, lateralDelta: Int, verticalDelta: Int) {
        if forwardDelta != 0 {
            motionForwardAxis = (motionForwardAxis + forwardDelta).clamped(to: -1...1)
            publishImpulse(ImpulseEvent(axis: forwardDelta > 0 ? .forward : .backward))
        }
        if lateralDelta != 0 {
            motionLateralAxis = (motionLateralAxis + lateralDelta).clamped(to: -1...1)
            publishImpulse(ImpulseEvent(axis: lateralDelta > 0 ? .right : .left))
        }
        if verticalDelta != 0 {
            motionVerticalAxis = (motionVerticalAxis + verticalDelta).clamped(to: -1...1)
            publishImpulse(ImpulseEvent(axis: verticalDelta > 0 ? .up : .down))
        }
    }

    private func publishImpulse(_ event: ImpulseEvent) {
        lastImpulse = event
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self?.lastImpulse = nil
        }
    }
}

// MARK: - ImpulseEvent

public struct ImpulseEvent: Equatable {
    public enum Axis { case forward, backward, left, right, up, down }
    public let axis: Axis
    public let id: UUID = UUID()

    public static func == (lhs: ImpulseEvent, rhs: ImpulseEvent) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Helpers

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
