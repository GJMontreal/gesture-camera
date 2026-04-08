import SwiftUI

/// Walk around while watching this view to tune translation sensitivity.
/// Each detected step lights up the corresponding arrow for 0.3 s.
/// Motion is enabled automatically while the view is presented.
public struct CameraTranslationTestView: View {

    @ObservedObject var controller: GestureCameraController
    @Environment(\.dismiss) private var dismiss

    @State private var lit: Set<ImpulseEvent.Axis> = []

    public init(controller: GestureCameraController) {
        self.controller = controller
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Text("Walk forward, backward, left, and right.\nEach step should light up the matching arrow.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                directionIndicator

                Spacer()

                // Sensitivity slider
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Sensitivity")
                        Spacer()
                        Text(sensitivityLabel(controller.impulseThreshold))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { 1.1 - controller.impulseThreshold },
                            set: { controller.impulseThreshold = 1.1 - $0 }
                        ),
                        in: 0.1...1.0
                    )
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .navigationTitle("Test Translation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if !controller.isMotionEnabled { controller.toggleMotion() }
            }
            .onDisappear {
                if controller.isMotionEnabled { controller.toggleMotion() }
            }
            .onChange(of: controller.lastImpulse) { event in
                guard let event else { return }
                lit.insert(event.axis)
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    lit.remove(event.axis)
                }
            }
        }
    }

    // MARK: - Direction indicator

    private var directionIndicator: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                blank
                arrowCell("↑", axis: .forward)
                blank
            }
            HStack(spacing: 8) {
                arrowCell("←", axis: .left)
                blank
                arrowCell("→", axis: .right)
            }
            HStack(spacing: 8) {
                blank
                arrowCell("↓", axis: .backward)
                blank
            }
        }
    }

    private var blank: some View {
        Color.clear.frame(width: cellSize, height: cellSize)
    }

    private func arrowCell(_ symbol: String, axis: ImpulseEvent.Axis) -> some View {
        let active = lit.contains(axis)
        return Text(symbol)
            .font(.system(size: 28, weight: .semibold))
            .frame(width: cellSize, height: cellSize)
            .background(active ? Color.green.opacity(0.85) : Color.secondary.opacity(0.15))
            .foregroundStyle(active ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .animation(.easeOut(duration: 0.15), value: active)
    }

    private let cellSize: CGFloat = 64

    private func sensitivityLabel(_ threshold: Double) -> String {
        switch threshold {
        case ..<0.2: return "High"
        case ..<0.5: return "Medium"
        default:     return "Low"
        }
    }
}
