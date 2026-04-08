# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Package structure

```
Sources/GestureCamera/          # Core library (CoreMotion + simd, no SceneKit dep)
Sources/GestureCameraSceneKit/  # SceneKit adapter (depends on GestureCamera)
Demo/                           # iOS app sources (needs an Xcode project to run)
Tests/GestureCameraTests/
```

## Building

`swift build` targets the host (macOS) and will fail — this package is iOS-only. Use xcodebuild:

```bash
xcodebuild build -scheme GestureCamera         -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
xcodebuild build -scheme GestureCameraSceneKit -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
xcodebuild build -scheme GestureCameraMetalKit -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

The `Demo/` folder contains Swift sources and an xcodegen spec. To regenerate or build:

```bash
cd Demo
xcodegen generate                                # regenerate GestureCameraDemo.xcodeproj
xcodebuild build -project GestureCameraDemo.xcodeproj \
  -scheme GestureCameraDemo \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
```

The generated `.xcodeproj` is gitignored (regenerate from `project.yml` as needed).

## Architecture

**`GestureCamera` (core library)**

- `CameraTransform` — value type: `position: SIMD3<Float>` + `orientation: simd_quatf`. Exposes derived `forward`, `right`, `up` vectors.
- `MotionCameraDriver` — thin `CMMotionManager` wrapper. On `start()`, latches the first attitude sample as a reference frame; subsequent callbacks fire with `(yaw, pitch)` in radians relative to that reference. Callbacks run on main thread.
- `GestureCameraController` — `@MainActor ObservableObject`. Single source of truth for `transform`. Three input channels:
  - **Motion**: `toggleMotion()` starts/stops `MotionCameraDriver`. On enable, snapshots current orientation as `motionBaseOrientation`; attitude deltas are applied on top of it.
  - **Gesture**: `applyTranslationGesture(dx:dy:sensitivity:)` translates along the camera's local X/Y plane.
  - **WASD**: `setMoving(_:active:)` sets directional flags. `update(deltaTime:)` must be called every frame to apply movement; Space = up, Shift = down.
- `WASDOverlayView` — SwiftUI full-screen overlay. Renders a WASD diamond, Space/Shift buttons, and the `rotate.3d` motion toggle.

**`GestureCameraSceneKit`**

- `SceneKitCameraAdapter` — `@MainActor` class. Uses a `CADisplayLink` to call `controller.update(deltaTime:)` and sync `cameraNode.simdPosition`/`simdOrientation` each frame.

**Demo**

- `CubeSceneView` — `UIViewRepresentable` wrapping `SCNView`. Creates the scene (lit cube + checkerboard floor), wires up `SceneKitCameraAdapter`, and installs a `UIPanGestureRecognizer` that forwards deltas to `applyTranslationGesture`.
- `ContentView` — `ZStack` of `CubeSceneView` + `WASDOverlayView` sharing one `@StateObject GestureCameraController`.

## Key design decisions

- `MotionCameraDriver` is dependency-injectable so the controller can be tested without hardware.
- Motion yaw maps to world-Y rotation; pitch maps to local-X rotation. Signs can be flipped via `motionSensitivity` (negate to invert).
- `SceneKitCameraAdapter` owns the display link lifetime; call `stop()` on teardown to avoid retain cycles through the display link target.
- The `GestureCamera` library has zero external dependencies (system frameworks only: CoreMotion, simd, SwiftUI).
