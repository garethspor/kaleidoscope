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
    int2 maxSize(inputTexture.get_width() - 1, inputTexture.get_height() - 1);
    float2 fid(float(gid.x) / maxSize.x, float(gid.y) / maxSize.y);

    fid = sin(fid * M_PI_F * 2);
    fid = (fid + 1.0) / 2.0;

    uint2 sampleId(fid.x * maxSize.x, fid.y * maxSize.y);
    half4 inputColor = inputTexture.read(sampleId);

    half4 outputColor = half4(inputColor.r, inputColor.g, inputColor.b, 1.0);

    outputTexture.write(outputColor, gid);
}
