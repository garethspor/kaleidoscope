//
//  Filter2.metal
//  AVCamFilter
//
//  Created by Gareth Spor on 12/26/20.
//

#include <metal_stdlib>
using namespace metal;

// TODO: figure out why bool has to come after int
struct FilterParams {
    int numSegments = 3;
    int filler = 0;  // WAR to match packing format of Swift struct
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

half4 Sample(texture2d<half, access::read>  texture,
             float2 target,
             bool mirrored,
             int maxSize) {
    uint sampleY = target.y * maxSize;
    if (mirrored) {
        sampleY = texture.get_height() - 1 - sampleY;
    }
    uint2 sampleCoords{uint(target.x * maxSize), sampleY};
    return texture.read(sampleCoords);
}

// Compute kernel
kernel void kaleidoscope2(texture2d<half, access::read>  inputTexture  [[ texture(0) ]],
                          texture2d<half, access::write> outputTexture [[ texture(1) ]],
                          constant FilterParams *params [[ buffer(0) ]],
                          constant LineSegment *mirrors [[ buffer(1) ]],
                          uint2 gid [[thread_position_in_grid]])
{
    const int maxSize = max(inputTexture.get_width() - 1, inputTexture.get_height() - 1);

    // Center on the mean of all mirror corners
    float2 center{0, 0};
    for (int i = 0; i < params->numSegments; ++i) {
        center += mirrors[i].point0;
        center += mirrors[i].point1;
    }
    center /= (params->numSegments * 2);

    const float gridY = params->mirrored ? inputTexture.get_height() - 1 - gid.y : gid.y;
    float2 target(float(gid.x) / maxSize, gridY / maxSize);

    constexpr int MAX_REFLECTIONS = 128;
    constexpr float MIRROR_BRIGHTNESS = 0.75;
    constexpr float MIRROR_TRANSPARENCY = 0.125;

    half4 color = Sample(inputTexture, target, params->mirrored, maxSize);

    int numReflections = 0;
    int lastReflectionSegment = -1;
    while (numReflections < MAX_REFLECTIONS) {
        bool reflected = false;
        for (int i = 0; i < params->numSegments; ++i) {
            if (i == lastReflectionSegment) {
                continue;
            }
            // For now, just go with the 1st intersection. For more complex shapes, we'll need to use the closest intersection.
            if (Intersects(center, target, mirrors[i])) {
                target = Reflect(target, mirrors[i]);

                half4 newColor = Sample(inputTexture, target, params->mirrored, maxSize);
                color.rgb *= MIRROR_TRANSPARENCY;
                color.rgb += MIRROR_BRIGHTNESS * newColor.rgb;

                lastReflectionSegment = i;
                ++numReflections;
                reflected = true;
                break;
            }
        }
        if (!reflected) {
            break;
        }
    }

    outputTexture.write(color, gid);
}
