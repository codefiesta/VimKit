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

constant float3 lightDirection = float3(0.22, .33, 1);
constant float lightIntensity = 125.0;
constant float4 lightColor = float4(0.55, 0.55, 0.4, 1.0);
constant float4 materialAmbientColor = float4(0.04, 0.04, 0.04, 1.0);
constant float4 materialSpecularColor = float4(1.0, 1.0, 1.0, 1.0);

// The struct that is passed to the vertex function
typedef struct {
    // 3D coordinates representing a position in space
    simd_float3 position [[attribute(VertexAttributePosition)]];
    // Used for lighting calculations (such as Phong shading)
    float3 normal [[attribute(VertexAttributeNormal)]];
} Vertex;

// The struct that is passed from the vertex function to the fragment function
typedef struct {
    // The position of the vertex
    simd_float4 position [[position]];
    // The normal from the perspective of the camera
    simd_float3 cameraNormal;
    // The directional vector from the perspective of the camera
    simd_float3 cameraDirection;
    // The direction of the light from the position of the camera
    simd_float3 cameraLightDirection;
    // The distance from camera to the vertex
    float cameraDistance;
    // The material color
    simd_float4 color;
    // The material glossiness
    float glossiness;
    // The material smoothness
    float smoothness;
    // The instance identifier
    int32_t identifier;
} VertexOut;

// The struct that is returned from the fragment function
typedef struct {
    // The colorAttachments[0] that holds the color information
    float4 color [[color(0)]];
    // The colorAttachments[1] that holds the instance identifier (-1 indicates an invalid instance)
    int32_t identifier [[color(1)]];
} ColorOut;

// The main vertex shader function
vertex VertexOut vertexMain(Vertex in [[stage_in]],
                            constant UniformsArray &uniformsArray [[ buffer(BufferIndexUniforms) ]],
                            constant InstanceUniforms &instanceUniforms [[ buffer(BufferIndexInstanceUniforms) ]],
                            uint vertex_id [[vertex_id]],
                            ushort amp_id [[amplification_id]]) {
    VertexOut out;
    Uniforms uniforms = uniformsArray.uniforms[amp_id];
    
    simd_float4x4 modelMatrix = instanceUniforms.matrix;
    simd_float4x4 viewMatrix = uniforms.viewMatrix;
    simd_float4x4 projectionMatrix = uniforms.projectionMatrix;
    simd_float4x4 modelViewProjectionMatrix = projectionMatrix * viewMatrix * modelMatrix;
    simd_float4x4 modelViewMatrix = viewMatrix * modelMatrix;

    // Position
    float4 position = float4(in.position, 1.0);
    out.position = modelViewProjectionMatrix * position;
    
    
    // Pass color information to the fragment shader
    float3 normal = in.normal.xyz;
    out.glossiness = instanceUniforms.glossiness;
    out.smoothness = instanceUniforms.smoothness;
    out.color = instanceUniforms.color;

    // XRay the object
    if (instanceUniforms.xRay) {
        float grayscale = 0.299 * instanceUniforms.color.x + 0.587 * instanceUniforms.color.y + 0.114 * instanceUniforms.color.z;
        float alpha = instanceUniforms.color.w * 0.1;
        out.color = float4(grayscale, grayscale, grayscale, alpha);
    }

    // Pass lighting information to the fragment shader
    out.cameraNormal = (normalize(modelViewMatrix * float4(normal, 0))).xyz;
    out.cameraDirection = float3(0, 0, 0) - (modelViewMatrix * position).xyz;
    out.cameraLightDirection = (viewMatrix * float4(normalize(lightDirection), 0)).xyz;
    out.cameraDistance = length_squared((modelMatrix * position).xyz - uniforms.cameraPosition);

    // Pass the instance id
    out.identifier = instanceUniforms.identifier;
    return out;
}

// The primary fragment shader function that includes the texture
fragment ColorOut fragmentMain(VertexOut in [[stage_in]],
                              texture2d<float, access::sample> texture [[texture(0)]],
                              sampler colorSampler [[sampler(0)]]) {

    ColorOut out;
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
    out.identifier = in.identifier;
    
    return out;
}



