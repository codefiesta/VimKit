//
//  Depth.metal
//  VimKit
//
//  Created by Kevin McKee
//

#include <metal_stdlib>
#include "../include/ShaderTypes.h"
using namespace metal;

// Calculates a slice of a depth pyramid from a higher resolution slice.
// Handles downsampling from odd sized depth textures.
kernel void depthPyramid(uint2 index [[thread_position_in_grid]],
                         constant uint4& rect [[buffer(KernelBufferIndexDepthPyramidSize)]],
                         depth2d<float, access::sample> inDepth [[texture(0)]],
                         texture2d<float, access::write> outDepth [[texture(1)]]) {

    constexpr sampler sam (min_filter::nearest, mag_filter::nearest, coord::pixel);
    uint width = rect.x;
    uint height = rect.y;
    float2 src = float2(index * 2 + rect.zw);

    float minval = inDepth.sample(sam, src);
    minval = max(minval, inDepth.sample(sam, src + float2(0, 1)));
    minval = max(minval, inDepth.sample(sam, src + float2(1, 0)));
    minval = max(minval, inDepth.sample(sam, src + float2(1, 1)));

    bool edgeX = (index.x * 2 == width - 3);
    bool edgeY = (index.y * 2 == height - 3);

    if (edgeX) {
        minval = max(minval, inDepth.sample(sam, src + float2(2, 0)));
        minval = max(minval, inDepth.sample(sam, src + float2(2, 1)));
    }

    if (edgeY) {
        minval = max(minval, inDepth.sample(sam, src + float2(0, 2)));
        minval = max(minval, inDepth.sample(sam, src + float2(1, 2)));
    }

    if (edgeX && edgeY) minval = max(minval, inDepth.sample(sam, src + float2(2, 2)));

    outDepth.write(float4(minval), index);
}


