import simd

/// The camera's position and orientation in world space.
public struct CameraTransform: Equatable {
    public var position: SIMD3<Float>
    /// Orientation as a unit quaternion; maps +Z camera-space to world forward.
    public var orientation: simd_quatf

    public static let identity = CameraTransform(
        position: SIMD3<Float>(0, 1, 5),
        orientation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    )

    public init(position: SIMD3<Float>, orientation: simd_quatf) {
        self.position = position
        self.orientation = orientation
    }

    /// -Z in camera space, rotated into world space.
    public var forward: SIMD3<Float> { orientation.act(SIMD3<Float>(0, 0, -1)) }
    public var right:   SIMD3<Float> { orientation.act(SIMD3<Float>(1, 0, 0)) }
    public var up:      SIMD3<Float> { orientation.act(SIMD3<Float>(0, 1, 0)) }

    /// View matrix (world → camera space). Pass directly to a vertex shader uniform.
    ///
    /// Computed as the inverse of the camera's world transform:
    ///   V = [R^T | -R^T * position]
    public var viewMatrix: simd_float4x4 {
        let invQ = orientation.inverse
        var m    = simd_float4x4(invQ)          // upper-left 3×3 = R^T
        let t    = invQ.act(position)            // R^T * position
        m.columns.3 = SIMD4<Float>(-t.x, -t.y, -t.z, 1)
        return m
    }
}
