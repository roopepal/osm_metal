//
//  Math.swift
//  OsmMetal
//
//  Created by Roope on 6.3.2024.
//

// swiftlint:disable comma

import simd

extension simd_float4x4 {

    init(translate t: simd_float3) {
        self.init(SIMD4<Float>(  1,   0,   0, 0),
                  SIMD4<Float>(  0,   1,   0, 0),
                  SIMD4<Float>(  0,   0,   1, 0),
                  SIMD4<Float>(t.x, t.y, t.z, 1))
    }

    init(rotateY yRadians: Float) {
        let s = sin(yRadians)
        let c = cos(yRadians)
        self.init(SIMD4<Float>(  c,   0,   s,   0),
                  SIMD4<Float>(  0,   1,   0,   0),
                  SIMD4<Float>( -s,   0,   c,   0),
                  SIMD4<Float>(  0,   0,   0,   1))
    }

    init(perspectiveProjectionFoVY fovYRadians: Float,
         aspectRatio: Float,
         near: Float,
         far: Float
    ) {
        let sy = 1 / tan(fovYRadians * 0.5)
        let sx = sy / aspectRatio
        let zRange = far - near
        let sz = -far / zRange
        let tz = -2 * far * near / zRange
        self.init(SIMD4<Float>(sx, 0,  0,  0),
                  SIMD4<Float>(0, sy,  0,  0),
                  SIMD4<Float>(0,  0, sz, -1),
                  SIMD4<Float>(0,  0, tz,  0))
    }

    init(lookAt at: SIMD3<Float>,
         from: SIMD3<Float>,
         up: SIMD3<Float>
    ) {
        let zNeg = normalize(at - from)
        let x = normalize(cross(zNeg, up))
        let y = normalize(cross(x, zNeg))
        self.init(SIMD4<Float>(x, 0),
                  SIMD4<Float>(y, 0),
                  SIMD4<Float>(-zNeg, 0),
                  SIMD4<Float>(from, 1))
    }
}

// swiftlint:enable comma
