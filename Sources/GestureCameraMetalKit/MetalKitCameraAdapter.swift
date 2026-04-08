import MetalKit
import QuartzCore
import GestureCamera

/// Drives a GestureCameraController from a CADisplayLink and delivers the
/// current CameraTransform to your Metal render pass each frame.
///
/// Usage:
/// ```swift
/// let adapter = MetalKitCameraAdapter(controller: controller, view: mtkView)
///
/// adapter.onDraw = { [weak self] view, transform in
///     guard let self,
///           let drawable  = view.currentDrawable,
///           let rpd       = view.currentRenderPassDescriptor else { return }
///     // fill in your per-frame uniforms using transform.viewMatrix
///     let uniforms = FrameUniforms(
///         viewMatrix:       transform.viewMatrix,
///         projectionMatrix: self.projectionMatrix(for: view)
///     )
///     // ... encode your render commands ...
/// }
///
/// adapter.start()
/// ```
@MainActor
public final class MetalKitCameraAdapter {

    private let controller: GestureCameraController
    private weak var view: MTKView?
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    /// Called each frame on the main thread after `controller.update(deltaTime:)`.
    /// Build and commit your MTLCommandBuffer here.
    public var onDraw: ((MTKView, CameraTransform) -> Void)?

    public init(controller: GestureCameraController, view: MTKView) {
        self.controller = controller
        self.view = view
        // We own the loop; tell MTKView not to drive its own display link.
        view.isPaused = true
        view.enableSetNeedsDisplay = false
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
        let dt  = lastTimestamp == 0 ? 0 : Float(now - lastTimestamp)
        lastTimestamp = now

        controller.update(deltaTime: dt)

        guard let view else { return }
        onDraw?(view, controller.transform)
    }
}
