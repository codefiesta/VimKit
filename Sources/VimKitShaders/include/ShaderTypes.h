//
//  ShaderTypes.h
//
//
//  Created by Kevin McKee
//

//  Header containing types and enums shared between Metal shaders and Swift

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

#endif /* ShaderTypes_h */
