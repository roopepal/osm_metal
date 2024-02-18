//
//  FloatingPointExtensions.swift
//  OsmMetal
//
//  Created by Roope on 9.3.2024.
//

import Foundation

extension FloatingPoint {

    func rescale(
        from: (min: Self, max: Self),
        to: (min: Self, max: Self)
    ) -> Self {
        let zeroToOne = (self - from.min) / (from.max - from.min)
        return (to.max - to.min) * zeroToOne + to.min
    }
}
