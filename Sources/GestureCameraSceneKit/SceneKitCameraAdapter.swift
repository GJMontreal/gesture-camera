import SceneKit
import QuartzCore
import GestureCamera

/// Drives an SCNNode from a GestureCameraController using a CADisplayLink.
///
/// Usage:
/// ```swift
/// let adapter = SceneKitCameraAdapter(controller: controller, cameraNode: node)
/// adapter.start()
/// ```
/// The adapter retains itself while active; call `stop()` to tear down.
@MainActor
public final class SceneKitCameraAdapter {

    private let controller: GestureCameraController
    private weak var cameraNode: SCNNode?

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    public init(controller: GestureCameraController, cameraNode: SCNNode) {
        self.controller = controller
        self.cameraNode = cameraNode
    }

    public func start() {
        guard displayLink == nil else { return }
        lastTimestamp = 0
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTimestamp == 0 ? 0 : Float(now - lastTimestamp)
        lastTimestamp = now

        controller.update(deltaTime: dt)

        let t = controller.transform
        cameraNode?.simdPosition    = t.position
        cameraNode?.simdOrientation = t.orientation
    }
}
