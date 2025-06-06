//
//  File.metal
//  VimKit
//
//  Created by Kevin McKee
//

#include <metal_stdlib>
#include <simd/simd.h>
#include "../include/ShaderTypes.h"

using namespace metal;

// The main phong lighting function.
// - Parameters:
//   - position: The vertex world position.
//   - normal: The vertex world normal.
//   - baseColor: The vertex base color
//   - glossiness: The glossiness (shine)
//   - cameraPosition: The camera position
//   - cameraDirection: The camera forward direction
//   - cameraDistance: The distance from the vertex to the camera position
//   - lightCount: The number of lights contained inside the light buffer
//   - lights: The scene lights
float4 phongLighting(float3 position,
                     float3 normal,
                     float4 baseColor,
                     float glossiness,
                     float3 cameraPosition,
                     float3 cameraDirection,
                     float cameraDistance,
                     uint lightCount,
                     constant Light *lights) {
    
    const float3 rgb = baseColor.xyz;
    const float alpha = baseColor.w;

    float3 diffuseColor = float3(0, 0, 0);
    float3 ambientColor = float3(0, 0, 0);
    float3 specularColor = float3(0, 0, 0);

    float3 materialSpecularColor = float3(1, 1, 1);
    
    // Loop through the lights and merge the lights
    for (uint i = 0; i < lightCount; i++) {

        const Light light = lights[i];

        switch (light.lightType) {
            case LightTypeSun:
                {
                    float3 lightDirection = normalize(-light.position);
                    float diffuseIntensity = saturate(-dot(lightDirection, normal));
                    
                    diffuseColor += light.color * rgb * diffuseIntensity;
                    
                    if (diffuseIntensity > 0) {
                        float3 reflection = reflect(lightDirection, normal);
                        float3 viewDirection = normalize(cameraPosition);
                        float specularIntensity = pow(saturate(dot(reflection, viewDirection)), glossiness);
                        specularColor += light.color * rgb * materialSpecularColor * specularIntensity;
                    }
                }
                break;
            case LightTypeSpot:
                {
                    const float3 worldPosition = position.xyz;
                    float d = distance(light.position, worldPosition);
                    float3 lightDirection = normalize(light.position - worldPosition);
                    float3 coneDirection = normalize(light.coneDirection);
                    float spotResult = dot(lightDirection, -coneDirection);
                    
                    if (spotResult > cos(light.coneAngle)) {
                        float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);
                        attenuation *= pow(spotResult, light.coneAttenuation);
                        float diffuseIntensity = saturate(dot(lightDirection, normal));
                        float3 color = light.color * rgb * diffuseIntensity;
                        color *= attenuation;
                        diffuseColor += color;
                    }
                }
                break;
            case LightTypePoint:
                {
                    const float3 worldPosition = position.xyz;
                    float d = distance(light.position, worldPosition);
                    float3 lightDirection = normalize(light.position - worldPosition);
                    float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);
                    
                    float diffuseIntensity = saturate(dot(lightDirection, normal));
                    float3 color = light.color * rgb * diffuseIntensity;
                    color *= attenuation;
                    diffuseColor += color;
                }
                break;
            case LightTypeAmbient:
                {
                    ambientColor += light.color * rgb;
                }
                break;
        }
    }
    
    float3 result = ambientColor + diffuseColor + specularColor;
    return float4(result, alpha);
}
