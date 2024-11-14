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

constant float3 lightDirection = float3(0.25, -0.5, 1);
constant float lightIntensity = 125.0;
constant float4 lightColor = float4(0.55, 0.55, 0.4, 1.0);
constant float4 materialAmbientColor = float4(0.04, 0.04, 0.04, 1.0);
constant float4 materialSpecularColor = float4(1.0, 1.0, 1.0, 1.0);

// The main vertex shader function.
// - Parameters:
//   - in: The vertex position + normal data.
//   - amp_id: The index into the uniforms array used for stereoscopic views in visionOS.
//   - instance_id: The baseInstance parameter passed to the draw call used to map this instance to it's transform data.
//   - frames: The frames buffer.
//   - instances: The instances pointer.
//   - submeshes: The submeshes pointer.
//   - materials: The materials pointer.
//   - colors: The colors pointer used to apply custom color profiles to instances.
vertex VertexOut vertexMain(VertexIn in [[stage_in]],
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
    

    float4x4 modelMatrix = instance.matrix;
    float4x4 viewMatrix = camera.viewMatrix;
    float4x4 projectionMatrix = camera.projectionMatrix;
    float4x4 modelViewProjectionMatrix = projectionMatrix * viewMatrix * modelMatrix;
    float4x4 modelViewMatrix = viewMatrix * modelMatrix;

    // Position
    out.position = modelViewProjectionMatrix * in.position;
    
    // Pass color information to the fragment shader
    float3 normal = in.normal.xyz;
    out.glossiness = material.glossiness;
    out.smoothness = material.smoothness;
    out.color = material.rgba;
    
    // XRay the object
    if (frame.xRay) {
        float grayscale = 0.299 * material.rgba.x + 0.587 * material.rgba.y + 0.114 * material.rgba.z;
        float alpha = material.rgba.w * 0.1;
        out.color = float4(grayscale, grayscale, grayscale, alpha);
    }
        
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

    // Pass lighting information to the fragment shader
    out.cameraNormal = (normalize(modelViewMatrix * float4(normal, 0))).xyz;
    out.cameraDirection = float3(0, 0, 0) - (modelViewMatrix * in.position).xyz;
    out.cameraLightDirection = (viewMatrix * float4(normalize(lightDirection), 0)).xyz;
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
fragment FragmentOut fragmentMain(VertexOut in [[stage_in]],
                                  texture2d<float, access::sample> texture [[texture(0)]],
                                  sampler colorSampler [[sampler(0)]]) {

    // If the color alpha is zero, discard the fragment
    if (in.color.w == 0.0) {
        discard_fragment();
    }

    FragmentOut out;
    float4 materialPureColor = in.color * 0.66;
    
    float3 normal = normalize(in.cameraNormal);
    float3 light1 = normalize(in.cameraLightDirection);
    float3 light2 = normalize(float3(0, 0, 0));
    
    float lightDot1 = saturate(dot(normal, light1));
    float lightDot2 = saturate(dot(normal, light2));
    
    float4 directionalLight = lightColor * lightDot1 * in.color;
    float4 pointLight = (lightColor * min(lightIntensity / sqrt(in.cameraDistance), 0.7)) * lightDot2 * in.color;
    float4 diffuseColor = directionalLight + pointLight + materialPureColor;
    
    // Shininess
    float4 specularColor = 0.0;
    if (in.glossiness > 90) {
        float3 e = normalize(in.cameraDirection);
        float3 r = -light1 + 2.0 * lightDot1 * normal;
        float3 r2 = -light1 + 2.0 * lightDot2 * normal;
        float e_dot_r = saturate(dot(e, r));
        float e_dot_r2 = saturate(dot(e, r2));
        float shine = in.glossiness;
        // combine 2 lights
        specularColor = materialSpecularColor * lightColor * pow(e_dot_r, shine) + materialSpecularColor * (lightColor * lightIntensity / in.cameraDistance) * pow(e_dot_r2, shine) * 0.5;
    }

    float4 color = float4(materialAmbientColor + diffuseColor + specularColor);
    color.a = in.color.a;
    
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
