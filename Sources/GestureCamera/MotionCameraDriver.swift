import CoreMotion
import UIKit

/// Wraps CMMotionManager and delivers two streams from a single CMDeviceMotion feed:
///   - **Attitude** deltas (yaw/pitch) relative to the reference captured at `start()`
///   - **Translation impulses** detected from linear acceleration on the forward and lateral axes
///
/// All callbacks fire on the main thread.
public final class MotionCameraDriver {

    public enum UnavailableReason { case hardwareNotPresent }

    // MARK: - Callbacks

    /// Attitude change relative to the reference captured at `start()`.
    /// (yaw, pitch) in radians. Not called before the reference is latched.
    public var onAttitudeUpdate: ((_ yaw: Double, _ pitch: Double) -> Void)?

    /// Fired when a translation impulse is detected on the forward or lateral axis.
    /// Each Int is -1, 0, or +1; non-zero means an impulse was detected in that direction.
    /// The controller accumulates these into its persistent axis states.
    public var onTranslationImpulse: ((_ forwardDelta: Int, _ lateralDelta: Int) -> Void)?

    /// Called once if the hardware is not available.
    public var onUnavailable: ((UnavailableReason) -> Void)?

    // MARK: - Tuning

    /// Acceleration magnitude (in g) that triggers an impulse. Default 0.4g.
    public var impulseThreshold: Double = 0.4

    /// How long after an impulse the axis is locked, giving the user time to
    /// return the phone to neutral without triggering a counter-impulse. Default 0.45s.
    public var impulseDeadTime: TimeInterval = 0.45

    // MARK: - State

    public private(set) var isActive: Bool = false

    // MARK: - Private

    private let motionManager = CMMotionManager()
    private var referenceAttitude: CMAttitude?

    // Per-axis edge-trigger state.
    // "above" tracks whether the last sample was over threshold, so we fire
    // only on the onset crossing, not on every sample while held above threshold.
    private var forwardAbove   = false
    private var lateralAbove   = false
    private var forwardReadyAt: TimeInterval = 0   // wall time when dead time expires
    private var lateralReadyAt: TimeInterval = 0

    // MARK: - Lifecycle

    public init() {}

    /// Begins device motion updates. Captures the first sample as the attitude
    /// reference so yaw/pitch deltas start from zero.
    public func start() {
        guard motionManager.isDeviceMotionAvailable else {
            onUnavailable?(.hardwareNotPresent)
            return
        }
        referenceAttitude = nil
        forwardAbove = false
        lateralAbove = false
        forwardReadyAt = 0
        lateralReadyAt = 0
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: .main
        ) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.process(motion)
        }
        isActive = true
    }

    public func stop() {
        motionManager.stopDeviceMotionUpdates()
        referenceAttitude = nil
        isActive = false
    }

    // MARK: - Private

    private func process(_ motion: CMDeviceMotion) {
        // --- Attitude ---
        if referenceAttitude == nil {
            referenceAttitude = motion.attitude.copy() as? CMAttitude
            return
        }
        let relative = motion.attitude.copy() as! CMAttitude
        relative.multiply(byInverseOf: referenceAttitude!)
        onAttitudeUpdate?(relative.yaw, relative.pitch)

        // --- Translation impulses ---
        // userAcceleration is in the device frame, gravity removed.
        // Forward (-Z) is consistent across all orientations: pushing the phone
        // away from the user always moves it along the phone's -Z axis.
        // The lateral axis changes with screen orientation since the phone has
        // been physically rotated.
        let accel = motion.userAcceleration
        let now   = motion.timestamp   // seconds since system boot, monotonic

        detectImpulse(
            value:     -accel.z,
            isAbove:   &forwardAbove,
            readyAt:   &forwardReadyAt,
            now:       now,
            onImpulse: { [weak self] delta in self?.onTranslationImpulse?(delta, 0) }
        )
        detectImpulse(
            value:     lateralAcceleration(accel),
            isAbove:   &lateralAbove,
            readyAt:   &lateralReadyAt,
            now:       now,
            onImpulse: { [weak self] delta in self?.onTranslationImpulse?(0, delta) }
        )
    }

    /// Returns the acceleration component that corresponds to screen-left/right,
    /// accounting for the current device orientation.
    private func lateralAcceleration(_ accel: CMAcceleration) -> Double {
        switch UIDevice.current.orientation {
        case .landscapeLeft:        return -accel.y
        case .landscapeRight:       return  accel.y
        case .portraitUpsideDown:   return -accel.x
        default:                    return  accel.x   // portrait
        }
    }

    /// Edge-triggered threshold detector with dead time.
    ///
    /// Fires `onImpulse(±1)` once per threshold crossing, then locks the axis
    /// for `impulseDeadTime` seconds so the return swing is ignored.
    private func detectImpulse(
        value:     Double,
        isAbove:   inout Bool,
        readyAt:   inout TimeInterval,
        now:       TimeInterval,
        onImpulse: (Int) -> Void
    ) {
        let magnitude = abs(value)

        if magnitude > impulseThreshold {
            // Rising edge: only fire once per crossing, and only outside dead time.
            if !isAbove && now >= readyAt {
                isAbove  = true
                readyAt  = now + impulseDeadTime
                onImpulse(value > 0 ? +1 : -1)
            }
        } else {
            // Falling edge: reset so the next crossing can trigger again.
            isAbove = false
        }
    }
}
