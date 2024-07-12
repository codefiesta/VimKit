//
//  Skycube.metal
//
//
//  Created by Kevin McKee
//

#include <metal_stdlib>
#include <simd/simd.h>
#include "../include/ShaderTypes.h"

using namespace metal;

// The struct that is passed to the vertex function
typedef struct {
    float4 position [[attribute(VertexAttributePosition)]];
} VertexIn;

// The struct that is passed from the vertex function to the fragment function
typedef struct {
    // The position of the vertex
    simd_float4 position [[position]];
    // The material color
    simd_float4 color;
    // The texture coordinates
    float3 textureCoordinates;
    // The instance identifier
    int32_t identifier;
} VertexOut;

// The struct that is returned from the fragment function
typedef struct {
    // The colorAttachments[0] that holds the color information
    float4 color [[color(0)]];
    // The colorAttachments[1] that holds the instance identifier (-1 indicates an invalid instance)
    int32_t identifier [[color(1)]];
} ColorOut;

vertex VertexOut vertexSkycube(VertexIn in [[stage_in]],
                              constant UniformsArray &uniformsArray [[ buffer(BufferIndexUniforms) ]],
                              constant InstanceUniforms &instanceUniforms [[ buffer(BufferIndexInstanceUniforms) ]],
                              uint vertex_id [[vertex_id]],
                              ushort amp_id [[amplification_id]]) {
    
    Uniforms uniforms = uniformsArray.uniforms[amp_id];
    simd_float4x4 projectionMatrix = uniforms.projectionMatrix;

    simd_float4x4 viewMatrix = uniforms.viewMatrix;
    viewMatrix[3] = float4(0, 0, 0, 1);

    simd_float4x4 viewProjectionMatrix = viewMatrix * projectionMatrix;
    
    VertexOut out;
    out.position = (viewProjectionMatrix * in.position).xyww;
    out.color = instanceUniforms.color;
    out.textureCoordinates = in.position.xyz;
    out.identifier = instanceUniforms.identifier;
    return out;
}

fragment ColorOut fragmentSkycube(VertexOut in [[stage_in]],
                                  texturecube<float> cubeTexture [[texture(0)]]) {
//    constexpr sampler default_sampler(filter::linear);
//    float4 color = cubeTexture.sample(default_sampler, in.textureCoordinates);
    ColorOut out;
    out.color = in.color;
    out.identifier = in.identifier;
    return out;
}
