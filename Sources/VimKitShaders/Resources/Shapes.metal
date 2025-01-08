//
//  Shapes.metal
//
//
//  Created by Kevin McKee
//

#include <metal_stdlib>
#include "../include/ShaderTypes.h"
using namespace metal;

// The shape vertex shader function.
// - Parameters:
//   - in: The vertex position data.
//   - amp_id: The index into the uniforms array used for stereoscopic views in visionOS.
//   - instance_id: The baseInstance parameter passed to the draw call used to map this instance to it's transform data.
//   - frames: The frames buffer.
//   - modelMatrix: The shape transform data
//   - color: The shape color.
[[vertex]]
VertexOut vertexShape(VertexIn in [[stage_in]],
                      ushort amp_id [[amplification_id]],
                      uint vertex_id [[vertex_id]],
                      constant Frame *frames [[ buffer(VertexBufferIndexFrames) ]],
                      constant float4x4 &modelMatrix [[buffer(VertexBufferIndexInstances)]],
                      constant float4 &color [[buffer(VertexBufferIndexColors)]]) {
    VertexOut out;
    const Frame frame = frames[0];
    const Camera camera = frame.cameras[amp_id];
    float4x4 viewMatrix = camera.viewMatrix;
    float4x4 projectionMatrix = camera.projectionMatrix;
    float4x4 modelViewProjectionMatrix = projectionMatrix * viewMatrix * modelMatrix;

    // Position
    out.position = modelViewProjectionMatrix * in.position;

    // Color
    out.color = color;

    return out;
}

// The shape fragment shader function.
// - Parameters:
//   - in: the data passed from the vertex function.
[[fragment]]
float4 fragmentShape(VertexOut in [[stage_in]]) {
    return in.color;
}
