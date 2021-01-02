//
//  LineSegment.swift
//  Kaleidoscope
//
//  Created by Gareth Spor on 1/1/21.
//

import Foundation

struct LineSegment {
    var p0x: Float = 0.0
    var p0y: Float = 0.0
    var p1x: Float = 0.0
    var p1y: Float = 0.0

    // Precompute the following values for shaders
    // point1 - point0
    var vecX: Float = 0.0
    var vecY: Float = 0.0

    // Ax + By + C = 0;
    var coefA: Float = 0.0
    var coefB: Float = 0.0
    var coefC: Float = 0.0
    var coefBASquaredDiff: Float = 0.0;  // B^2 - A^2
    var coefABSquaredSum: Float = 0.0;  // A^2 + B^2
    var twoAB: Float = 0.0;  // 2 * A * B
    var twoAC: Float = 0.0;  // 2 * A * C
    var twoBC: Float = 0.0;  // 2 * B * C
};
