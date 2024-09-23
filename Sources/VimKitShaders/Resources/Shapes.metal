//
//  Shapes.metal
//
//
//  Created by Kevin McKee
//

#include <metal_stdlib>
#include "../include/ShaderTypes.h"
using namespace metal;

// The struct that is passed to the shape vertex function
typedef struct {
    float3 position [[attribute(VertexAttributePosition)]];
} ShapeIn;

// The struct that is passed from the shape vertex function to the fragment function
struct ShapeOut {
    float4 position [[position]];
    float4 color;
};

// The shape vertex shader function.
// - Parameters:
//   - in: The vertex position data.
//   - amp_id: The index into the uniforms array used for stereoscopic views in visionOS.
//   - instance_id: The baseInstance parameter passed to the draw call used to map this instance to it's transform data.
//   - uniformsArray: The per frame uniforms.
//   - modelMatrix: The shape transform data
//   - color: The shape color.
//   - colorOverrides: The color overrides pointer used to apply custom color profiles to instances.
//   - xRay: Flag indicating if this frame is being rendered in xray mode.
vertex ShapeOut vertexShape(ShapeIn in [[stage_in]],
                            ushort amp_id [[amplification_id]],
                            uint vertex_id [[vertex_id]],
                            constant UniformsArray &uniformsArray [[ buffer(VertexBufferIndexUniforms) ]],
                            constant float4x4 &modelMatrix [[buffer(VertexBufferIndexInstances)]],
                            constant float4 &color [[buffer(VertexBufferIndexColors)]]) {
    ShapeOut out;
    Uniforms uniforms = uniformsArray.uniforms[amp_id];
    float4x4 viewMatrix = uniforms.viewMatrix;
    float4x4 projectionMatrix = uniforms.projectionMatrix;
    float4x4 modelViewProjectionMatrix = projectionMatrix * viewMatrix * modelMatrix;

    // Position
    float4 position = float4(in.position, 1.0);
    out.position = modelViewProjectionMatrix * position;
    // Color
    out.color = color;
    return out;
}

// The shape fragment shader function.
// - Parameters:
//   - in: the data passed from the vertex function.
fragment float4 fragmentShape(ShapeOut in [[stage_in]]) {
    return in.color;
}

