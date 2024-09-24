//
//  Skycube.metal
//
//
//  Created by Kevin McKee
//

#include <metal_stdlib>
#include "../include/ShaderTypes.h"

using namespace metal;

// The skycube vertex shader function.
// - Parameters:
//   - in: The vertex position data.
//   - amp_id: The index into the uniforms array used for stereoscopic views in visionOS.
//   - uniformsArray: The per frame uniforms.
vertex VertexOut vertexSkycube(VertexIn in [[stage_in]],
                               ushort amp_id [[amplification_id]],
                               constant UniformsArray &uniformsArray [[ buffer(VertexBufferIndexUniforms) ]]) {
    
    Uniforms uniforms = uniformsArray.uniforms[amp_id];
    float4x4 projectionMatrix = uniforms.projectionMatrix;

    float4x4 viewMatrix = uniforms.viewMatrix;
    viewMatrix[3] = float4(0, 0, 0, 1);

    // Use the sceneTransform as the model matrix as most scenes are z-up
    float4x4 modelViewProjectionMatrix = projectionMatrix * viewMatrix * uniforms.sceneTransform;
    
    VertexOut out;
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
fragment FragmentOut fragmentSkycube(VertexOut in [[stage_in]],
                                  texturecube<float> cubeTexture [[texture(0)]],
                                  sampler colorSampler [[sampler(0)]]) {
    FragmentOut out;
    float4 color = cubeTexture.sample(colorSampler, in.textureCoordinates);
    out.color = color;
    out.index = in.index;
    return out;
}
