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
//   - camera: The per frame camera data.
//   - instance: The instance to check if inside the view frustum.
// - Returns: true if the instance is inside the view frustum, otherwise false
__attribute__((always_inline))
static bool isInsideViewFrustum(const Camera camera,
                                const Instance instance) {
    
    
    if (instance.state == InstanceStateHidden) { return false; }

    const float3 minBounds = instance.minBounds;
    const float3 maxBounds = instance.maxBounds;

    // Extract the box corners
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

// Checks if the instance passes the depth test.
// - Parameters:
//   - camera: The per frame data.
//   - instance: The instance to check.
//   - textureSize: The texture size.
//   - depthSampler: The depth sampler.
//   - rasterRateMapData: The rasterization rate map data.
//   - depthPyramidTexture: The depth pyramid texture.
// - Returns: true if the instance passes the depth test
__attribute__((always_inline))
static bool depthTest(const Frame frame,
                      const Instance instance,
                      const uint2 textureSize,
                      const sampler depthSampler,
                      constant rasterization_rate_map_data *rasterRateMapData,
                      texture2d<float> depthPyramidTexture) {
    
    const Camera camera = frame.cameras[0];

    // Transform the bounding box
    float3 minBounds = instance.minBounds;
    float3 maxBounds = instance.maxBounds;
    
    float4x4 viewMatrix = camera.viewMatrix;
    float4x4 projectionMatrix = camera.projectionMatrix;
    float4x4 projectionViewMatrix = projectionMatrix * viewMatrix;
    
    minBounds = (projectionViewMatrix * float4(minBounds, 1.0)).xyz;
    maxBounds = (projectionViewMatrix * float4(maxBounds, 1.0)).xyz;

    // Make the raster rate map decoder
    float2 inversePhysicalSize = 1.0 / frame.physicalSize;
    rasterization_rate_map_decoder decoder(*rasterRateMapData);

    // Extract the box corners
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

    for (int i = 0; i < 8; i++) {
        
        float3 corner = corners[i].xyz;

        corner.z = max(corner.z, 0.0f);
        corner.xy = corner.xy * float2(0.5, -0.5) + 0.5;
        corner = saturate(corner);
        
        float2 screenCoordinates = corner.xy * frame.viewportSize;
        corner.xy = decoder.map_screen_to_physical_coordinates(screenCoordinates) * inversePhysicalSize;
        
        if (i == 0) {
            minBounds = corner;
            maxBounds = corner;
        }
        
        minBounds = min(minBounds, corner);
        maxBounds = max(maxBounds, corner);
    }

    // Check the depth buffer
    const float compareValue = minBounds.z;

    const float2 ext = float2(textureSize) * (maxBounds - minBounds).xy;
    const uint lod = ceil(log2(max(ext.x, ext.y)));
    
    const uint2 lodSizeInPixels = textureSize & (0xFFFFFFFF << lod);
    const float2 lodScale = float2(textureSize) / float2(lodSizeInPixels);

    // Use the min(x,y) and max(x,y) as the sample locations
    const float2 sampleMin = minBounds.xy * lodScale;
    const float2 sampleMax = maxBounds.xy * lodScale;

    // Sample the corners
    const float d0 = depthPyramidTexture.sample(depthSampler, float2(sampleMin.x, sampleMin.y), level(lod)).x;
    const float d1 = depthPyramidTexture.sample(depthSampler, float2(sampleMin.x, sampleMax.y), level(lod)).x;
    const float d2 = depthPyramidTexture.sample(depthSampler, float2(sampleMax.x, sampleMin.y), level(lod)).x;
    const float d3 = depthPyramidTexture.sample(depthSampler, float2(sampleMax.x, sampleMax.y), level(lod)).x;

    // Determine the max depth
    float maxDepth = max(max(d0, d1), max(d2, d3));
    
    return compareValue >= maxDepth;
}

// Checks if the instanced mesh is visible inside the view frustum and passes the depth test.
// - Parameters:
//   - frame: The per frame data.
//   - instancedMesh: The instanced mesh to check.
//   - instances: The instances pointer.
//   - meshes: The meshes pointer.
//   - submeshes: The submeshes pointer.
//   - rasterRateMapData: The rasterization rate map data.
//   - depthPyramidTexture: The depth pyramid texture.
// - Returns: true if the instanced mesh is inside the view frustum and passes the depth test
__attribute__((always_inline))
static bool isVisible(const Frame frame,
                      const InstancedMesh instancedMesh,
                      constant Instance *instances,
                      constant Mesh *meshes,
                      constant Submesh *submeshes,
                      constant rasterization_rate_map_data *rasterRateMapData,
                      texture2d<float> depthPyramidTexture) {

    const bool performDepthTest = frame.enableDepthTesting;
    
    const Camera camera = frame.cameras[0]; // TODO: Stereoscopic views??

    // Get the texture size and sampler
    const uint2 textureSize = uint2(depthPyramidTexture.get_width(), depthPyramidTexture.get_height());
    constexpr sampler depthSampler(filter::nearest, mip_filter::nearest, address::clamp_to_edge);

    const int lowerBound = (int) instancedMesh.baseInstance;
    const int upperBound = lowerBound + (int) instancedMesh.instanceCount;

    // Loop through the instances and check their visibility
    // If any instances are visible simply return true and allow the instancing draw call to happen
    for (int i = lowerBound; i < upperBound; i++) {
        
        const Instance instance = instances[i];

        // Check if inside the view frustum
        if (isInsideViewFrustum(camera, instance)) {
            // If depth testing is enabled, check if the instance passes the depth test
            if (performDepthTest) {
                return depthTest(frame, instance, textureSize, depthSampler, rasterRateMapData, depthPyramidTexture);
            }
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
                          constant float *positions,
                          constant float *normals,
                          constant uint32_t *indexBuffer,
                          constant Frame *frames,
                          constant Light *lights,
                          constant Instance *instances,
                          constant Material *materials,
                          constant float4 *colors,
                          uint indexCount,
                          uint instanceCount,
                          uint baseInstance) {
    
    // Encode the vertex buffers
    cmd.set_vertex_buffer(frames, VertexBufferIndexFrames);
    cmd.set_vertex_buffer(positions, VertexBufferIndexPositions);
    cmd.set_vertex_buffer(normals, VertexBufferIndexNormals);
    cmd.set_vertex_buffer(instances, VertexBufferIndexInstances);
    cmd.set_vertex_buffer(materials, VertexBufferIndexMaterials);
    cmd.set_vertex_buffer(colors, VertexBufferIndexColors);
    cmd.set_vertex_buffer(materials, VertexBufferIndexMaterials);
    
    // Encode the fragment buffers
    cmd.set_fragment_buffer(lights, FragmentBufferIndexLights);

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
//   - lights: The lights buffer.
//   - instances: The instances pointer.
//   - instancedMeshes: The instanced meshes pointer.
//   - meshes: The meshes pointer.
//   - submeshes: The submeshes pointer.
//   - materials: The materials pointer.
//   - colors: The colors pointer.
//   - icbContainer: The pointer to the indirect command buffer container.
//   - executedCommands: The excuted commands buffer that keeps track of culling.
//   - rasterRateMapData: The raster data map.
//   - depthPyramidTexture: The depth texture.
kernel void encodeIndirectRenderCommands(uint2 threadPosition [[thread_position_in_grid]],
                                         uint2 gridSize [[threads_per_grid]],
                                         constant float *positions [[buffer(KernelBufferIndexPositions)]],
                                         constant float *normals [[buffer(KernelBufferIndexNormals)]],
                                         constant uint32_t *indexBuffer [[buffer(KernelBufferIndexIndexBuffer)]],
                                         constant Frame *frames [[buffer(KernelBufferIndexFrames)]],
                                         constant Light *lights [[buffer(KernelBufferIndexLights)]],
                                         constant Instance *instances [[buffer(KernelBufferIndexInstances)]],
                                         constant InstancedMesh *instancedMeshes [[buffer(KernelBufferIndexInstancedMeshes)]],
                                         constant Mesh *meshes [[buffer(KernelBufferIndexMeshes)]],
                                         constant Submesh *submeshes [[buffer(KernelBufferIndexSubmeshes)]],
                                         constant Material *materials [[buffer(KernelBufferIndexMaterials)]],
                                         constant float4 *colors [[buffer(KernelBufferIndexColors)]],
                                         device ICBContainer *icbContainer [[buffer(KernelBufferIndexCommandBufferContainer)]],
                                         device uint8_t * executedCommands [[buffer(KernelBufferIndexExecutedCommands)]],
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
    
    const InstancedMesh instancedMesh = instancedMeshes[y];
    const Frame frame = frames[0];

    // Perform depth testing to check if the instanced mesh should be occluded or not
    bool visible = isVisible(frame,
                             instancedMesh,
                             instances,
                             meshes,
                             submeshes,
                             rasterRateMapData,
                             depthPyramidTexture);
    
    // If this instanced mesh isn't visible don't issue any draw commands and simply exit
    if (!visible) {
        // Mark the command as not being executed
        executedCommands[index] = 0;
        return;
    }

    // Mark the command as being executed
    executedCommands[index] = 1;
    
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
                      lights,
                      instances,
                      &materials[materialIndex],
                      colors,
                      indexCount,
                      instanceCount,
                      baseInstance);

    }
}
