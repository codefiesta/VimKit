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
//   - normal: The vertex normal.
//   - position: The vertex position.
//   - instance_id: The baseInstance parameter passed to the draw call used to map this instance to it's transform data.
float4 phongLighting(float3 position,
                     float3 normal,
                     float4 baseColor,
                     float glossiness,
                     float3 cameraPosition,
                     float3 cameraDirection,
                     float cameraDistance,
                     constant Light *lights) {
    
    const float3 rgb = baseColor.xyz;
    const float alpha = baseColor.w;

    float3 diffuseColor = float3(0, 0, 0);
    float3 ambientColor = float3(0, 0, 0);
    float3 specularColor = float3(0, 0, 0);

    float3 materialSpecularColor = float3(1, 1, 1);
    
    // SunLight
    Light light = lights[0];

    float3 lightDirection = normalize(-light.position);
    float diffuseIntensity = saturate(-dot(lightDirection, normal));
    
    diffuseColor += rgb * light.color * diffuseIntensity;
    
    if (diffuseIntensity > 0) {
        float3 reflection = reflect(lightDirection, normal);
        float3 viewDirection = normalize(cameraDirection);
        float specularIntensity = pow(saturate(dot(reflection, viewDirection)), glossiness);
        specularColor += rgb * light.specularColor * materialSpecularColor * specularIntensity;
    }

    // AmbientLight
    light = lights[1];
    ambientColor += light.color * rgb;
    

//    for (uint i = 0; i < 1; i++) {
//
//        const Light light = lights[i];
//
//        switch (light.type) {
//            case LightTypeSun:
//                {
//                    float3 lightDirection = normalize(-light.position);
//                    float diffuseIntensity = saturate(-dot(lightDirection, normal));
//                    
//                    diffuseColor += light.color * rgb * diffuseIntensity;
//                    
//                    if (diffuseIntensity > 0) {
//                        float3 reflection = reflect(lightDirection, normal);
//                        float3 viewDirection = normalize(cameraPosition);
//                        float specularIntensity = pow(saturate(dot(reflection, viewDirection)), glossiness);
//                        specularColor += light.specularColor * materialSpecularColor * specularIntensity;
//                    }
//                }
//                break;
//            case LightTypeSpot:
//                {
//                    const float3 worldPosition = position.xyz;
//                    float d = distance(light.position, worldPosition);
//                    float3 lightDirection = normalize(light.position - worldPosition);
//                    float3 coneDirection = normalize(light.coneDirection);
//                    float spotResult = dot(lightDirection, -coneDirection);
//                    
//                    if (spotResult > cos(light.coneAngle)) {
//                        float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);
//                        attenuation *= pow(spotResult, light.coneAttenuation);
//                        float diffuseIntensity = saturate(dot(lightDirection, normal));
//                        float3 color = light.color * rgb * diffuseIntensity;
//                        color *= attenuation;
//                        diffuseColor += color;
//                    }
//                }
//                break;
//            case LightTypePoint:
//                {
//                    const float3 worldPosition = position.xyz;
//                    float d = distance(light.position, worldPosition);
//                    float3 lightDirection = normalize(light.position - worldPosition);
//                    float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);
//                    
//                    float diffuseIntensity = saturate(dot(lightDirection, normal));
//                    float3 color = light.color * rgb * diffuseIntensity;
//                    color *= attenuation;
//                    diffuseColor += color;
//                }
//                break;
//            case LightTypeAmbient:
//                {
//                    ambientColor += light.color;
//                }
//                break;
//        }
//    }
    
    float3 result = ambientColor + diffuseColor + specularColor;
    return float4(result, alpha);
}
