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
//   - frames: The frames buffer.
[[vertex]]
VertexOut vertexSkycube(VertexIn in [[stage_in]],
                        ushort amp_id [[amplification_id]],
                        constant Frame *frames [[buffer(VertexBufferIndexFrames)]]) {
    
    const Frame frame = frames[0];
    const Camera camera = frame.cameras[amp_id];
    float4x4 projectionMatrix = camera.projectionMatrix;

    float4x4 viewMatrix = camera.viewMatrix;
    viewMatrix[3] = float4(0, 0, 0, 1);

    // Use the sceneTransform as the model matrix as most scenes are z-up
    float4x4 modelViewProjectionMatrix = projectionMatrix * viewMatrix * camera.sceneTransform;
    
    VertexOut out;
    float4 position = (modelViewProjectionMatrix * in.position).xyww;
    out.position = position;
    out.textureCoordinates = in.position.xyz;
    out.index = -1; // Denotes an invalid selection
    
    // Don't apply any clip distances to the skycube
    for (int i = 0; i < 6; i++) {
        out.clipDistance[i] = 0.0f;
    }

    return out;
}

// The skycube fragment shader function.
// - Parameters:
//   - in: the data passed from the vertex function.
//   - cubeTexture: the cube texture.
//   - colorSampler: The color sampler.
[[fragment]]
FragmentOut fragmentSkycube(FragmentIn in [[stage_in]],
                            texturecube<float> cubeTexture [[texture(0)]],
                            sampler colorSampler [[sampler(0)]]) {
    FragmentOut out;
    float4 color = cubeTexture.sample(colorSampler, in.textureCoordinates);
    out.color = color;
    out.index = in.index;
    return out;
}
