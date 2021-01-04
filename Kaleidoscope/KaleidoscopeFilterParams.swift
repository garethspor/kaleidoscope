//
//  KaleidoscopeFilterParams.swift
//  Kaleidoscope
//
//  Created by Gareth Spor on 1/3/21.
//

import Foundation

// Parameters to control Kaleidoscope filter (shader)
struct KaleidoscopeFilterParams {
    // Number of line segments in mirror model
    var numSegments: Int = 3
    // If view is mirrored (selfie mode)
    var mirrored: Bool = false
    // Brightness or reflectivity index of mirror
    var brightness: Float = 0.2
    // Transmisivity of mirror
    var transparency: Float = 0.8
    // Maximum number of reflections to trace
    var maxReflections: Int = 64
  }
