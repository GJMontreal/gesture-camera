import SwiftUI

/// A settings form for tuning camera behaviour.
/// Present this as a sheet or embed it in any settings screen.
///
/// ```swift
/// .sheet(isPresented: $showSettings) {
///     CameraSettingsView(controller: controller)
/// }
/// ```
public struct CameraSettingsView: View {

    @ObservedObject var controller: GestureCameraController
    @Environment(\.dismiss) private var dismiss

    @State private var showTranslationTest = false

    public init(controller: GestureCameraController) {
        self.controller = controller
    }

    public var body: some View {
        NavigationStack {
            Form {
                // MARK: Touch
                Section("Touch") {
                    Toggle("Invert Rotation", isOn: $controller.invertTouchGestures)
                }

                // MARK: Movement
                Section("Movement") {
                    LabeledSlider(
                        label: "Speed",
                        value: Binding(
                            get: { Double(controller.movementSpeed) },
                            set: { controller.movementSpeed = Float($0) }
                        ),
                        in: 0.5...10,
                        format: { String(format: "%.1f", $0) }
                    )
                }

                // MARK: Translation (motion impulse)
                Section {
                    Toggle("Step Detection", isOn: $controller.isMotionTranslationEnabled)
                } header: {
                    Text("Translation (Step Detection)")
                }

                if controller.isMotionTranslationEnabled {
                    Section("Sensitivity") {
                        LabeledSlider(
                            label: "Fwd / Back",
                            value: Binding(
                                get: { 1.1 - controller.forwardImpulseThreshold },
                                set: { controller.forwardImpulseThreshold = 1.1 - $0 }
                            ),
                            in: 0.1...1.0,
                            format: { _ in sensitivityLabel(controller.forwardImpulseThreshold) }
                        )
                        LabeledSlider(
                            label: "Left / Right",
                            value: Binding(
                                get: { 1.1 - controller.lateralImpulseThreshold },
                                set: { controller.lateralImpulseThreshold = 1.1 - $0 }
                            ),
                            in: 0.1...1.0,
                            format: { _ in sensitivityLabel(controller.lateralImpulseThreshold) }
                        )
                        LabeledSlider(
                            label: "Up / Down",
                            value: Binding(
                                get: { 1.1 - controller.verticalImpulseThreshold },
                                set: { controller.verticalImpulseThreshold = 1.1 - $0 }
                            ),
                            in: 0.1...1.0,
                            format: { _ in sensitivityLabel(controller.verticalImpulseThreshold) }
                        )
                        Button("Test Translation…") {
                            showTranslationTest = true
                        }
                    }
                }
            }
            .navigationTitle("Camera Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showTranslationTest) {
                CameraTranslationTestView(controller: controller)
            }
        }
    }

    private func sensitivityLabel(_ threshold: Double) -> String {
        switch threshold {
        case ..<0.2: return "High"
        case ..<0.5: return "Medium"
        default:     return "Low"
        }
    }
}

// MARK: - Helpers

private struct LabeledSlider: View {
    let label: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let format: (Double) -> String

    init(label: String, value: Binding<Double>, in range: ClosedRange<Double>, format: @escaping (Double) -> String) {
        self.label = label
        self.value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(format(value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
        }
        .padding(.vertical, 2)
    }
}
