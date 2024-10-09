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
//   - meshes: The meshes pointer.
//   - submeshes: The submeshes pointer.
//   - materials: The materials pointer.
//   - identifiers: The identifier data the holds the mesh and submesh indices that are currently being rendered.
vertex VertexOut vertexVisibilityTest(VertexIn in [[stage_in]],
                            ushort amp_id [[amplification_id]],
                            uint vertex_id [[vertex_id]],
                            uint instance_id [[instance_id]],
                            constant UniformsArray &uniformsArray [[buffer(VertexBufferIndexUniforms)]],
                            constant Instance *instances [[buffer(VertexBufferIndexInstances)]],
                            constant Mesh *meshes [[buffer(VertexBufferIndexMeshes)]],
                            constant Submesh *submeshes [[buffer(VertexBufferIndexSubmeshes)]],
                            constant Material *materials [[buffer(VertexBufferIndexMaterials)]]) {

    VertexOut out;
    const Instance instance = instances[instance_id];
    
    const Mesh mesh = meshes[instance.mesh];
    const BoundedRange submeshRange = mesh.submeshes;
    
    bool firstPass = true;
    float4 color = float4(0, 0, 0, 1.0);
    
    // Loop through the submeshes to find the lowest alpha value
    for (int i = (int)submeshRange.lowerBound; i < (int)submeshRange.upperBound; i++) {
        const Submesh submesh = submeshes[i];
        const Material material = materials[submesh.material];
        if (firstPass) {
            color = material.rgba;
            firstPass = false;
        }
        color.w = min(color.w, material.rgba.w);
    }
    color.w *= 0.5;
    
    Uniforms uniforms = uniformsArray.uniforms[amp_id];

    float4x4 modelMatrix = instance.matrix;
    float3 center = (instance.maxBounds + instance.minBounds) * 0.5;
    float3 extents = instance.maxBounds - instance.minBounds;
    modelMatrix.columns[0] = float4(extents.x, 0.0, 0.0, 0.0);
    modelMatrix.columns[1] = float4(0.0, extents.y, 0.0, 0.0);
    modelMatrix.columns[2] = float4(0.0, 0.0, extents.z, 0.0);
    modelMatrix.columns[3] = float4(center, 1.0);
    
    float4x4 viewMatrix = uniforms.viewMatrix;
    float4x4 projectionMatrix = uniforms.projectionMatrix;
    float4x4 modelViewProjectionMatrix = projectionMatrix * viewMatrix * modelMatrix;

    // Position
    out.position = modelViewProjectionMatrix * in.position;
    // Color
    out.color = color;
    
    switch (instance.state) {
        case InstanceStateDefault:
            break;
        case InstanceStateHidden:
            out.color = float4(0, 0, 0, 0);
            break;
        case InstanceStateSelected:
            break;
    }

    return out;
}

// Extracts the six frustum planes determined by the provided matrix.
// - Parameters:
//   - matrix: the camera projectionMatrix * viewMatrix
//   - planes: the planes pointer to write to
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
