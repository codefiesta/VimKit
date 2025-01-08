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
[[kernel]]
void computeVertexNormals(device const float *positions,
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
//   - tid: The thread position in the grid being executed.
[[kernel]]
void computeBoundingBoxes(device const float *positions,
                          device const uint32_t *indices,
                          device Instance *instances,
                          device const Mesh *meshes,
                          device const Submesh *submeshes,
                          uint2 tid [[thread_position_in_grid]]) {
    
    const uint i = tid.x;

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
    }
    
    instances[i].minBounds = minBounds;
    instances[i].maxBounds = maxBounds;
}
