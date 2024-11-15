//
//  Indirect.metal
//  VimKit
//
//  Created by Kevin McKee
//

#include <metal_stdlib>
#include "../include/ShaderTypes.h"
using namespace metal;

// Checks if the instance is inside the view frustum.
// - Parameters:
//   - frames: The frames buffer.
//   - instance: The instance to check if inside the view frustum.
// - Returns: true if the instance is inside the view frustum, otherwise false
__attribute__((always_inline))
static bool isInsideViewFrustum(constant Frame *frames,
                                constant Instance &instance) {
    
    
    if (instance.state == InstanceStateHidden) { return false; }

    const Frame frame = frames[0];
    const Camera camera = frame.cameras[0]; // TODO: Stereoscopic views??

    const float3 minBounds = instance.minBounds;
    const float3 maxBounds = instance.maxBounds;

    // Make the array of corners
    const float4 corners[8] = {
        float4(minBounds, 1.0),
        float4(minBounds.x, minBounds.y, maxBounds.z, 1.0),
        float4(minBounds.x, maxBounds.y, minBounds.z, 1.0),
        float4(minBounds.x, maxBounds.y, maxBounds.z, 1.0),
        float4(maxBounds.x, minBounds.y, minBounds.z, 1.0),
        float4(maxBounds.x, minBounds.y, maxBounds.z, 1.0),
        float4(maxBounds.x, maxBounds.y, minBounds.z, 1.0),
        float4(maxBounds, 1.0)
    };

    // Loop through the frustum planes and check the box corners
    for (int i = 0; i < 6; i++) {

        const float4 plane = camera.frustumPlanes[i];
        
        if (dot(plane, corners[0]) < 0 &&
            dot(plane, corners[1]) < 0 &&
            dot(plane, corners[2]) < 0 &&
            dot(plane, corners[3]) < 0 &&
            dot(plane, corners[4]) < 0 &&
            dot(plane, corners[5]) < 0 &&
            dot(plane, corners[6]) < 0 &&
            dot(plane, corners[7]) < 0) {
            // Not visible - all corners returned negative
            return false;
        }
    }
    return true;
}

// Checks if the instanced mesh is visible inside the view frustum and passes the depth test.
// - Parameters:
//   - frames: The frames buffer.
//   - instancedMesh: The instanced mesh to chek.
//   - instances: The instances pointer.
//   - meshes: The meshes pointer.
//   - submeshes: The submeshes pointer.
//   - rasterRateMapData: The rasterization rate map data.
//   - depthPyramidTexture: The depth pyramid texture.
// - Returns: true if the instanced mesh is inside the view frustum and passes the depth test
__attribute__((always_inline))
static bool isVisible(constant Frame *frames,
                      constant InstancedMesh &instancedMesh,
                      constant Instance *instances,
                      constant Mesh *meshes,
                      constant Submesh *submeshes,
                      constant rasterization_rate_map_data *rasterRateMapData,
                      texture2d<float> depthPyramidTexture) {
    
    // Depth buffer culling.
    const uint2 textureSize = uint2(depthPyramidTexture.get_width(), depthPyramidTexture.get_height());

    const int lowerBound = (int) instancedMesh.baseInstance;
    const int upperBound = lowerBound + (int) instancedMesh.instanceCount;
    constexpr sampler depthSampler(filter::nearest, mip_filter::nearest, address::clamp_to_edge);

    // If any of the instances appear, simply draw the entire instanced mesh
    for (int i = lowerBound; i < upperBound; i++) {
        
        if (!isInsideViewFrustum(frames, instances[i])) { continue; }
        
        const Instance instance = instances[i];
        const float2 extents = float2(textureSize) * (instance.maxBounds.xy - instance.minBounds.xy);
        const uint lod = ceil(log2(max(extents.x, extents.y)));
        
        const uint2 lodSizeInLod0Pixels = textureSize & (0xFFFFFFFF << lod);
        const float2 lodScale = float2(textureSize) / float2(lodSizeInLod0Pixels);
        const float2 sampleLocationMin = instance.minBounds.xy * lodScale;
        const float2 sampleLocationMax = instance.maxBounds.xy * lodScale;

        const float d0 = depthPyramidTexture.sample(depthSampler,
                                                    float2(sampleLocationMin.x, sampleLocationMin.y),
                                                    level(lod)).x;

        const float d1 = depthPyramidTexture.sample(depthSampler,
                                                    float2(sampleLocationMin.x, sampleLocationMax.y),
                                                    level(lod)).x;
        
        const float d2 = depthPyramidTexture.sample(depthSampler,
                                                    float2(sampleLocationMax.x, sampleLocationMin.y),
                                                    level(lod)).x;

        const float d3 = depthPyramidTexture.sample(depthSampler,
                                                    float2(sampleLocationMax.x, sampleLocationMax.y),
                                                    level(lod)).x;

        const float compareValue = instance.minBounds.z;
        float maxDepth = max(max(d0, d1), max(d2, d3));
        
        if (compareValue >= maxDepth) {
            return true;
        }
    }
    
    return false;
}

