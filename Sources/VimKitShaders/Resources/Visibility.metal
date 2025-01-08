//
//  Visibility.metal
//  VimKit
//
//  Created by Kevin McKee
//

#include <metal_stdlib>
#include "../include/ShaderTypes.h"

using namespace metal;

// The vertex visibility test shader function.
// - Parameters:
//   - in: The vertex position + normal data.
//   - amp_id: The index into the uniforms array used for stereoscopic views in visionOS.
//   - instance_id: The baseInstance parameter passed to the draw call used to map this instance to it's transform data.
//   - frames: The frames buffer.
//   - instances: The instances pointer.
//   - materials: The materials pointer.
//   - identifiers: The identifier data the holds the mesh and submesh indices that are currently being rendered.
[[vertex]]
VertexOut vertexVisibilityTest(VertexIn in [[stage_in]],
                               ushort amp_id [[amplification_id]],
                               uint vertex_id [[vertex_id]],
                               uint instance_id [[instance_id]],
                               constant Frame *frames [[buffer(VertexBufferIndexFrames)]],
                               constant Instance *instances [[buffer(VertexBufferIndexInstances)]],
                               constant Material *materials [[buffer(VertexBufferIndexMaterials)]]) {

    VertexOut out;
    const Instance instance = instances[instance_id];
    const Material material = materials[0];
    const Camera camera = frames[0].cameras[amp_id];
    
    float4x4 modelMatrix = instance.matrix;
    float4x4 viewMatrix = camera.viewMatrix;
    float4x4 projectionMatrix = camera.projectionMatrix;
    float4x4 modelViewProjectionMatrix = projectionMatrix * viewMatrix * modelMatrix;

    // Position
    out.position = modelViewProjectionMatrix * in.position;
    out.glossiness = material.glossiness;
    out.smoothness = material.smoothness;

    // Color
    out.color = material.rgba;
    
    return out;
}
