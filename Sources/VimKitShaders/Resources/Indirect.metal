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
//   - indexBuffer: The pointer to the index buffer.
//   - uniformsArray: The per frame uniforms.
//   - instances: The instances pointer.
//   - instancedMeshes: The instanced meshes pointer.
//   - meshes: The meshes pointer.
//   - submeshes: The submeshes pointer.
//   - materials: The materials pointer.
//   - colors: The colors pointer.
//   - options: The frame rendering options.
//   - options: The frame rendering options.
//   - visibilityResults: The object visibility results.
//   - icbContainer: The pointer to the indirect command buffer container.
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
                                   constant RenderOptions &options [[buffer(KernelBufferIndexRenderOptions)]],
                                   constant uint64_t *visibilityResults [[buffer(KernelBufferIndexVisibilityResults)]],
                                   device ICBContainer *icbContainer [[buffer(KernelBufferIndexCommandBufferContainer)]]) {
    
    // Check the visibility result
    uint64_t visibilityResult = visibilityResults[index];
    bool visible = visibilityResult == (size_t)0;

    // If visible, set the buffers and add draw commands
    if (visible) {

        const InstancedMesh instancedMesh = instancedMeshes[index];
        const Mesh mesh = meshes[instancedMesh.mesh];
        const BoundedRange submeshRange = mesh.submeshes;
        
        // Get indirect render commnd from the indirect command buffer
        render_command cmd(icbContainer->commandBuffer, index);
        
        // Encode the buffers
        cmd.set_vertex_buffer(&uniformsArray, VertexBufferIndexUniforms);
        cmd.set_vertex_buffer(positions, VertexBufferIndexPositions);
        cmd.set_vertex_buffer(normals, VertexBufferIndexNormals);
        cmd.set_vertex_buffer(instances, VertexBufferIndexInstances);
        cmd.set_vertex_buffer(materials, VertexBufferIndexMaterials);
        cmd.set_vertex_buffer(colors, VertexBufferIndexColors);
        cmd.set_vertex_buffer(&options, VertexBufferIndexRenderOptions);
        
        // TODO: Encode the Fragment Buffers

        // Loop through the submeshes and execute the draw calls
        for (int i = (int)submeshRange.lowerBound; i < (int)submeshRange.upperBound; i++) {
            const Submesh submesh = submeshes[i];
            const BoundedRange indexRange = submesh.indices;
            const uint indexCount = (uint)indexRange.upperBound - (uint)indexRange.lowerBound;
            const uint indexBufferOffset = indexRange.lowerBound;

            if (submesh.material != (size_t)-1) {
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

