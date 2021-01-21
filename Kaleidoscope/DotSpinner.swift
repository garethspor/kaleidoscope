//
//  DotSpinner.swift
//  Kaleidoscope
//
//  Created by Gareth Spor on 1/20/21.
//

import CoreGraphics
import Foundation

// Class for managing state of spinning kaleidoscope mirror dots
class DotSpinner {

    private let originalFrames: [CGRect]
    private let rotationCenter: CGPoint
    private let originalAngles: [Double]
    private let originalDistances: [Double]

    private var rotation: Double = 0.0
    private var rotationSpeed: Double = 0.0
    var rotationAcceleration = Double.pi / 30 / 120
    var accelerating = false

    var spunFrames : [CGRect] {
        var frames : [CGRect] = []
        for index in 0..<originalFrames.count {
            let theta = originalAngles[index] + rotation
            let spunOrigin = CGPoint(
                x: rotationCenter.x + CGFloat(sin(theta) * originalDistances[index]),
                y: rotationCenter.y + CGFloat(cos(theta) * originalDistances[index]))
            frames.append(CGRect(origin: spunOrigin, size: originalFrames[index].size))
        }
        return frames
    }

    func resetRotation() {
        rotation = 0.0
        rotationSpeed = 0.0
    }

    func updateRotation() {
        if accelerating {
            rotationSpeed += rotationAcceleration
        }
        rotation += rotationSpeed
    }

    required init(withFrames frames: [CGRect]) {
        originalFrames = frames

        var meanOrigin = CGPoint(x: 0, y: 0)
        for frame in frames {
            meanOrigin.x += frame.origin.x
            meanOrigin.y += frame.origin.y
        }
        meanOrigin.x /= CGFloat(frames.count)
        meanOrigin.y /= CGFloat(frames.count)

        rotationCenter = meanOrigin
        var angles : [Double] = []
        var distances : [Double] = []
        for frame in frames {
            let deltaX = Double(frame.origin.x - rotationCenter.x)
            let deltaY = Double(frame.origin.y - rotationCenter.y)
            angles.append(atan2(deltaX, deltaY))
            distances.append(sqrt(deltaX * deltaX + deltaY * deltaY))
        }
        originalAngles = angles
        originalDistances = distances
    }
}
