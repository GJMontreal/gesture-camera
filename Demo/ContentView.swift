import SwiftUI
import GestureCamera

struct ContentView: View {
    @StateObject private var controller = GestureCameraController()

    var body: some View {
        ZStack {
            CubeSceneView(controller: controller)
                .ignoresSafeArea()
            WASDOverlayView(controller: controller)
        }
    }
}
