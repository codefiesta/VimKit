//
//  Shaders.metal
//  VimViewer
//
//  Created by Kevin McKee
//

#include <metal_stdlib>
#include <simd/simd.h>
#include "../include/ShaderTypes.h"

using namespace metal;

// The main vertex shader function.
// - Parameters:
//   - in: The vertex position + normal data.
//   - amp_id: The index into the uniforms array used for stereoscopic views in visionOS.
//   - vertex_id: The per-vertex identifier.
//   - instance_id: The baseInstance parameter passed to the draw call used to map this instance to it's transform data.
//   - frames: The frames buffer.
//   - instances: The instances pointer.
//   - materials: The materials pointer.
//   - colors: The colors pointer used to apply custom color profiles to instances.
[[vertex]]
VertexOut vertexMain(VertexIn in [[stage_in]],
                     ushort amp_id [[amplification_id]],
                     uint vertex_id [[vertex_id]],
                     uint instance_id [[instance_id]],
                     constant Frame *frames [[buffer(VertexBufferIndexFrames)]],
                     constant Instance *instances [[buffer(VertexBufferIndexInstances)]],
                     constant Material *materials [[buffer(VertexBufferIndexMaterials)]],
                     constant float4 *colors [[buffer(VertexBufferIndexColors)]]) {

    VertexOut out;
    const Instance instance = instances[instance_id];
    const Material material = materials[0];
    const Frame frame = frames[0];
    const Camera camera = frame.cameras[amp_id];

    uint instanceIndex = instance.index;
    int colorIndex = instance.colorIndex;
    
    // Matrices
    float4x4 modelMatrix = instance.matrix;
    float4x4 viewMatrix = camera.viewMatrix;
    float4x4 projectionMatrix = camera.projectionMatrix;
    float4x4 modelViewProjectionMatrix = projectionMatrix * viewMatrix * modelMatrix;
    float4x4 modelViewMatrix = viewMatrix * modelMatrix;
    float3x3 normalMatrix = float3x3(modelMatrix.columns[0].xyz, modelMatrix.columns[1].xyz, modelMatrix.columns[2].xyz);

    // Position
    float4 worldPosition = modelMatrix * in.position;
    out.position = modelViewProjectionMatrix * in.position;
    out.worldPosition = worldPosition.xyz / worldPosition.w;
    
    // Normal
    float3 normal = in.normal.xyz;
    out.worldNormal = normalMatrix * normal;
    
    // Color
    out.glossiness = material.glossiness;
    out.smoothness = material.smoothness;
    out.color = material.rgba;
    
    // Lights
    out.lightCount = frame.lightCount;
    
    // XRay the object
    if (frame.xRay) {
        float grayscale = 0.299 * material.rgba.x + 0.587 * material.rgba.y + 0.114 * material.rgba.z;
        float alpha = material.rgba.w * 0.1;
        out.color = float4(grayscale, grayscale, grayscale, alpha);
    }
    
    // Instance state
    switch (instance.state) {
        case InstanceStateDefault:
            // If the color override is set, pluck the color from the colors buffer
            if (colorIndex > 0) {
                out.color = colors[colorIndex];
            }
            break;
        case InstanceStateHidden:
            out.color = float4(0, 0, 0, 0);
            break;
        case InstanceStateSelected:
            out.color = colors[0];
            break;
    }
    
    // Clip Planes
    if (frame.enableClipPlanes) {
        
        // Check the valid clip planes
        for (int i = 0; i < 6; i++) {
            const float4 plane = camera.clipPlanes[i];

            // Validate clip plane by making sure the w isn't infinite
            if (isinf(plane.w)) {
                out.clipDistance[i] = 0.0f;
                continue;
            }
            // Calculate the distance to the clip plane
            const float clipDistance = (dot(plane.xyz, worldPosition.xyz) + plane.w);
            out.clipDistance[i] = clipDistance;
        }
    } else {
        out.clipDistance[0] = 0.0f;
        out.clipDistance[1] = 0.0f;
        out.clipDistance[2] = 0.0f;
        out.clipDistance[3] = 0.0f;
        out.clipDistance[4] = 0.0f;
        out.clipDistance[5] = 0.0f;
    }
    
    // Camera
    out.cameraPosition = camera.position;
    out.cameraDirection = float3(0, 0, 0) - (modelViewMatrix * in.position).xyz;
    out.cameraDistance = length_squared((modelMatrix * in.position).xyz - camera.position);
    
    // Pass the instance index
    out.index = instanceIndex;

    return out;
}

// The main fragment shader function.
// - Parameters:
//   - in: the data passed from the vertex function.
//   - texture: the texture.
//   - colorSampler: The color sampler.
[[fragment]]
FragmentOut fragmentMain(FragmentIn in [[stage_in]],
                         constant Light *lights [[buffer(FragmentBufferIndexLights)]],
                         texture2d<float, access::sample> texture [[texture(0)]],
                         sampler colorSampler [[sampler(0)]]) {

    float4 baseColor = in.color;
    float glossiness = in.glossiness;
    float3 cameraPosition = in.cameraPosition;
    float3 cameraDirection = in.cameraDirection;
    float cameraDistance = in.cameraDistance;

    
    FragmentOut out;
    
    // Discard the fragment if the color alpha is zero or the vertex is clipped
    if (baseColor.w == 0.0) {
        discard_fragment();
        return out;
    }
    
    float3 normal = normalize(in.worldNormal);
    float3 position = in.worldPosition;
    uint lightCount = in.lightCount;

    // Calculate the vertex color with the phong lighting function
    float4 color = phongLighting(position,
                                 normal,
                                 baseColor,
                                 glossiness,
                                 cameraPosition,
                                 cameraDirection,
                                 cameraDistance,
                                 lightCount,
                                 lights);
    
    out.color = color;
    out.index = in.index;
    
    return out;
}

// Provides a simple vertex shader for transforming the array of provided vertices.
vertex VertexOut vertexDepthOnly(VertexIn in [[stage_in]],
                                 ushort amp_id [[amplification_id]],
                                 uint vertex_id [[vertex_id]],
                                 const device float3 * positions [[buffer(VertexBufferIndexPositions)]],
                                 constant Frame *frames [[buffer(VertexBufferIndexFrames)]]) {
    VertexOut out;
    const Frame frame = frames[0];
    const Camera camera = frame.cameras[amp_id];
    float4x4 viewMatrix = camera.viewMatrix;
    float4x4 projectionMatrix = camera.projectionMatrix;
    float4x4 viewProjectionMatrix = projectionMatrix * viewMatrix;

    // Position
    out.position = viewProjectionMatrix * float4(positions[vertex_id], 1.0f);
    return out;
}
