//
//  Filter2.metal
//  AVCamFilter
//
//  Created by Gareth Spor on 12/26/20.
//

#include <metal_stdlib>
using namespace metal;

struct FilterParams {
    int kaleidoscopeOrder = 7;  // A nice default value
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

// Compute kernel
kernel void kaleidoscope2(texture2d<half, access::read>  inputTexture  [[ texture(0) ]],
                          texture2d<half, access::write> outputTexture [[ texture(1) ]],
                          constant FilterParams *params [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]])
{
    uint2 sampleId = gid;
    int maxSize = max(inputTexture.get_width() - 1, inputTexture.get_height() - 1);

    float2 center(0.5, 0.5);
    float2 target(float(gid.x) / maxSize, float(gid.y) / maxSize);

    // Hard code a segment to test against
    LineSegment line{
        .point0 = {0.1, 0.4},
        .point1 = {0.4, 0.1},
        .vectorRepresentation = {0.3, -0.3},
        .coefA = 1.0,
        .coefB = 1.0,
        .coefC = -0.5,
        .coefBASquaredDiff = 0.0,
        .coefABSquaredSum = 2.0,
        .twoAB = 2.0,
        .twoAC = -1.0,
        .twoBC = -1.0
    };

    float2 d1(target - center);
    float2 d2 = line.vectorRepresentation;

    // determinant  https://stackoverflow.com/questions/3838329/how-can-i-check-if-two-segments-intersect
    float det = d1.x * d2.y - d2.x * d1.y;

    bool intersected = false;
    if (det != 0.0) {
        // lines are not parallel
        float2 d3(center - line.point0);
        float det1 = d1.x * d3.y - d3.x * d1.y;
        float s = det1 / det;
        if (s >= 0.0 && s <= 1.0) {
            float det2 = d2.x * d3.y - d3.x * d2.y;
            float t = det2 / det;
            if (t >= 0.0 && t < 1.0) {
                intersected = true;
                // Compute reflection  http://www.sdmath.com/math/geometry/reflection_across_line.html
                float u = (line.coefBASquaredDiff * target.x
                           - line.twoAB * target.y
                           - line.twoAC)
                          / line.coefABSquaredSum;
                float v = (-line.coefBASquaredDiff * target.y
                           - line.twoAB * target.x
                           - line.twoBC)
                          / line.coefABSquaredSum;
                sampleId.x = u * maxSize;
                sampleId.y = v * maxSize;
            }
        }
    }

    half4 color = inputTexture.read(sampleId);
    if (intersected) {
        // Simulate dark mirror. Don't modify the alpha chanel!
        color.rgb *= 0.5;
    }
    outputTexture.write(color, gid);
}
