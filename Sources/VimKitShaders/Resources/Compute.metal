//
//  Compute.metal
//
//
//  Created by Kevin McKee
//
#include <metal_stdlib>
#include "../include/ShaderTypes.h"
using namespace metal;

// Computes the vertex normals.
// See: https://iquilezles.org/articles/normals/
// See: https://computergraphics.stackexchange.com/questions/4031/programmatically-generating-vertex-normals
// - Parameters:
//   - positions: The pointer to the positions.
//   - indices: The pointer to the indices.
//   - faceNormals: The pointer to the face normals that will be updated with computed values.
//   - normals: The pointer to the normals that will be updated with the computed values.
//   - positionsCount: The count of positions.
//   - indicesCount: The count of indices.
kernel void computeVertexNormals(device const float *positions,
                                 device const uint32_t *indices,
                                 device float3 *faceNormals,
                                 device float *normals,
                                 constant int &positionsCount,
                                 constant int &indicesCount) {
    
    const int verticesCount = positionsCount / 3;
    
    // 1) Calculate the face normals
    for (int i = 0; i < indicesCount; i += 3) {
        int j = indices[i] * 3;
        const float3 a = float3(positions[j], positions[j+1], positions[j+2]);
        j = indices[i+1] * 3;
        const float3 b = float3(positions[j], positions[j+1], positions[j+2]);
        j = indices[i+2] * 3;
        const float3 c = float3(positions[j], positions[j+1], positions[j+2]);
        const float3 crossProduct = cross(b - a, c - a);
        faceNormals[indices[i]] += crossProduct;
        faceNormals[indices[i+1]] += crossProduct;
        faceNormals[indices[i+2]] += crossProduct;
    }

    // 2) Calculate the vertex normals
    for (int i = 0; i < verticesCount; i++) {
        int j = i * 3;
        const float3 n = normalize(faceNormals[i]);
        normals[j] = n.x;
        normals[j+1] = n.y;
        normals[j+2] = n.z;
    }
}

// Computes the bounding boxes for all of the instances.
// - Parameters:
//   - positions: The pointer to the positions data.
//   - indices: The pointer to the indices data.
//   - instances: The pointer to the instances data.
//   - meshes: The pointer to the mesh data.
//   - submeshes: The pointer to the submesh data.
//   - count: The total number of instances.
kernel void computeBoundingBoxes(device const float *positions,
                                 device const uint32_t *indices,
                                 device Instance *instances,
                                 device const Mesh *meshes,
                                 device const Submesh *submeshes,
                                 constant int &count) {
    
    // Loop through all of the instances
    for (int i = 0; i < count; i++) {

        bool firstPass = true;

        const Instance instance = instances[i];
        const float4x4 transform = instance.matrix;
        
        thread float3 minBounds = float3(0, 0, 0);
        thread float3 maxBounds = float3(0, 0, 0);
        
        const Mesh mesh = meshes[instance.mesh];
        const BoundedRange submeshRange = mesh.submeshes;
        
        // Loop through the submesh vertices to find the min + max bounds
        for (int j = (int)submeshRange.lowerBound; j < (int)submeshRange.upperBound; j++) {

            const Submesh submesh = submeshes[j];
            const BoundedRange range = submesh.indices;
            
            for (int k = (int)range.lowerBound; k < (int)range.upperBound; k++) {
                
                const int index = indices[k] * 3;

                const float x = positions[index];
                const float y = positions[index+1];
                const float z = positions[index+2];

                const float4 position = float4(x, y, z, 1.0);
                const float4 worldPostion = transform * position;

                if (firstPass) {
                    minBounds = worldPostion.xyz;
                    maxBounds = worldPostion.xyz;
                    firstPass = false;
                }
                
                minBounds = min(minBounds, worldPostion.xyz);
                maxBounds = max(maxBounds, worldPostion.xyz);
            }
            
            instances[i].minBounds = minBounds;
            instances[i].maxBounds = maxBounds;

        }
    }
}

// Encodes the buffers and adds draw commands via indirect command buffer.
kernel void encodeIndirectCommands(uint index [[thread_position_in_grid]],
                                   constant float *positions [[buffer(KernelBufferIndexPositions)]],
                                   constant float *normals [[buffer(KernelBufferIndexNormals)]],
                                   constant uint32_t *indexBuffer [[buffer(KernelBufferIndexIndexBuffer)]],
                                   constant UniformsArray &uniformsArray [[buffer(KernelBufferIndexUniforms)]],
                                   constant Instance *instances [[buffer(KernelBufferIndexInstances)]],
                                   constant InstancedMesh *instancedMeshes [[buffer(KernelBufferIndexInstancedMeshes)]],
                                   constant Mesh *meshes [[buffer(KernelBufferIndexMeshes)]],
                                   constant Submesh *submeshes [[buffer(KernelBufferIndexSubmeshes)]],
                                   constant Material *materials [[buffer(KernelBufferIndexMaterials)]],
                                   constant float4 *colors [[buffer(KernelBufferIndexColors)]],
                                   constant Identifiers &identifiers [[buffer(KernelBufferIndexIdentifiers)]],
                                   constant RenderOptions &options [[buffer(KernelBufferIndexRenderOptions)]],
                                   constant uint64_t *visibilityResults [[buffer(KernelBufferIndexVisibilityResults)]],
                                   device ICBContainer *icbContainer [[buffer(KernelBufferIndexCommandBufferContainer)]]) {
    
    
    // Check the visibility result
    uint64_t visibilityResult = visibilityResults[index];
    bool visible = visibilityResult != 0;

    // If visible, set the buffers and add draw commands
    if (visible) {

        const InstancedMesh instancedMesh = instancedMeshes[index];
        const Mesh mesh = meshes[instancedMesh.mesh];
        const BoundedRange submeshRange = mesh.submeshes;
        
        // Get indirect render commnd from the indirect command buffer
        render_command cmd(icbContainer->commandBuffer, index);
        
        // Encode the buffers
        cmd.set_vertex_buffer(positions, VertexBufferIndexPositions);
        cmd.set_vertex_buffer(normals, VertexBufferIndexNormals);
        cmd.set_vertex_buffer(instances, VertexBufferIndexInstances);
        cmd.set_vertex_buffer(meshes, VertexBufferIndexMeshes);
        cmd.set_vertex_buffer(submeshes, VertexBufferIndexSubmeshes);
        cmd.set_vertex_buffer(materials, VertexBufferIndexMaterials);
        cmd.set_vertex_buffer(colors, VertexBufferIndexColors);
        
        // TODO: Encode the Identifiers
        
        // TODO: Encode the Fragment Buffers

        // Loop through the submeshes and execute the draw calls
        for (int i = (int)submeshRange.lowerBound; i < (int)submeshRange.upperBound; i++) {
            const Submesh submesh = submeshes[i];
            const BoundedRange indexRange = submesh.indices;
            const uint indexCount = (uint)indexRange.upperBound - (uint)indexRange.lowerBound;
            
            // Execute the draw call
            cmd.draw_indexed_primitives(primitive_type::triangle,
                                        indexCount,
                                        indexBuffer,
                                        instancedMesh.instanceCount,
                                        0,
                                        instancedMesh.baseInstance);
        }
    }

    // If not visible, no draw command will be sent
}
