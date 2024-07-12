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
} Uniforms;

// Provides an array of uniforms for rendering stereoscopic views
typedef struct {
    Uniforms uniforms[2];
} UniformsArray;

// Instance Uniforms
typedef struct {
    int32_t identifier;
    simd_float4x4 matrix;
    simd_float4 color;
    float glossiness;
    float smoothness;
    bool xRay;
} InstanceUniforms;

// Constants for the association of a specific buffer index argument passed into the shader function
typedef NS_ENUM(EnumBackingType, BufferIndex) {
    BufferIndexPositions = 0,
    BufferIndexNormals = 1,
    BufferIndexUniforms = 2,
    BufferIndexInstanceUniforms = 3,
};

typedef NS_ENUM(EnumBackingType, VertexAttribute) {
    VertexAttributePosition = 0,
    VertexAttributeNormal = 1,
};

#endif /* ShaderTypes_h */
