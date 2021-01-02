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

func MakeLineSegment(p0x: Float, p0y: Float, p1x: Float, p1y: Float) -> LineSegment {
    let coefA: Float = p0y - p1y
    let coefB: Float = p1x - p0x
    let coefC: Float = p0x * p1y - p1x * p0y
    return LineSegment(
        p0x: p0x, p0y: p0y,
        p1x: p1x, p1y: p1y,
        vecX: p1x - p0x, vecY: p1y - p0y,
        coefA: coefA, coefB: coefB, coefC: coefC,
        coefBASquaredDiff: coefB * coefB - coefA * coefA,
        coefABSquaredSum: coefA * coefA + coefB * coefB,
        twoAB: 2.0 * coefA * coefB,
        twoAC: 2.0 * coefA * coefC,
        twoBC: 2.0 * coefB * coefC
    )
}
