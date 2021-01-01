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
    half4 inputColor = inputTexture.read(gid);

    half4 outputColor = half4(inputColor.r, inputColor.g, 0.0, 1.0);

    outputTexture.write(outputColor, gid);
}
