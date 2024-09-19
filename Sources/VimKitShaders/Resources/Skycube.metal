//
//  Skycube.metal
//
//
//  Created by Kevin McKee
//

#include <metal_stdlib>
#include "../include/ShaderTypes.h"

using namespace metal;

// The struct that is passed to the vertex function
typedef struct {
    float4 position [[attribute(VertexAttributePosition)]];
} SkyCubeIn;

// The struct that is passed from the vertex function to the fragment function
typedef struct {
    // The position of the vertex
    float4 position [[position]];
    // The material color
    float4 color;
    // The texture coordinates
    float3 textureCoordinates;
    // The instance index (-1 indicates a non-selectable or invalid instance)
    int32_t index;
} SkyCubeOut;

// The struct that is returned from the fragment function
typedef struct {
    // The colorAttachments[0] that holds the color information
    float4 color [[color(0)]];
    // The colorAttachments[1] that holds the instance index (-1 indicates a non-selectable or invalid instance)
    int32_t index [[color(1)]];
} ColorOut;

// The skycube vertex shader function.
// - Parameters:
//   - in: The vertex position data.
//   - amp_id: The index into the uniforms array used for stereoscopic views in visionOS.
//   - uniformsArray: The per frame uniforms.
vertex SkyCubeOut vertexSkycube(SkyCubeIn in [[stage_in]],
                                ushort amp_id [[amplification_id]],
                                constant UniformsArray &uniformsArray [[ buffer(BufferIndexUniforms) ]]) {
    
    Uniforms uniforms = uniformsArray.uniforms[amp_id];
    float4x4 projectionMatrix = uniforms.projectionMatrix;

    float4x4 viewMatrix = uniforms.viewMatrix;
    viewMatrix[3] = float4(0, 0, 0, 1);

    // Use the sceneTransform as the model matrix as most scenes are z-up
    float4x4 modelViewProjectionMatrix = projectionMatrix * viewMatrix * uniforms.sceneTransform;
    
    SkyCubeOut out;
    float4 position = (modelViewProjectionMatrix * in.position).xyww;
    out.position = position;
    out.textureCoordinates = in.position.xyz;
    out.index = -1; // Denotes an invalid selection
    return out;
}

// The skycube fragment shader function.
// - Parameters:
//   - in: the data passed from the vertex function.
//   - cubeTexture: the cube texture.
//   - colorSampler: The color sampler.
fragment ColorOut fragmentSkycube(SkyCubeOut in [[stage_in]],
                                  texturecube<float> cubeTexture [[texture(0)]],
                                  sampler colorSampler [[sampler(0)]]) {
    ColorOut out;
    float4 color = cubeTexture.sample(colorSampler, in.textureCoordinates);
    out.color = color;
    out.index = in.index;
    return out;
}
