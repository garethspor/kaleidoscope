//
//  LineSegment.swift
//  Kaleidoscope
//
//  Created by Gareth Spor on 1/1/21.
//

import Foundation

struct Vec2f {
    var x: Float
    var y: Float
}

struct LineSegment {
    var p0 = Vec2f(x:0.0, y:0.0)
    var p1 = Vec2f(x:0.0, y:0.0)

    // Precompute the following values for shaders
    // point1 - point0
    var vec = Vec2f(x:0.0, y:0.0)

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

func MakeLineSegment(p0: Vec2f, p1: Vec2f) -> LineSegment {
    let coefA: Float = p0.y - p1.y
    let coefB: Float = p1.x - p0.x
    let coefC: Float = p0.x * p1.y - p1.x * p0.y
    return LineSegment(
        p0: p0, p1: p1,
        vec: Vec2f(x: p1.x - p0.x, y: p1.y - p0.y),
        coefA: coefA, coefB: coefB, coefC: coefC,
        coefBASquaredDiff: coefB * coefB - coefA * coefA,
        coefABSquaredSum: coefA * coefA + coefB * coefB,
        twoAB: 2.0 * coefA * coefB,
        twoAC: 2.0 * coefA * coefC,
        twoBC: 2.0 * coefB * coefC
    )
}
