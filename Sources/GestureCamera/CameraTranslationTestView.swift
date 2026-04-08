import SwiftUI

/// Walk around while watching this view to tune translation sensitivity.
/// Each detected step lights up the corresponding arrow for 0.3 s.
/// Motion is enabled automatically while the view is presented.
public struct CameraTranslationTestView: View {

    @ObservedObject var controller: GestureCameraController
    @Environment(\.dismiss) private var dismiss

    @State private var lit: Set<ImpulseEvent.Axis> = []
    @State private var translationWasEnabled = false

    public init(controller: GestureCameraController) {
        self.controller = controller
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Direction indicator
                VStack(spacing: 12) {
                    Spacer()
                    Text("Walk in each direction and adjust until steps\nregister reliably without false triggers.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    directionIndicator
                    Spacer()
                }
                .frame(maxWidth: .infinity)

                Divider()

                // Sliders — always visible below the indicator
                VStack(spacing: 20) {
                    axisSlider(
                        label: "Fwd / Back",
                        systemImage: "arrow.up.arrow.down",
                        value: Binding(
                            get: { 1.1 - controller.forwardImpulseThreshold },
                            set: { controller.forwardImpulseThreshold = 1.1 - $0 }
                        ),
                        threshold: controller.forwardImpulseThreshold,
                        activeAxes: [.forward, .backward]
                    )
                    axisSlider(
                        label: "Left / Right",
                        systemImage: "arrow.left.arrow.right",
                        value: Binding(
                            get: { 1.1 - controller.lateralImpulseThreshold },
                            set: { controller.lateralImpulseThreshold = 1.1 - $0 }
                        ),
                        threshold: controller.lateralImpulseThreshold,
                        activeAxes: [.left, .right]
                    )
                    axisSlider(
                        label: "Up / Down",
                        systemImage: "arrow.up.arrow.down",
                        value: Binding(
                            get: { 1.1 - controller.verticalImpulseThreshold },
                            set: { controller.verticalImpulseThreshold = 1.1 - $0 }
                        ),
                        threshold: controller.verticalImpulseThreshold,
                        activeAxes: [.up, .down]
                    )
                }
                .padding(24)
            }
            .navigationTitle("Test Translation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                translationWasEnabled = controller.isMotionTranslationEnabled
                controller.isMotionTranslationEnabled = true
                if !controller.isMotionEnabled { controller.toggleMotion() }
            }
            .onDisappear {
                if controller.isMotionEnabled { controller.toggleMotion() }
                controller.isMotionTranslationEnabled = translationWasEnabled
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
        HStack(alignment: .center, spacing: 24) {
            // Forward/lateral cross
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    blank
                    arrowCell("↑", axis: .forward)
                    blank
                }
                HStack(spacing: 10) {
                    arrowCell("←", axis: .left)
                    blank
                    arrowCell("→", axis: .right)
                }
                HStack(spacing: 10) {
                    blank
                    arrowCell("↓", axis: .backward)
                    blank
                }
            }

            // Vertical column
            VStack(spacing: 10) {
                arrowCell("↑", axis: .up)
                arrowCell("↓", axis: .down)
            }
        }
    }

    private var blank: some View {
        Color.clear.frame(width: cellSize, height: cellSize)
    }

    private func arrowCell(_ symbol: String, axis: ImpulseEvent.Axis) -> some View {
        let active = lit.contains(axis)
        return Text(symbol)
            .font(.system(size: 30, weight: .semibold))
            .frame(width: cellSize, height: cellSize)
            .background(active ? Color.green.opacity(0.85) : Color.secondary.opacity(0.15))
            .foregroundStyle(active ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .animation(.easeOut(duration: 0.12), value: active)
    }

    private let cellSize: CGFloat = 72

    // MARK: - Axis slider

    private func axisSlider(
        label: String,
        systemImage: String,
        value: Binding<Double>,
        threshold: Double,
        activeAxes: Set<ImpulseEvent.Axis>
    ) -> some View {
        let isActive = !lit.isDisjoint(with: activeAxes)
        return VStack(spacing: 6) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(isActive ? .green : .secondary)
                    .animation(.easeOut(duration: 0.12), value: isActive)
                Text(label)
                    .fontWeight(.medium)
                Spacer()
                Text(sensitivityLabel(threshold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: 0.1...1.0)
        }
    }

    private func sensitivityLabel(_ threshold: Double) -> String {
        switch threshold {
        case ..<0.25: return "High"
        case ..<0.55: return "Medium"
        default:      return "Low"
        }
    }
}