// Encodes and draws the indexed primitives using the specified render command.
// - Parameters:
//   - cmd: The render command to use
//   - positions: The pointer to the positions.
//   - normals: The pointer to the normals.
//   - indexBuffer: The pointer to the index buffer.
//   - frames: The frames buffer.
//   - instances: The instances pointer.
//   - materials: The materials pointer.
//   - colors: The colors pointer.
//   - indexCount: The count of indexed vertices to draw.
//   - instanceCount: The count of instances to draw
//   - baseInstance: The starting index of the instances pointer.
__attribute__((always_inline))
static void encodeAndDraw(thread render_command &cmd,
                          constant float *positions [[buffer(KernelBufferIndexPositions)]],
                          constant float *normals [[buffer(KernelBufferIndexNormals)]],
                          constant uint32_t *indexBuffer [[buffer(KernelBufferIndexIndexBuffer)]],
                          constant Frame *frames [[buffer(KernelBufferIndexFrames)]],
                          constant Instance *instances [[buffer(KernelBufferIndexInstances)]],
                          constant Material *materials [[buffer(KernelBufferIndexMaterials)]],
                          constant float4 *colors [[buffer(KernelBufferIndexColors)]],
                          uint indexCount,
                          uint instanceCount,
                          uint baseInstance) {
    
    // Encode the buffers
    cmd.set_vertex_buffer(frames, VertexBufferIndexFrames);
    cmd.set_vertex_buffer(positions, VertexBufferIndexPositions);
    cmd.set_vertex_buffer(normals, VertexBufferIndexNormals);
    cmd.set_vertex_buffer(instances, VertexBufferIndexInstances);
    cmd.set_vertex_buffer(materials, VertexBufferIndexMaterials);
    cmd.set_vertex_buffer(colors, VertexBufferIndexColors);
    cmd.set_vertex_buffer(materials, VertexBufferIndexMaterials);
    
    // TODO: Encode the Fragment Buffers

    // Execute the draw call
    cmd.draw_indexed_primitives(primitive_type::triangle,
                                indexCount,
                                indexBuffer,
                                instanceCount,
                                0,
                                baseInstance);
}

// Encodes the buffers and adds draw commands via indirect command buffer.
// - Parameters:
//   - threadPosition: The thread position in the grid being executed.
//   - positions: The pointer to the positions.
//   - normals: The pointer to the normals.
//   - indexBuffer: The pointer to the index buffer.
//   - frames: The frames buffer.
//   - instances: The instances pointer.
//   - instancedMeshes: The instanced meshes pointer.
//   - meshes: The meshes pointer.
//   - submeshes: The submeshes pointer.
//   - materials: The materials pointer.
//   - colors: The colors pointer.
//   - icbContainer: The pointer to the indirect command buffer container.
//   - rasterRateMapData: The raster data map.
//   - depthPyramidTexture: The depth texture.
kernel void encodeIndirectRenderCommands(uint2 threadPosition [[thread_position_in_grid]],
                                   uint2 gridSize [[threads_per_grid]],
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
    
    // The x lane provides the max number of submeshes that the mesh can contain
    const uint x = threadPosition.x;
    // The y lane provides the index of the instanced mesh to draw
    const uint y = threadPosition.y;
    // Grab the height of the our grid size
    const uint height = gridSize.y;
    
    // Calculate the index of this position in the grid. This is used to
    // get the the render command at this unique index as only one draw call can be issued per thread.
    const uint index = y + (x * height);

    // Perform depth testing to check if the instanced mesh should be occluded or not
    bool visible = true;
//    bool visible = isVisible(frames,
//                             instancedMeshes[y],
//                             instances,
//                             meshes,
//                             submeshes,
//                             rasterRateMapData,
//                             depthPyramidTexture);
    
    // If this instanced mesh isn't visible don't issue any draw commands and simply exit
    if (!visible) {
        return;
    }

    const InstancedMesh instancedMesh = instancedMeshes[y];
    const uint instanceCount = instancedMesh.instanceCount;
    const uint baseInstance = instancedMesh.baseInstance;
    const Mesh mesh = meshes[instancedMesh.mesh];

    const BoundedRange submeshRange = mesh.submeshes;
    const uint lowerBound = (uint) submeshRange.lowerBound;
    const uint upperBound = (uint) submeshRange.upperBound;

    const uint i = x + lowerBound;

    if (i < upperBound) {

        // Get indirect render commnd from the indirect command buffer
        render_command cmd(icbContainer->commandBuffer, index);
        
        const Submesh submesh = submeshes[i];
        const BoundedRange indexRange = submesh.indices;
        const uint materialIndex = (uint) submesh.material;
        const uint indexCount = (uint)indexRange.upperBound - (uint)indexRange.lowerBound;
        const uint indexBufferOffset = indexRange.lowerBound;

        // Execute the draw call
        encodeAndDraw(cmd,
                      positions,
                      normals,
                      &indexBuffer[indexBufferOffset],
                      frames,
                      instances,
                      &materials[materialIndex],
                      colors,
                      indexCount,
                      instanceCount,
                      baseInstance);

    }
}
