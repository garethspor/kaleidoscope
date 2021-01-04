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
    var vec: CGPoint { get { return CGPoint(x: p1.x - p0.x, y: p1.y - p0.y) }}
    // Ax + By + C = 0;
    var coefA: CGFloat { get { return p0.y - p1.y }}
    var coefB: CGFloat { get { return p1.x - p0.x }}
    var coefC: CGFloat { get { return p0.x * p1.y - p1.x * p0.y }}
    var coefBASquaredDiff: CGFloat { get { return coefB * coefB - coefA * coefA }}
    var coefABSquaredSum: CGFloat { get { return coefA * coefA + coefB * coefB }}
    var twoAB: CGFloat { get { return 2.0 * coefA * coefB }}
    var twoAC: CGFloat { get { return 2.0 * coefA * coefC }}
    var twoBC: CGFloat { get { return 2.0 * coefB * coefC }}
    
    // Convert to floats to be compatable with LineSegment struct in metal shader
    var asFloats: [Float] {
        get {
            return [Float(p0.x), Float(p0.y),
                    Float(p1.x), Float(p1.y),
                    Float(vec.x), Float(vec.y),
                    Float(coefA),
                    Float(coefB),
                    Float(coefC),
                    Float(coefBASquaredDiff),
                    Float(coefABSquaredSum),
                    Float(twoAB),
                    Float(twoAC),
                    Float(twoBC)]
        }
    }
};

