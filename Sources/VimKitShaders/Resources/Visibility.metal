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
//   - uniformsArray: The per frame uniforms.
//   - instances: The instances pointer.
//   - materials: The materials pointer.
//   - identifiers: The identifier data the holds the mesh and submesh indices that are currently being rendered.
vertex VertexOut vertexVisibilityTest(VertexIn in [[stage_in]],
                                      ushort amp_id [[amplification_id]],
                                      uint vertex_id [[vertex_id]],
                                      uint instance_id [[instance_id]],
                                      constant UniformsArray &uniformsArray [[buffer(VertexBufferIndexUniforms)]],
                                      constant Instance *instances [[buffer(VertexBufferIndexInstances)]],
                                      constant Material *materials [[buffer(VertexBufferIndexMaterials)]]) {

    VertexOut out;
    const Instance instance = instances[instance_id];
    const Material material = materials[0];
    const Uniforms uniforms = uniformsArray.uniforms[amp_id];
    
    float4x4 modelMatrix = instance.matrix;
    float4x4 viewMatrix = uniforms.viewMatrix;
    float4x4 projectionMatrix = uniforms.projectionMatrix;
    float4x4 modelViewProjectionMatrix = projectionMatrix * viewMatrix * modelMatrix;

    // Position
    out.position = modelViewProjectionMatrix * in.position;
    // Color
    out.color = material.rgba;
    
    return out;
}

// Extracts the six frustum planes determined by the provided matrix.
// - Parameters:
//   - matrix: the camera projectionMatrix * viewMatrix
//   - planes: the planes pointer to write to
/**
static void extractFrustumPlanes(constant float4x4 &matrix, thread float4 *planes) {

    float4x4 mt = transpose(matrix);
    planes[0] = mt[3] + mt[0]; // left
    planes[1] = mt[3] - mt[0]; // right
    planes[2] = mt[3] - mt[1]; // top
    planes[3] = mt[3] + mt[1]; // bottom
    planes[4] = mt[2];         // near
    planes[5] = mt[3] - mt[2]; // far
    for (int i = 0; i < 6; ++i) {
        planes[i] /= length(planes[i].xyz);
    }
}
*/
