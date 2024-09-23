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
    float3 position [[attribute(VertexAttributePosition)]];
    // Used for lighting calculations (such as Phong shading)
    float3 normal [[attribute(VertexAttributeNormal)]];
} Vertex;

// The struct that is passed from the vertex function to the fragment function
typedef struct {
    // The position of the vertex
    float4 position [[position]];
    // The normal from the perspective of the camera
    float3 cameraNormal;
    // The directional vector from the perspective of the camera
    float3 cameraDirection;
    // The direction of the light from the position of the camera
    float3 cameraLightDirection;
    // The distance from camera to the vertex
    float cameraDistance;
    // The material color
    float4 color;
    // The material glossiness
    float glossiness;
    // The material smoothness
    float smoothness;
    // The instance index (-1 indicates a non-selectable or invalid instance)
    int32_t index;
} VertexOut;

// The struct that is returned from the fragment function
typedef struct {
    // The colorAttachments[0] that holds the color information
    float4 color [[color(0)]];
    // The colorAttachments[1] that holds the instance index (-1 indicates a non-selectable or invalid instance)
    int32_t index [[color(1)]];
} ColorOut;

// The main vertex shader function.
// - Parameters:
//   - in: The vertex position + normal data.
//   - amp_id: The index into the uniforms array used for stereoscopic views in visionOS.
//   - instance_id: The baseInstance parameter passed to the draw call used to map this instance to it's transform data.
//   - uniformsArray: The per frame uniforms.
//   - meshUniforms: The per mesh uniforms.
//   - instances: The instances pointer.
//   - colors: The colors pointer used to apply custom color profiles to instances.
//   - xRay: Flag indicating if this frame is being rendered in xray mode.
vertex VertexOut vertexMain(Vertex in [[stage_in]],
                            ushort amp_id [[amplification_id]],
                            uint vertex_id [[vertex_id]],
                            uint instance_id [[instance_id]],
                            constant UniformsArray &uniformsArray [[buffer(VertexBufferIndexUniforms)]],
                            constant MeshUniforms &meshUniforms [[buffer(VertexBufferIndexMeshUniforms)]],
                            constant Instances *instances [[buffer(VertexBufferIndexInstances)]],
                            constant float4 *colors [[buffer(VertexBufferIndexColors)]],
                            constant bool &xRay [[buffer(VertexBufferIndexXRay)]]) {

    VertexOut out;
    Instances instance = instances[instance_id];
    uint instanceIndex = instance.index;
    int colorIndex = instance.colorIndex;
    
    Uniforms uniforms = uniformsArray.uniforms[amp_id];

    float4x4 modelMatrix = instance.matrix;
    float4x4 viewMatrix = uniforms.viewMatrix;
    float4x4 projectionMatrix = uniforms.projectionMatrix;
    float4x4 modelViewProjectionMatrix = projectionMatrix * viewMatrix * modelMatrix;
    float4x4 modelViewMatrix = viewMatrix * modelMatrix;

    // Position
    float4 position = float4(in.position, 1.0);
    out.position = modelViewProjectionMatrix * position;
    
    // Pass color information to the fragment shader
    float3 normal = in.normal.xyz;
    out.glossiness = meshUniforms.glossiness;
    out.smoothness = meshUniforms.smoothness;
    out.color = meshUniforms.color;
    
    // XRay the object
    if (xRay) {
        float grayscale = 0.299 * meshUniforms.color.x + 0.587 * meshUniforms.color.y + 0.114 * meshUniforms.color.z;
        float alpha = meshUniforms.color.w * 0.1;
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
            out.position = float4(0, 0, 0, 0);
            out.color = float4(0, 0, 0, 0);
            break;
        case InstanceStateSelected:
            out.color = colors[0];
            break;
    }

    // Pass lighting information to the fragment shader
    out.cameraNormal = (normalize(modelViewMatrix * float4(normal, 0))).xyz;
    out.cameraDirection = float3(0, 0, 0) - (modelViewMatrix * position).xyz;
    out.cameraLightDirection = (viewMatrix * float4(normalize(lightDirection), 0)).xyz;
    out.cameraDistance = length_squared((modelMatrix * position).xyz - uniforms.cameraPosition);

    // Pass the instance index
    out.index = instanceIndex;
    return out;
}

// The main fragment shader function.
// - Parameters:
//   - in: the data passed from the vertex function.
//   - texture: the texture.
//   - colorSampler: The color sampler.
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
    out.index = in.index;
    
    return out;
}



