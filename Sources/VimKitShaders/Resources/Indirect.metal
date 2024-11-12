//
//  Indirect.metal
//  VimKit
//
//  Created by Kevin McKee
//

#include <metal_stdlib>
#include "../include/ShaderTypes.h"
using namespace metal;

// Encodes the buffers and adds draw commands via indirect command buffer.
// - Parameters:
//   - index: The thread position in the grid being executed.
//   - positions: The pointer to the positions.
//   - normals: The pointer to the normals.
//   - indexBuffer: The pointer to the index buffer.
//   - frames: The pointer to the frames buffer.
//   - instances: The instances pointer.
//   - instancedMeshes: The instanced meshes pointer.
//   - meshes: The meshes pointer.
//   - submeshes: The submeshes pointer.
//   - materials: The materials pointer.
//   - colors: The colors pointer.
//   - options: The frame rendering options.
//   - icbContainer: The pointer to the indirect command buffer container.
//   - rasterRateMapData: The raster data map.
//   - depthPyramidTexture: The depth texture.
kernel void encodeIndirectCommands(uint index [[thread_position_in_grid]],
                                   constant float *positions [[buffer(KernelBufferIndexPositions)]],
                                   constant float *normals [[buffer(KernelBufferIndexNormals)]],
                                   constant uint32_t *indexBuffer [[buffer(KernelBufferIndexIndexBuffer)]],
                                   constant Frame *frames [[buffer(KernelBufferIndexFrames)]],
                                   constant Instance *instances [[buffer(KernelBufferIndexInstances)]],
                                   constant InstancedMesh *instancedMeshes [[buffer(KernelBufferIndexInstancedMeshes)]],
                                   constant Mesh *meshes [[buffer(KernelBufferIndexMeshes)]],
                                   constant Submesh *submeshes [[buffer(KernelBufferIndexSubmeshes)]],
                                   constant Material *materials [[buffer(KernelBufferIndexMaterials)]],
                                   constant float4 *colors [[buffer(KernelBufferIndexColors)]],
                                   device ICBContainer *icbContainer [[buffer(KernelBufferIndexCommandBufferContainer)]],
                                   constant rasterization_rate_map_data *rasterRateMapData [[buffer(KernelBufferIndexRasterizationRateMapData)]],
                                   texture2d<float> depthPyramidTexture [[texture(0)]]) {
    
    // TODO: Check depth
    bool visible = true;

    // If visible, set the buffers and add draw commands
    if (visible) {

        const InstancedMesh instancedMesh = instancedMeshes[index];
        const Mesh mesh = meshes[instancedMesh.mesh];
        const BoundedRange submeshRange = mesh.submeshes;
        
        // Get indirect render commnd from the indirect command buffer
        render_command cmd(icbContainer->commandBuffer, index);
        
        // Encode the buffers
        cmd.set_vertex_buffer(frames, VertexBufferIndexFrames);
        cmd.set_vertex_buffer(positions, VertexBufferIndexPositions);
        cmd.set_vertex_buffer(normals, VertexBufferIndexNormals);
        cmd.set_vertex_buffer(instances, VertexBufferIndexInstances);
        cmd.set_vertex_buffer(materials, VertexBufferIndexMaterials);
        cmd.set_vertex_buffer(colors, VertexBufferIndexColors);
        
        // TODO: Encode the Fragment Buffers

        // Loop through the submeshes and execute the draw calls
        for (int i = (int)submeshRange.lowerBound; i < (int)submeshRange.upperBound; i++) {
            const Submesh submesh = submeshes[i];
            const BoundedRange indexRange = submesh.indices;
            const uint indexCount = (uint)indexRange.upperBound - (uint)indexRange.lowerBound;
            const uint indexBufferOffset = indexRange.lowerBound;

            if (submesh.material >= 0) {
                // Offet the material
                cmd.set_vertex_buffer(materials + submesh.material, VertexBufferIndexMaterials);
            }
            
            // Execute the draw call
            cmd.draw_indexed_primitives(primitive_type::triangle,
                                        indexCount,
                                        indexBuffer + indexBufferOffset,
                                        instancedMesh.instanceCount,
                                        0,
                                        instancedMesh.baseInstance);

        }
    }

    // If not visible, no draw command will be sent
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
