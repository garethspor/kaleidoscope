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
kernel void kaleidoscope(texture2d<half, access::read>  inputTexture  [[ texture(0) ]],
                         texture2d<half, access::write> outputTexture [[ texture(1) ]],
                         constant FilterParams *params [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]])
{
    const int centerX = inputTexture.get_width() / 2;
    const int centerY = inputTexture.get_height() / 2;
    int sampleX = (int)gid.x - centerX;
    int sampleY = (int)gid.y - centerY;

    float theta = atan2((float)sampleY, (float)sampleX);
    float rad = sqrt((float)sampleY * sampleY + sampleX * sampleX);

    const float reflectLength = (float)inputTexture.get_width() * 0.5;
    if (rad > reflectLength) {
        rad = reflectLength - (rad - reflectLength);
    }

    const float wedgeAngle = 2 * M_PI_F / params->kaleidoscopeOrder;
    theta = fmod(theta + M_PI_F, wedgeAngle);
    theta -= (wedgeAngle / 2);
    theta = abs(theta);

    sampleX = cos(theta) * rad;
    sampleY = sin(theta) * rad;

    // instead of re-centering by adding back the center coords, multiply by 2 to make the sampling area larger.
    sampleX *= 2;
    sampleY *= 2;

    if (sampleX < 0 || sampleY < 0) {
        outputTexture.write(half4(0.0, 0.0, 0.0, 1.0), gid);
        return;
    }

    uint2 sampleId(sampleX, sampleY);

    // Don't read or write outside of the texture.
    if ((sampleId.x >= inputTexture.get_width()) || (sampleId.y >= inputTexture.get_height())) {
        outputTexture.write(half4(0.0, 0.0, 0.0, 1.0), gid);
        return;
    }

    half4 inputColor = inputTexture.read(sampleId);

    half4 outputColor = half4(inputColor.r, inputColor.g, inputColor.b, 1.0);

    outputTexture.write(outputColor, gid);
}
