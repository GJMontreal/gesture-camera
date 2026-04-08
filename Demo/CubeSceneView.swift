import SwiftUI
import SceneKit
import GestureCamera
import GestureCameraSceneKit

/// UIViewRepresentable that renders a SceneKit scene with a single lit cube.
/// The camera is driven by a GestureCameraController.
struct CubeSceneView: UIViewRepresentable {

    let controller: GestureCameraController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = Self.makeScene()
        scnView.backgroundColor = UIColor(white: 0.08, alpha: 1)
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = false

        // Wire up camera node
        let cameraNode = context.coordinator.cameraNode
        scnView.scene?.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode

        // Start the display-link adapter
        context.coordinator.adapter = SceneKitCameraAdapter(
            controller: controller,
            cameraNode: cameraNode
        )
        context.coordinator.adapter?.start()

        // Pan gesture → translate camera
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        scnView.addGestureRecognizer(pan)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    // MARK: - Scene construction

    private static func makeScene() -> SCNScene {
        let scene = SCNScene()

        // Cube
        let box = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.06)
        box.firstMaterial?.diffuse.contents  = UIColor.systemBlue
        box.firstMaterial?.specular.contents = UIColor.white
        box.firstMaterial?.shininess = 50
        scene.rootNode.addChildNode(SCNNode(geometry: box))

        // Floor grid (large plane, checkerboard texture)
        let plane = SCNPlane(width: 100, height: 100)
        let checker = checkerboardImage(size: 128, tileCount: 4)
        plane.firstMaterial?.diffuse.contents = checker
        plane.firstMaterial?.diffuse.wrapS = .repeat
        plane.firstMaterial?.diffuse.wrapT = .repeat
        plane.firstMaterial?.isDoubleSided = true
        let floorNode = SCNNode(geometry: plane)
        floorNode.simdPosition = SIMD3<Float>(0, -0.5, 0)
        floorNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        scene.rootNode.addChildNode(floorNode)

        // Ambient light
        let ambient = SCNLight()
        ambient.type  = .ambient
        ambient.color = UIColor(white: 0.3, alpha: 1)
        let ambientNode = SCNNode(); ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Directional light
        let sun = SCNLight()
        sun.type  = .directional
        sun.color = UIColor(white: 0.9, alpha: 1)
        sun.castsShadow = true
        let sunNode = SCNNode(); sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
        scene.rootNode.addChildNode(sunNode)

        return scene
    }

    /// Programmatically draw a simple grey checkerboard texture.
    private static func checkerboardImage(size: Int, tileCount: Int) -> UIImage {
        let tileSize = size / tileCount
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { ctx in
            for row in 0..<tileCount {
                for col in 0..<tileCount {
                    let isLight = (row + col) % 2 == 0
                    ctx.cgContext.setFillColor(
                        UIColor(white: isLight ? 0.45 : 0.3, alpha: 1).cgColor
                    )
                    ctx.cgContext.fill(CGRect(
                        x: col * tileSize, y: row * tileSize,
                        width: tileSize, height: tileSize
                    ))
                }
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        let controller: GestureCameraController
        let cameraNode: SCNNode
        var adapter: SceneKitCameraAdapter?

        init(controller: GestureCameraController) {
            self.controller = controller

            let node = SCNNode()
            let camera = SCNCamera()
            camera.zNear = 0.05
            camera.zFar  = 200
            camera.fieldOfView = 60
            node.camera = camera
            self.cameraNode = node
        }

        @MainActor
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .changed else { return }
            let delta = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            controller.applyRotationGesture(
                dx: Float(delta.x),
                dy: Float(delta.y)
            )
        }
    }
}
