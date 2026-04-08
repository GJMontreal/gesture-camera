# GestureCamera

An iOS Swift package that drives a 3D camera using device motion (gyroscope + accelerometer) and touch gestures. No roll, ever.

**Requires iOS 16+ · Swift 5.9+**

---

## What it does

| Input | Effect |
|---|---|
| Rotate phone (yaw/pitch) | Look around — orientation-independent, works in portrait and landscape |
| Pan gesture on the 3D view | Look around via touch drag |
| Step forward / back | Camera moves forward / back |
| Step left / right | Camera strafes |
| Raise / lower phone | Camera moves up / down |
| WASD arrows on screen | Continuous movement in any direction |

Translation uses edge-triggered impulse detection: each detected step toggles movement on, the counter-motion (returning to neutral) toggles it off. Sensitivity is independently tunable per axis.

---

## Installation

In Xcode: **File → Add Package Dependencies**, enter the repository URL, then add whichever products your target needs.

In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/GJMontreal/gesture-camera", from: "1.0.0"),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "GestureCamera",          package: "gesture-camera"),
            .product(name: "GestureCameraSceneKit",  package: "gesture-camera"), // if using SceneKit
            .product(name: "GestureCameraMetalKit",  package: "gesture-camera"), // if using Metal
        ]
    )
]
```

---

## Info.plist

Motion requires a usage description. Add this key to your `Info.plist`:

```xml
<key>NSMotionUsageDescription</key>
<string>Motion sensors power gesture-based camera control.</string>
```

---

## SceneKit integration

```swift
import SwiftUI
import SceneKit
import GestureCamera
import GestureCameraSceneKit

struct ContentView: View {
    @StateObject private var controller = GestureCameraController()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            SceneView(controller: controller)
                .ignoresSafeArea()
            WASDOverlayView(controller: controller)
        }
        .sheet(isPresented: $showSettings) {
            CameraSettingsView(controller: controller)
        }
        .onChange(of: showSettings) { isShowing in
            controller.isPaused = isShowing
        }
    }
}

struct SceneView: UIViewRepresentable {
    let controller: GestureCameraController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = makeScene()
        scnView.allowsCameraControl = false

        let cameraNode = context.coordinator.cameraNode
        scnView.scene?.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode

        context.coordinator.adapter = SceneKitCameraAdapter(
            controller: controller,
            cameraNode: cameraNode
        )
        context.coordinator.adapter?.start()

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        scnView.addGestureRecognizer(pan)
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    final class Coordinator: NSObject {
        let controller: GestureCameraController
        let cameraNode: SCNNode
        var adapter: SceneKitCameraAdapter?

        init(controller: GestureCameraController) {
            self.controller = controller
            let node = SCNNode()
            node.camera = SCNCamera()
            self.cameraNode = node
        }

        @MainActor
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .changed else { return }
            let delta = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            controller.applyRotationGesture(dx: Float(delta.x), dy: Float(delta.y))
        }
    }

    private func makeScene() -> SCNScene {
        // build your scene here
        SCNScene()
    }
}
```

`SceneKitCameraAdapter` owns a `CADisplayLink` that calls `controller.update(deltaTime:)` and syncs `cameraNode.simdPosition` / `simdOrientation` every frame. Call `adapter.stop()` on teardown.

---

## Metal integration

```swift
import MetalKit
import GestureCamera
import GestureCameraMetalKit

class MyRenderer {
    let controller = GestureCameraController()
    var adapter: MetalKitCameraAdapter!

    init(mtkView: MTKView) {
        adapter = MetalKitCameraAdapter(controller: controller, view: mtkView)

        adapter.onDraw = { [weak self] view, transform in
            guard let self,
                  let drawable = view.currentDrawable,
                  let rpd      = view.currentRenderPassDescriptor else { return }

            var uniforms = FrameUniforms(
                viewMatrix:       transform.viewMatrix,
                projectionMatrix: self.projectionMatrix(for: view)
            )
            // encode render commands ...
        }

        adapter.start()
    }
}
```

`MetalKitCameraAdapter` sets `mtkView.isPaused = true` and takes over the display link. `CameraTransform.viewMatrix` is a `simd_float4x4` ready to upload as a shader uniform.

---

## Overlay and settings

`WASDOverlayView` is a full-screen SwiftUI overlay. Place it in a `ZStack` above your 3D view:

- **Left thumb** — `+` arrow cross for forward / back / strafe
- **Right thumb** — stacked `↑↓` for vertical
- **Top-right** — motion enable toggle (`rotate.3d` icon)

`CameraSettingsView` is a standalone settings form to present as a sheet or push from a navigation stack. It exposes:

- Invert touch rotation toggle
- Movement speed slider
- Per-axis sensitivity sliders (Fwd/Back, Left/Right, Up/Down)
- **Test Translation** button — opens `CameraTranslationTestView`

`CameraTranslationTestView` lets users walk around and watch a live direction indicator while tuning sensitivity per axis. Motion starts automatically when the view appears and stops when it's dismissed.

**Always pause the controller when presenting settings** so the camera doesn't drift:

```swift
.onChange(of: showSettings) { isShowing in
    controller.isPaused = isShowing
}
```

---

## Key properties

```swift
controller.movementSpeed            // world units / second (default 3.0)
controller.forwardImpulseThreshold  // step sensitivity, 0.1–1.0 (default 0.4)
controller.lateralImpulseThreshold  // step sensitivity, 0.1–1.0 (default 0.4)
controller.verticalImpulseThreshold // raise/lower sensitivity, 0.1–1.0 (default 0.6)
controller.invertTouchGestures      // flip touch drag axes (default true)
controller.isPaused                 // freeze all movement
controller.toggleMotion()           // start / stop device motion tracking
```
