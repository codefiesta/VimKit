//
//  ShaderTypes.h
//
//
//  Created by Kevin McKee
//

#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
typedef metal::int32_t EnumBackingType;
#else
#import <Foundation/Foundation.h>
typedef NSInteger EnumBackingType;
#endif
#import <simd/simd.h>

//***********************************************************************
// SWIFT/METAL STRUCTURES THAT ARE SHARED BETWEEN METAL SHADERS AND SWIFT
//***********************************************************************

// Per Frame Uniforms
typedef struct {
    // Camera uniforms
    simd_float3 cameraPosition;
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
    simd_float4x4 sceneTransform;
} Uniforms;

// Provides an array of uniforms for rendering stereoscopic views
typedef struct {
    Uniforms uniforms[2];
} UniformsArray;

// Per Mesh Uniforms
typedef struct {
    simd_float4 color;
    float glossiness;
    float smoothness;
} MeshUniforms;

// Enum constants for possible instance states
typedef NS_ENUM(EnumBackingType, InstanceState) {
    InstanceStateDefault = 0,
    InstanceStateHidden = 1,
    InstanceStateSelected = 2,
};

// Instancing Data
typedef struct {
    // The index of the instance.
    uint32_t index;
    // The index of the color override to use from the colors buffer (-1 indicates no override)
    int32_t colorIndex;
    // The 4x4 row-major matrix representing the node's world-space transform.
    simd_float4x4 matrix;
    // The state of the instance
    InstanceState state;
} Instances;

// Enum constants for the association of a specific buffer index argument passed into the shader vertex function
typedef NS_ENUM(EnumBackingType, VertexBufferIndex) {
    VertexBufferIndexPositions = 0,
    VertexBufferIndexNormals = 1,
    VertexBufferIndexUniforms = 2,
    VertexBufferIndexMeshUniforms = 3,
    VertexBufferIndexInstances = 4,
    VertexBufferIndexColors = 5,
    VertexBufferIndexXRay = 6
};

// Enum constances for the attribute index of an incoming vertex
typedef NS_ENUM(EnumBackingType, VertexAttribute) {
    VertexAttributePosition = 0,
    VertexAttributeNormal = 1,
    VertexAttributeUv = 2
};

//***********************************************************************
// METAL ONLY STRUCTURES THAT CAN BE SHARED ACROSS METAL SHADERS
//***********************************************************************

#ifdef __METAL_VERSION__

#include <metal_stdlib>
using namespace metal;

// Describes the incoming vertex data that is sent to a shader vertex function.
typedef struct {
    float4 position [[attribute(VertexAttributePosition)]];
    float3 normal [[attribute(VertexAttributeNormal)]];
    float2 uv [[attribute(VertexAttributeUv)]];
} VertexIn;

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
    // The texture coordinates
    float3 textureCoordinates;
    // The instance index (-1 indicates a non-selectable or invalid instance)
    int32_t index;
} VertexOut;

// The struct that is returned from the fragment function
typedef struct {
    // The colorAttachments[0] that holds the color information
    float4 color [[color(0)]];
    // The colorAttachments[1] that holds the instance index (-1 indicates a non-selectable or invalid instance)
    int32_t index [[color(1)]];
} FragmentOut;

#endif

#endif /* ShaderTypes_h */

