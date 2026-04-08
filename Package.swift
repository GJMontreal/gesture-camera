// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GestureCamera",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "GestureCamera",          targets: ["GestureCamera"]),
        .library(name: "GestureCameraSceneKit",  targets: ["GestureCameraSceneKit"]),
        .library(name: "GestureCameraMetalKit",  targets: ["GestureCameraMetalKit"]),
    ],
    targets: [
        .target(
            name: "GestureCamera",
            path: "Sources/GestureCamera"
        ),
        .target(
            name: "GestureCameraSceneKit",
            dependencies: ["GestureCamera"],
            path: "Sources/GestureCameraSceneKit"
        ),
        .target(
            name: "GestureCameraMetalKit",
            dependencies: ["GestureCamera"],
            path: "Sources/GestureCameraMetalKit"
        ),
        .testTarget(
            name: "GestureCameraTests",
            dependencies: ["GestureCamera"],
            path: "Tests/GestureCameraTests"
        ),
    ]
)
