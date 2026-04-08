import CoreMotion
import UIKit

/// Wraps CMMotionManager and delivers two streams from a single CMDeviceMotion feed:
///   - **Attitude deltas** (yawDelta, pitchDelta) in radians, relative to the reference
///     captured at `start()`. Both values are orientation-independent: yaw comes from
///     `attitude.yaw` (world-frame compass heading) and pitch from `asin(-R.m33)`
///     (screen-normal elevation angle). Neither depends on how the phone is held.
///   - **Translation impulses** detected from linear acceleration.
///
/// When the interface orientation changes (portrait ↔ landscape), `attitude.yaw` shifts
/// ~90° even though the physical look direction hasn't changed. `onRebaseline` fires so
/// the controller can absorb the jump without moving the camera.
///
/// All callbacks fire on the main thread.
public final class MotionCameraDriver {

    public enum UnavailableReason { case hardwareNotPresent }

    // MARK: - Callbacks

    /// Yaw and pitch deltas in radians relative to the reference captured at `start()`.
    /// Signs: positive yawDelta = phone turned right; positive pitchDelta = phone tilted up.
    public var onAttitudeUpdate: ((_ yawDelta: Float, _ pitchDelta: Float) -> Void)?

    /// Fired when interface orientation changes (portrait ↔ landscape).
    /// attitude.yaw shifts ~90° at each transition; the driver re-latches its reference
    /// so subsequent deltas are correct. The controller should update its own base
    /// yaw/pitch to the current camera values so the camera doesn't jump.
    public var onRebaseline: (() -> Void)?

    /// Fired when a translation impulse is detected.
    public var onTranslationImpulse: ((_ forwardDelta: Int, _ lateralDelta: Int) -> Void)?

    public var onUnavailable: ((UnavailableReason) -> Void)?

    // MARK: - Tuning

    public var impulseThreshold: Double = 0.4
    public var impulseDeadTime: TimeInterval = 0.45

    // MARK: - State

    public private(set) var isActive: Bool = false

    // MARK: - Private

    private let motionManager = CMMotionManager()
    private var referenceYaw:       Float = 0
    private var referenceElevation: Float = 0
    private var referenceSet = false
    private var lastInterfaceOrientation: UIInterfaceOrientation = .unknown

    private var forwardAbove   = false
    private var lateralAbove   = false
    private var forwardReadyAt: TimeInterval = 0
    private var lateralReadyAt: TimeInterval = 0

    // MARK: - Lifecycle

    public init() {}

    public func start() {
        guard motionManager.isDeviceMotionAvailable else {
            onUnavailable?(.hardwareNotPresent)
            return
        }
        referenceSet             = false
        lastInterfaceOrientation = currentInterfaceOrientation
        forwardAbove  = false
        lateralAbove  = false
        forwardReadyAt = 0
        lateralReadyAt = 0
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.process(motion)
        }
        isActive = true
    }

    public func stop() {
        motionManager.stopDeviceMotionUpdates()
        referenceSet = false
        isActive     = false
    }

    // MARK: - Private

    private var currentInterfaceOrientation: UIInterfaceOrientation {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation ?? .portrait
    }

    private func process(_ motion: CMDeviceMotion) {
        let R = motion.attitude.rotationMatrix

        // attitude.yaw  = world-frame heading (Z-up reference, orientation-independent)
        // asin(-R.m33)  = elevation of the screen normal; immune to compass yaw
        let currentYaw       = Float(motion.attitude.yaw)
        let currentElevation = asin(max(-1, min(1, -Float(R.m33))))

        // Re-baseline on interface orientation change. attitude.yaw jumps ~90° at each
        // portrait↔landscape transition even though the phone hasn't moved relative to
        // the user's body. Absorb the jump by treating current attitude as the new reference.
        let orientation = currentInterfaceOrientation
        if referenceSet && orientation != lastInterfaceOrientation {
            referenceYaw       = currentYaw
            referenceElevation = currentElevation
            onRebaseline?()
        }
        lastInterfaceOrientation = orientation

        if !referenceSet {
            referenceYaw       = currentYaw
            referenceElevation = currentElevation
            referenceSet       = true
            return
        }

        var deltaYaw = currentYaw - referenceYaw
        if deltaYaw >  .pi { deltaYaw -= 2 * .pi }
        if deltaYaw < -.pi { deltaYaw += 2 * .pi }

        let deltaPitch = currentElevation - referenceElevation

        // Negate yaw: CMAttitude yaw increases CCW (left turn), camera yaw convention
        // is positive = right turn.
        onAttitudeUpdate?(-deltaYaw, deltaPitch)

        // --- Translation impulses ---
        let accel = motion.userAcceleration
        let now   = motion.timestamp

        detectImpulse(
            value:     accel.z,
            isAbove:   &forwardAbove,
            readyAt:   &forwardReadyAt,
            now:       now,
            onImpulse: { [weak self] delta in self?.onTranslationImpulse?(delta, 0) }
        )
        detectImpulse(
            value:     -lateralAcceleration(accel),
            isAbove:   &lateralAbove,
            readyAt:   &lateralReadyAt,
            now:       now,
            onImpulse: { [weak self] delta in self?.onTranslationImpulse?(0, delta) }
        )
    }

    private func lateralAcceleration(_ accel: CMAcceleration) -> Double {
        switch UIDevice.current.orientation {
        case .landscapeLeft:      return -accel.y
        case .landscapeRight:     return  accel.y
        case .portraitUpsideDown: return -accel.x
        default:                  return  accel.x
        }
    }

    private func detectImpulse(
        value:     Double,
        isAbove:   inout Bool,
        readyAt:   inout TimeInterval,
        now:       TimeInterval,
        onImpulse: (Int) -> Void
    ) {
        let magnitude = abs(value)
        if magnitude > impulseThreshold {
            if !isAbove && now >= readyAt {
                isAbove = true
                readyAt = now + impulseDeadTime
                onImpulse(value > 0 ? +1 : -1)
            }
        } else {
            isAbove = false
        }
    }
}
