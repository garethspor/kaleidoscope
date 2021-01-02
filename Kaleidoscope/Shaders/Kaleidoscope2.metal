//
//  Filter2.metal
//  AVCamFilter
//
//  Created by Gareth Spor on 12/26/20.
//

#include <metal_stdlib>
using namespace metal;

struct FilterParams {
    bool mirrored = false;
};

struct LineSegment {
    float2 point0{0.0, 0.0};
    float2 point1{0.0, 0.0};
    float2 vectorRepresentation{0.0, 0.0};  // point1 - point0
    // Ax + By + C = 0;
    float coefA = 0.0;
    float coefB = 0.0;
    float coefC = 0.0;
    float coefBASquaredDiff = 0.0;  // B^2 - A^2
    float coefABSquaredSum = 0.0;  // A^2 + B^2
    float twoAB = 0.0;  // 2AB
    float twoAC = 0.0;  // 2AC
    float twoBC = 0.0;  // 2BC
};

float ComputeDeterminant(float2 a, float2 b) {
    return a.x * b.y - b.x * a.y;
}

float2 Reflect(float2 point, LineSegment line) {
    // from: http://www.sdmath.com/math/geometry/reflection_across_line.html
    return {(line.coefBASquaredDiff * point.x
               - line.twoAB * point.y
               - line.twoAC)
    / line.coefABSquaredSum,
      (-line.coefBASquaredDiff * point.y
               - line.twoAB * point.x
               - line.twoBC)
        / line.coefABSquaredSum};
}

bool Intersects(float2 point0, float2 point1, LineSegment segment) {
    // from: https://stackoverflow.com/questions/3838329/how-can-i-check-if-two-segments-intersect
    float2 vector(point1 - point0);
    float detA = ComputeDeterminant(vector, segment.vectorRepresentation);
    if (detA == 0.0) {
        // lines are parallel. For our purposes, assume no intersection.
        return false;
    }
    float2 d3(point0 - segment.point0);
    float detB = ComputeDeterminant(vector, d3);
    float s = detB / detA;
    if (s >= 0.0 && s <= 1.0) {
        float detC = ComputeDeterminant(segment.vectorRepresentation, d3);
        float t = detC / detA;
        if (t >= 0.0 && t < 1.0) {
            return true;
        }
    }
    return false;
}

// Compute kernel
kernel void kaleidoscope2(texture2d<half, access::read>  inputTexture  [[ texture(0) ]],
                          texture2d<half, access::write> outputTexture [[ texture(1) ]],
                          constant FilterParams *params [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]])
{
    const int maxSize = max(inputTexture.get_width() - 1, inputTexture.get_height() - 1);
    const float2 center(float(inputTexture.get_width() / 2) / maxSize,
                        float(inputTexture.get_height() / 2) / maxSize);
    const float gridY = params->mirrored ? inputTexture.get_height() - 1 - gid.y : gid.y;
    float2 target(float(gid.x) / maxSize, gridY / maxSize);

    // Hard code segments to test against
    const int numSegments = 3;
    LineSegment segments[3] =
    {{
        .point0 = {0.1, 0.6},
        .point1 = {0.5, 0.2},
        .vectorRepresentation = {0.4, -0.4},
        .coefA = 1.0,
        .coefB = 1.0,
        .coefC = -0.7,
        .coefBASquaredDiff = 0.0,
        .coefABSquaredSum = 2.0,
        .twoAB = 2.0,
        .twoAC = -1.4,
        .twoBC = -1.4
    },
    {
        .point0 = {0.5, 0.2},
        .point1 = {0.9, 0.6},
        .vectorRepresentation = {0.4, 0.4},
        .coefA = 1.0,
        .coefB = -1.0,
        .coefC = -0.3,
        .coefBASquaredDiff = 0.0,
        .coefABSquaredSum = 2.0,
        .twoAB = -2.0,
        .twoAC = -0.6,
        .twoBC = 0.6
    },
    {
        .point0 = {0.1, 0.6},
        .point1 = {0.9, 0.6},
        .vectorRepresentation = {0.8, 0.0},
        .coefA = 0.0,
        .coefB = 1.0,
        .coefC = -0.6,
        .coefBASquaredDiff = 1.0,
        .coefABSquaredSum = 1.0,
        .twoAB = 0.0,
        .twoAC = 0.0,
        .twoBC = -1.2
    }};

    constexpr int MAX_REFLECTIONS = 10;
    constexpr float MIRROR_BRIGHTNESS = 0.85;

    half4 color;
    int numReflections = 0;
    int lastReflectionSegment = -1;
    float brightness = 1.0;
    while (numReflections < MAX_REFLECTIONS) {
        bool reflected = false;
        for (int i = 0; i < numSegments; ++i) {
            if (i == lastReflectionSegment) {
                continue;
            }
            // For now, just go with the 1st intersection. For more complex shapes, we'll need to use the closest intersection.
            if (Intersects(center, target, segments[i])) {
                target = Reflect(target, segments[i]);
                lastReflectionSegment = i;
                ++numReflections;
                brightness *= MIRROR_BRIGHTNESS;
                reflected = true;
                break;
            }
        }
        if (!reflected) {
            break;
        }
    }

    uint sampleY = target.y * maxSize;
    if (params->mirrored) {
        sampleY = inputTexture.get_height() - 1 - sampleY;
    }
    uint2 sampleCoords{uint(target.x * maxSize), sampleY};
    color = inputTexture.read(sampleCoords);
    color.rgb *= brightness;

    outputTexture.write(color, gid);
}
