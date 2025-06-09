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
//   - corners: The instance bounding box corners.
// - Returns: true if the instance is inside the view frustum, otherwise false
__attribute__((always_inline))
static bool isInsideViewFrustumAndClipPlanes(const Camera camera,
                                             const Instance instance,
                                             const float4 corners[8]) {
    
    
    if (instance.state == InstanceStateHidden) { return false; }

    // Loop through the frustum + clip planes and check the box corners
    for (int i = 0; i < 6; i++) {

        const float4 frustumPlane = camera.frustumPlanes[i];
        
        if (dot(frustumPlane, corners[0]) < 0 &&
            dot(frustumPlane, corners[1]) < 0 &&
            dot(frustumPlane, corners[2]) < 0 &&
            dot(frustumPlane, corners[3]) < 0 &&
            dot(frustumPlane, corners[4]) < 0 &&
            dot(frustumPlane, corners[5]) < 0 &&
            dot(frustumPlane, corners[6]) < 0 &&
            dot(frustumPlane, corners[7]) < 0) {
            // Not visible - all corners returned negative
            return false;
        }
        
        const float4 clipPlane = camera.clipPlanes[i];
        const float3 planeNormal = normalize(clipPlane.xyz);
        
        // Skip the plane if it's not valid
        if (isinf(clipPlane.w)) { continue; }

        if (-dot(planeNormal, corners[0].xyz) + clipPlane.w < 0 &&
            -dot(planeNormal, corners[1].xyz) + clipPlane.w < 0 &&
            -dot(planeNormal, corners[2].xyz) + clipPlane.w < 0 &&
            -dot(planeNormal, corners[3].xyz) + clipPlane.w < 0 &&
            -dot(planeNormal, corners[4].xyz) + clipPlane.w < 0 &&
            -dot(planeNormal, corners[5].xyz) + clipPlane.w < 0 &&
            -dot(planeNormal, corners[6].xyz) + clipPlane.w < 0 &&
            -dot(planeNormal, corners[7].xyz) + clipPlane.w < 0) {
            // Not visible - all corners returned negative
            return false;
        }
    }
    return true;
}

// Calculates the texture coordinates for the specified position.
// - Parameters:
//   - frame: The per frame data.
//   - position: The position.
__attribute__((always_inline))
static float2 textureCoordinates(const Frame frame,
                                 const float4 position) {
    float2 clip = position.xy / position.w;
    float2 screenCoords = clip * 0.5f + 0.5f;
    return screenCoords * frame.viewportSize;
}

// Checks if the instance is visible by performing contribution and depth testing.
// - Parameters:
//   - camera: The per frame data.
//   - instance: The instance to check.
//   - corners: The instance bounding box corners.
//   - textureSize: The texture size.
//   - textureSampler: The texture sampler.
//   - depthTexture: The depth texture.
// - Returns: true if the instance passes the contribution & depth test
__attribute__((always_inline))
static bool isInstanceVisible(const Frame frame,
                              const Instance instance,
                              const float4 corners[8],
                              const uint2 textureSize,
                              const sampler textureSampler,
                              depth2d<float> depthTexture) {
    
    const bool enableDepthTesting = frame.enableDepthTesting;
    const bool enableContributionTesting = frame.enableContributionTesting;
    const Camera camera = frame.cameras[0];
    
    float4x4 viewMatrix = camera.viewMatrix;
    float4x4 projectionMatrix = camera.projectionMatrix;
    float4x4 projectionViewMatrix = projectionMatrix * viewMatrix;
    
    // Contribution culling (remove instances that are too small to contribute significantly to the final image)
    if (enableContributionTesting) {

        // Transform the bounding box
        float4 minBounds = projectionViewMatrix * float4(instance.minBounds, 1.0);
        float4 maxBounds = projectionViewMatrix * float4(instance.maxBounds, 1.0);

        float3 boxMin = minBounds.xyz / minBounds.w;
        float3 boxMax = maxBounds.xyz / maxBounds.w;
        
        float length = boxMax.x - boxMin.x;
        float width = boxMax.y - boxMin.y;
        float height = boxMax.z - boxMin.z;
        float area = abs(2 * (length * width + width * height + height * length));
        
        if (area < frame.minContributionArea) {
            return false;
        }
    }
    
    // Depth z culling (eliminate instances that are behind other instances)
    if (enableDepthTesting) {
        
        for (int i = 0; i < 8; i++) {
            const float4 corner = projectionViewMatrix * corners[i];
            const float2 sampleCoords = textureCoordinates(frame, corner);
            const float depthSample = depthTexture.sample(textureSampler, sampleCoords);
            float depthValue = corner.z / corner.w;
            if (depthValue >= depthSample) {
                return true;
            }
        }
        
        return false;
    }
    
    return true;
}

