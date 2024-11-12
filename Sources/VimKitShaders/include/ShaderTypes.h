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

typedef struct {
    // The lower bounds of the range
    size_t lowerBound;
    // The upper bounds of the range
    size_t upperBound;
} BoundedRange;

typedef struct {
    // The material glossiness in the domain of [0.0...0.1]
    float glossiness;
    // The material smoothness in the domain of [0.0...0.1]
    float smoothness;
    // The material RGBA diffuse color with components in the domain of [0.0...0.1]
    simd_float4 rgba;
} Material;

typedef struct {
    // The material index (-1 indicates no material)
    size_t material;
    // The range of values in the index buffer to define the geometry of its triangular faces in local space.
    BoundedRange indices;
} Submesh;

typedef struct {
    // The range of submeshes contained inside this mesh.
    BoundedRange submeshes;
} Mesh;

// A struct that holds per frame camera data
typedef struct {
    simd_float3 position;
    simd_float4x4 viewMatrix;
    simd_float4x4 projectionMatrix;
    simd_float4x4 sceneTransform;
    simd_float4 frustumPlanes[6];
} Camera;

// A struct that holds per frame data
typedef struct {
    // Provides an array of cameras for rendering stereoscopic views
    Camera cameras[2];
    // The screen viewport size
    simd_float2 viewportSize;
    // Flag indicating if this frame is being rendered in xray mode.
    bool xRay;
} Frame;

// Enum constants for possible instance states
typedef NS_ENUM(EnumBackingType, InstanceState) {
    InstanceStateDefault = 0,
    InstanceStateHidden = 1,
    InstanceStateSelected = 2,
};

// Instance
typedef struct {
    // The index of the instance.
    size_t index;
    // The index of the color override to use from the colors buffer (-1 indicates no override)
    size_t colorIndex;
    // The 4x4 row-major matrix representing the node's world-space transform.
    simd_float4x4 matrix;
    // The state of the instance
    InstanceState state;
    // The instance min bounds (in world space)
    simd_float3 minBounds;
    // The instance max bounds (in world space)
    simd_float3 maxBounds;
    // The parent index of the instance (-1 indicates no parent).
    size_t parent;
    // The mesh index (-1 indicates no mesh)
    size_t mesh;
    // Flag indicating if this instance is transparent or not.
    bool transparent;
} Instance;

// Inverts the relationship between an Instance and a Mesh that allows us to draw using instancing.
typedef struct {
    // The mesh index that is shared across the instances.
    size_t mesh;
    // Flag indicating if the mesh is transparent or not (used primarily for sorting).
    bool transparent;
    // The number of instances that share this mesh.
    size_t instanceCount;
    // The offset used by the GPU used to lookup the starting index into the instances buffer.
    size_t baseInstance;
} InstancedMesh;

// Enum constants for the association of a specific buffer index argument passed into the shader vertex function
typedef NS_ENUM(EnumBackingType, VertexBufferIndex) {
    VertexBufferIndexPositions = 0,
    VertexBufferIndexNormals = 1,
    VertexBufferIndexFrames = 2,
    VertexBufferIndexInstances = 3,
    VertexBufferIndexMeshes = 4,
    VertexBufferIndexSubmeshes = 5,
    VertexBufferIndexMaterials = 6,
    VertexBufferIndexColors = 7,
};

// Enum constants for the attribute index of an incoming vertex
typedef NS_ENUM(EnumBackingType, VertexAttribute) {
    VertexAttributePosition = 0,
    VertexAttributeNormal = 1,
    VertexAttributeUv = 2
};

// Enum constants for kernel compute function buffer indices
typedef NS_ENUM(EnumBackingType, KernelBufferIndex) {
    KernelBufferIndexPositions = 0,
    KernelBufferIndexNormals = 1,
    KernelBufferIndexIndexBuffer = 2,
    KernelBufferIndexFrames = 3,
    KernelBufferIndexInstances = 4,
    KernelBufferIndexInstancedMeshes = 5,
    KernelBufferIndexMeshes = 6,
    KernelBufferIndexSubmeshes = 7,
    KernelBufferIndexMaterials = 8,
    KernelBufferIndexColors = 9,
    KernelBufferIndexCommandBufferContainer = 10,
    KernelBufferIndexRasterizationRateMapData = 11,
    KernelBufferIndexDepthPyramidSize = 12
};

// Enum constants for argument buffer indices
typedef NS_ENUM(EnumBackingType, ArgumentBufferIndex) {
    ArgumentBufferIndexCommandBuffer = 0,
    ArgumentBufferIndexCommandBufferDepthOnly = 1
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

// Struct that contains everything required for encoding commands on the GPU.
typedef struct {
    // The default command buffer
    command_buffer commandBuffer [[id(ArgumentBufferIndexCommandBuffer)]];
    command_buffer commandBufferDepthOnly [[id(ArgumentBufferIndexCommandBufferDepthOnly)]];
} ICBContainer;

#endif

#endif /* ShaderTypes_h */

