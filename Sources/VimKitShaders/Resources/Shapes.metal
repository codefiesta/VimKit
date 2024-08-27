//
//  Shapes.metal
//
//
//  Created by Kevin McKee
//

#include <metal_stdlib>
#include "../include/ShaderTypes.h"
using namespace metal;

// The struct that is passed to the vertex function
typedef struct {
    float4 position [[attribute(VertexAttributePosition)]];
} VertexIn;

struct VertexOut {
    float4 position [[position]];
};

// Sphere vertex function
vertex VertexOut vertexSphere(VertexIn in [[stage_in]],
                              ushort amp_id [[amplification_id]],
                              uint vertex_id [[vertex_id]],
                              constant UniformsArray &uniformsArray [[ buffer(BufferIndexUniforms) ]],
                              constant float3 &center) {
    VertexOut out;
    Uniforms uniforms = uniformsArray.uniforms[amp_id];

    float4x4 modelMatrix = float4x4();
    modelMatrix[3] = float4(center, 1);

    float4x4 viewMatrix = uniforms.viewMatrix;
    float4x4 projectionMatrix = uniforms.projectionMatrix;
    float4x4 modelViewProjectionMatrix = projectionMatrix * viewMatrix * modelMatrix;
    float4x4 modelViewMatrix = viewMatrix * modelMatrix;

    // Position
    //out.position = modelViewProjectionMatrix * in.position;
    out.position = float4(center, 1) * in.position;

    out.position = in.position; // No transform, always in front of camera
    return out;
}

// Sphere fragment function
fragment float4 fragmentSphere(VertexOut fragmentIn [[stage_in]]) {
    return float4(1, 0, 0, 1);
}

