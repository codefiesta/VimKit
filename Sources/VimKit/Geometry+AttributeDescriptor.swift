//
//  Geometry+AttributeDescriptor.swift
//  VimKit
//
//  Created by Kevin McKee
//

import Foundation

extension Geometry {

    /// Every attribute descriptor has a one to one mapping to a string representation similar to a URN:
    /// `g3d:<association>:<semantic>:<index>:<data_type>:<data_arity>`
    /// See: https://github.com/vimaec/g3d/#attribute-descriptor-string
    public struct AttributeDescriptor: Decodable {

        enum DataType: String, Decodable {
            case int8
            case int16
            case int32
            case int64
            case uint8
            case uint16
            case uint32
            case uint64
            case float32
            case float64

            // Returns the byte size of the data type
            var size: Int {
                switch self {
                case .int8, .uint8:
                    return MemoryLayout<Int8>.size
                case .int16, .uint16:
                    return MemoryLayout<Int16>.size
                case .int32, .uint32:
                    return MemoryLayout<Int32>.size
                case .int64, .uint64:
                    return MemoryLayout<Int64>.size
                case .float32:
                    return MemoryLayout<Float32>.size
                case .float64:
                    return MemoryLayout<Float64>.size
                }
            }
        }

        /// Describes what part of the incoming geometry is associated with.
        enum Association: String, Decodable {
            case vertex
            case face
            case corner
            case edge
            case subgeometry
            case instance
            case shapevertex
            case shape
            case material
            case mesh
            case submesh
            case all
            case none
        }

        /// The semantic is used to identify what role the attribute has when parsing.
        enum Semantic: String, Decodable {
            case position // vertex buffer
            case index // index buffer
            case indexoffset // an offset into the index buffer (used with groups and with faces)
            case vertexoffset // the offset into the vertex buffer (used only with groups, and must have offset.)
            case submeshoffset
            case normal // computed normal information (per face, group, corner, or vertex)
            case binormal // computed binormal information
            case tangent // computed tangent information
            case material
            case materialid // material id
            case visibility
            case size  // number of indices per face or group
            case uv
            case color // usually vertex color, but could be edge color as well
            case smoothing
            case weight
            case mapchannel
            case id
            case joint
            case boxes // used to identify bounding boxes
            case spheres  // used to identify bounding spheres
            case transform
            case parent
            case mesh
            case width
            case glossiness
            case smoothness
            case user
            case flags
            case unknown
        }

        let association: Association
        let semantic: Semantic
        let index: Int
        let dataType: DataType
        let arity: Int

        /// Initializer.
        /// - Parameter value: the raw attribute string that is parsed to build the descriptor.
        init?(_ value: String) {
            let parts = value.split(separator: ":").map { String($0) }
            assert(parts.count == 6, "Invalid attribute descriptor")
            guard let association = Association(rawValue: parts[1]),
                  let semantic = Semantic(rawValue: parts[2]),
                  let index = Int(parts[3]),
                  let dataType = DataType(rawValue: parts[4]),
                  let arity = Int(parts[5]) else { return nil }
            self.association = association
            self.semantic = semantic
            self.index = index
            self.dataType = dataType
            self.arity = arity
        }
    }
}
