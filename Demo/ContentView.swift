import SwiftUI
import GestureCamera

struct ContentView: View {
    @StateObject private var controller = GestureCameraController()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            CubeSceneView(controller: controller)
                .ignoresSafeArea()
            WASDOverlayView(controller: controller)

            // Gear button — top-left, clear of the motion toggle
            VStack {
                HStack {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 22, weight: .medium))
                            .frame(width: 52, height: 52)
                            .background(.black.opacity(0.55))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding([.top, .leading], 20)
                    Spacer()
                }
                Spacer()
            }
        }
        .sheet(isPresented: $showSettings) {
            CameraSettingsView(controller: controller)
        }
    }
}
