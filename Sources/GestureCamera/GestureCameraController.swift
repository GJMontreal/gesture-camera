import Foundation
import simd

/// Manages camera position and orientation via three input channels:
///   - **Motion** (gyro/accelerometer): yaw/pitch from attitude, translation from impulses
///   - **Pan gesture**: translate along the camera's local X/Y plane
///   - **WASD**: continuous movement each `update(deltaTime:)` tick
///
/// All velocity (WASD and motion impulse) uses the same constant `movementSpeed`.
/// Motion translation is impulse-driven: each detected accelerometer event steps the
/// axis state by ±1 (clamped to [-1, +1]). A counter-impulse steps it back toward zero.
///
/// Consumers drive the per-frame tick by calling `update(deltaTime:)` from a
/// CADisplayLink or render loop on the main thread.
@MainActor
public final class GestureCameraController: ObservableObject {

    @Published public private(set) var transform: CameraTransform
    @Published public private(set) var isMotionEnabled: Bool = false

    /// Movement speed in world units per second. Applies to both WASD and motion impulse.
    public var movementSpeed: Float = 3.0

    /// Scales yaw and pitch from the motion driver. Negate to invert an axis.
    public var motionSensitivity: Float = 1.0

    // MARK: - Private state

    private let motionDriver: MotionCameraDriver

    /// Camera orientation at the moment motion was enabled.
    private var motionBaseOrientation: simd_quatf = .init(ix: 0, iy: 0, iz: 0, r: 1)
    private var motionYaw:   Float = 0
    private var motionPitch: Float = 0

    // WASD: held-key flags
    private var moveForward  = false
    private var moveBackward = false
    private var moveLeft     = false
    private var moveRight    = false
    private var moveUp       = false
    private var moveDown     = false

    // Motion translation axis states: -1, 0, or +1.
    // Set by impulse callbacks; persist until a counter-impulse steps them back.
    private var motionForwardAxis: Int = 0   // +1 = moving forward, -1 = backward
    private var motionLateralAxis: Int = 0   // +1 = moving right,   -1 = left

    // MARK: - Init

    public init(
        initialTransform: CameraTransform = .identity,
        motionDriver: MotionCameraDriver = MotionCameraDriver()
    ) {
        self.transform = initialTransform
        self.motionDriver = motionDriver

        motionDriver.onAttitudeUpdate = { [weak self] yaw, pitch in
            self?.applyMotionAttitude(yaw: Float(yaw), pitch: Float(pitch))
        }

        motionDriver.onTranslationImpulse = { [weak self] forwardDelta, lateralDelta in
            self?.applyTranslationImpulse(forwardDelta: forwardDelta, lateralDelta: lateralDelta)
        }
    }

    // MARK: - Motion toggle

    public func toggleMotion() {
        if isMotionEnabled {
            motionDriver.stop()
            motionForwardAxis = 0
            motionLateralAxis = 0
            isMotionEnabled = false
        } else {
            motionBaseOrientation = transform.orientation
            motionYaw   = 0
            motionPitch = 0
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
    }

    // MARK: - Pan gesture translation

    /// Translate the camera in its local X/Y plane.
    /// Uses "drag world" semantics: dragging right moves the world right (camera left).
    /// Call from a UIPanGestureRecognizer with point deltas zeroed each frame.
    public func applyTranslationGesture(dx: Float, dy: Float, sensitivity: Float = 0.01) {
        transform.position -= transform.right * (dx * sensitivity)
        transform.position += transform.up    * (dy * sensitivity)
    }

    // MARK: - Per-frame update

    /// Must be called every frame on the main thread.
    public func update(deltaTime dt: Float) {
        guard dt > 0 else { return }

        var velocity = SIMD3<Float>.zero

        // WASD (held keys) — camera-relative axes
        if moveForward  { velocity += transform.forward }
        if moveBackward { velocity -= transform.forward }
        if moveRight    { velocity += transform.right }
        if moveLeft     { velocity -= transform.right }
        if moveUp       { velocity.y += 1 }
        if moveDown     { velocity.y -= 1 }

        // Motion impulse — also camera-relative, same constant speed
        velocity += transform.forward * Float(motionForwardAxis)
        velocity += transform.right   * Float(motionLateralAxis)

        if simd_length_squared(velocity) > 0 {
            transform.position += simd_normalize(velocity) * movementSpeed * dt
        }
    }

    // MARK: - Private

    private func applyMotionAttitude(yaw: Float, pitch: Float) {
        motionYaw   = yaw   * motionSensitivity
        motionPitch = pitch * motionSensitivity
        let yawQ   = simd_quatf(angle: -motionYaw,  axis: SIMD3<Float>(0, 1, 0))
        let pitchQ = simd_quatf(angle: -motionPitch, axis: SIMD3<Float>(1, 0, 0))
        transform.orientation = simd_normalize(motionBaseOrientation * yawQ * pitchQ)
    }

    /// Steps axis states by the received deltas, clamped to [-1, +1].
    /// Because the constant-velocity model doesn't weight magnitude, each impulse
    /// is exactly one step: a counter-impulse from +1 lands at 0 (stop), not -1.
    private func applyTranslationImpulse(forwardDelta: Int, lateralDelta: Int) {
        if forwardDelta != 0 {
            motionForwardAxis = (motionForwardAxis + forwardDelta).clamped(to: -1...1)
        }
        if lateralDelta != 0 {
            motionLateralAxis = (motionLateralAxis + lateralDelta).clamped(to: -1...1)
        }
    }
}

// MARK: - Helpers

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
