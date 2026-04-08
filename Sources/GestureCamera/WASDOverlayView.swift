import SwiftUI

/// Full-screen overlay with a two-hand control layout:
///   - Left thumb:  D-pad (arrow cross) for forward/back/strafe
///   - Right thumb: stacked up/down arrows for vertical
///   - Top-right:   motion enable toggle
public struct WASDOverlayView: View {

    @ObservedObject var controller: GestureCameraController

    public init(controller: GestureCameraController) {
        self.controller = controller
    }

    public var body: some View {
        VStack {
            HStack {
                Spacer()
                motionToggle
            }
            .padding([.top, .trailing], 20)
            Spacer()
            HStack(alignment: .bottom) {
                dpad.padding([.leading, .bottom], 20)
                Spacer()
                verticalControl.padding([.trailing, .bottom], 20)
            }
        }
        .onDisappear {
            for direction in [GestureCameraController.MoveDirection.forward, .backward,
                              .left, .right, .up, .down] {
                controller.setMoving(direction, active: false)
            }
        }
    }

    // MARK: - D-pad (left thumb)

    /// Classic + cross: ↑ on top, ← and → on the sides, ↓ on the bottom.
    private var dpad: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                blank
                arrowButton("↑", .forward)
                blank
            }
            HStack(spacing: 4) {
                arrowButton("←", .left)
                blank
                arrowButton("→", .right)
            }
            HStack(spacing: 4) {
                blank
                arrowButton("↓", .backward)
                blank
            }
        }
    }

    // MARK: - Vertical control (right thumb)

    private var verticalControl: some View {
        VStack(spacing: 4) {
            arrowButton("↑", .up)
            arrowButton("↓", .down)
        }
    }

    // MARK: - Shared

    private var blank: some View {
        Color.clear.frame(width: keySize, height: keySize)
    }

    private func arrowButton(_ symbol: String, _ direction: GestureCameraController.MoveDirection) -> some View {
        Text(symbol)
            .font(.system(size: 22, weight: .medium))
            .frame(width: keySize, height: keySize)
            .background(.black.opacity(0.55))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in controller.setMoving(direction, active: true) }
                    .onEnded   { _ in controller.setMoving(direction, active: false) }
            )
    }

    // MARK: - Motion toggle (top-right)

    private var motionToggle: some View {
        Button { controller.toggleMotion() } label: {
            Image(systemName: "rotate.3d")
                .font(.system(size: 22, weight: .medium))
                .frame(width: keySize, height: keySize)
                .background(controller.isMotionEnabled ? Color.blue.opacity(0.75) : Color.black.opacity(0.55))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(controller.isMotionEnabled ? Color.blue : Color.clear, lineWidth: 2)
                )
        }
    }

    private let keySize: CGFloat = 52
}
