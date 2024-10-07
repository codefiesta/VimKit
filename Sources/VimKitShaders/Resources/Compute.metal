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
                                 device const Instance *instances,
                                 device const Mesh *meshes,
                                 device const Submesh *submeshes,
                                 constant int &count) {
    
    for (int i = 0; i < count; i++) {

        bool first = true;

        Instance instance = instances[i];
        float4x4 transform = instance.matrix;
        float3 minBounds = instance.minBounds;
        float3 maxBounds = instance.maxBounds;
        
        if (instance.mesh == -1) { continue; }
        
        Mesh mesh = meshes[instance.mesh];
        BoundedRange submeshRange = mesh.submeshes;
        
        // Loop through the submesh vertices to find the min + max bounds
        for (uint j = submeshRange.lowerBound; j < submeshRange.upperBound; j++) {

            Submesh submesh = submeshes[j];
            BoundedRange indicesRange = submesh.indices;
            
            for (uint k = indicesRange.lowerBound; k < indicesRange.upperBound; k++) {
                uint index = indices[k] * 3;

                float x = positions[index];
                float y = positions[index+1];
                float z = positions[index+2];

                float4 position = float4(x, y, z, 1.0);
                float4 worldPostion = transform * position;

                if (first) {
                    minBounds = worldPostion.xyz;
                    maxBounds = worldPostion.xyz;
                }

                minBounds = min(minBounds, worldPostion.xyz);
                maxBounds = max(maxBounds, worldPostion.xyz);
                
                first = false;
            }
        }
        
        instance.minBounds = minBounds;
        instance.maxBounds = maxBounds;
    }
}
