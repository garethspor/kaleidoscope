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
    float2 segmentA(0.1, 0.4);
    float2 segmentB(0.4, 0.1);

    // Ax + By + C = 0;
    float A = 1;
    float B = 1;
    float C = -0.5;

    float2 d1(target - center);
    float2 d2(segmentB - segmentA);

    // determinant
    float det = d1.x * d2.y - d2.x * d1.y;

    bool intersected = false;
    if (det != 0.0) {
        // lines are not parallel
        float2 d3(center - segmentA);
        float det1 = d1.x * d3.y - d3.x * d1.y;
        float s = det1 / det;
        if (s >= 0.0 && s <= 1.0) {
            float det2 = d2.x * d3.y - d3.x * d2.y;
            float t = det2 / det;
            if (t >= 0.0 && t < 1.0) {
                intersected = true;
                // Compute reflection
                float u = ((B * B - A * A) * target.x
                           - 2 * A * B * target.y
                           - 2 * A * C)
                          / (A * A + B * B);
                float v = ((A * A - B * B) * target.y
                           - 2 * A * B * target.x
                           - 2 * B * C)
                          / (A * A + B * B);
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
