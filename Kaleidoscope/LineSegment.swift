//
//  LineSegment.swift
//  Kaleidoscope
//
//  Created by Gareth Spor on 1/1/21.
//

import Foundation
import CoreVideo

struct LineSegment {
    var p0: CGPoint
    var p1: CGPoint

    // Precompute the following values for shaders
    // point1 - point0
    var vec: CGPoint

    // Ax + By + C = 0;
    var coefA: CGFloat = 0.0
    var coefB: CGFloat = 0.0
    var coefC: CGFloat = 0.0
    var coefBASquaredDiff: CGFloat = 0.0;  // B^2 - A^2
    var coefABSquaredSum: CGFloat = 0.0;  // A^2 + B^2
    var twoAB: CGFloat = 0.0;  // 2 * A * B
    var twoAC: CGFloat = 0.0;  // 2 * A * C
    var twoBC: CGFloat = 0.0;  // 2 * B * C
};

func MakeLineSegment(p0: CGPoint, p1: CGPoint) -> LineSegment {
    let coefA: CGFloat = p0.y - p1.y
    let coefB: CGFloat = p1.x - p0.x
    let coefC: CGFloat = p0.x * p1.y - p1.x * p0.y
    return LineSegment(
        p0: p0, p1: p1,
        vec: CGPoint(x: p1.x - p0.x, y: p1.y - p0.y),
        coefA: coefA, coefB: coefB, coefC: coefC,
        coefBASquaredDiff: coefB * coefB - coefA * coefA,
        coefABSquaredSum: coefA * coefA + coefB * coefB,
        twoAB: 2.0 * coefA * coefB,
        twoAC: 2.0 * coefA * coefC,
        twoBC: 2.0 * coefB * coefC
    )
}

func ConvertLineSegmentToFloats(segment: LineSegment) -> [Float] {
    return [
        Float(segment.p0.x),
        Float(segment.p0.y),
        Float(segment.p1.x),
        Float(segment.p1.y),
        Float(segment.vec.x),
        Float(segment.vec.y),
        Float(segment.coefA),
        Float(segment.coefB),
        Float(segment.coefC),
        Float(segment.coefBASquaredDiff),
        Float(segment.coefABSquaredSum),
        Float(segment.twoAB),
        Float(segment.twoAC),
        Float(segment.twoBC)
    ]
}
