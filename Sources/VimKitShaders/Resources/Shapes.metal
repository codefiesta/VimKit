//
//  Shapes.metal
//
//
//  Created by Kevin McKee
//

#include <metal_stdlib>
#include "../include/ShaderTypes.h"
using namespace metal;

typedef struct {
    float4 position [[attribute(VertexAttributePosition)]];
} SphereIn;

struct ShpereOut {
    float4 position [[position]];
};

// Sphere vertex function
vertex ShpereOut vertexSphere(SphereIn in [[stage_in]],
                              ushort amp_id [[amplification_id]],
                              uint vertex_id [[vertex_id]],
                              constant UniformsArray &uniformsArray [[ buffer(BufferIndexUniforms) ]],
                              constant float4x4 &modelMatrix [[buffer(BufferIndexInstances)]]) {
    ShpereOut out;
    Uniforms uniforms = uniformsArray.uniforms[amp_id];
    float4x4 viewMatrix = uniforms.viewMatrix;
    float4x4 projectionMatrix = uniforms.projectionMatrix;
    float4x4 modelViewProjectionMatrix = projectionMatrix * viewMatrix * modelMatrix;

    // Position
    float4 position = in.position;
    out.position = modelViewProjectionMatrix * position;
    return out;
}

// Sphere fragment function
fragment float4 fragmentSphere(ShpereOut fragmentIn [[stage_in]]) {
    return float4(1, 0, 0, 1);
}