// Checks if the instanced mesh is visible inside the view frustum and passes the depth test.
// - Parameters:
//   - frame: The per frame data.
//   - instancedMesh: The instanced mesh to check.
//   - instances: The instances pointer.
//   - meshes: The meshes pointer.
//   - submeshes: The submeshes pointer.
//   - textureSampler: The texture sampler.
//   - depthTexture: The depth texture.
// - Returns: true if the instanced mesh is inside the view frustum and passes the depth test
__attribute__((always_inline))
static bool isInstancedMeshVisible(const Frame frame,
                                   const InstancedMesh instancedMesh,
                                   constant Instance *instances,
                                   constant Mesh *meshes,
                                   constant Submesh *submeshes,
                                   sampler textureSampler,
                                   depth2d<float> depthTexture) {
    
    const Camera camera = frame.cameras[0]; // TODO: Stereoscopic views??

    // Get the texture size and sampler
    const uint2 textureSize = uint2(depthTexture.get_width(), depthTexture.get_height());
    
    const int lowerBound = (int) instancedMesh.baseInstance;
    const int upperBound = lowerBound + (int) instancedMesh.instanceCount;

    // Loop through the instances and check their visibility
    // If any instances are visible simply return true and allow the instancing draw call to happen
    for (int i = lowerBound; i < upperBound; i++) {
        
        const Instance instance = instances[i];
        
        // Extract the box corners
        const float4 corners[8] = {
            float4(instance.minBounds, 1.0),
            float4(instance.minBounds.x, instance.minBounds.y, instance.maxBounds.z, 1.0),
            float4(instance.minBounds.x, instance.maxBounds.y, instance.minBounds.z, 1.0),
            float4(instance.minBounds.x, instance.maxBounds.y, instance.maxBounds.z, 1.0),
            float4(instance.maxBounds.x, instance.minBounds.y, instance.minBounds.z, 1.0),
            float4(instance.maxBounds.x, instance.minBounds.y, instance.maxBounds.z, 1.0),
            float4(instance.maxBounds.x, instance.maxBounds.y, instance.minBounds.z, 1.0),
            float4(instance.maxBounds, 1.0)
        };

        const bool insideFrustum = isInsideViewFrustumAndClipPlanes(camera, instance, corners);

        if (insideFrustum) {
            // Check if the instance passes the depth & contribution test
            const bool isVisible = isInstanceVisible(frame, instance, corners, textureSize, textureSampler, depthTexture);
            if (isVisible) { return true; }
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
//   - executedCommands: The excuted commands buffer that keeps track of culling results.
//   - textureSampler: The texture sampler.
//   - depthTexture: The depth texture.
[[kernel]]
void encodeIndirectRenderCommands(uint2 threadPosition [[thread_position_in_grid]],
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
                                  device uint8_t *executedCommands [[buffer(KernelBufferIndexExecutedCommands)]],
                                  sampler textureSampler [[sampler(0)]],
                                  depth2d<float> depthTexture [[texture(0)]]) {
    
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
    bool visible = isInstancedMeshVisible(frame,
                             instancedMesh,
                             instances,
                             meshes,
                             submeshes,
                             textureSampler,
                             depthTexture);
    
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
