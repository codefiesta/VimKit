//
//  Vim+Statistics.swift
//  VimKit
//
//  Created by Kevin McKee
//

import Foundation
import MetalKit

extension Vim {

    /// Holds observable rendering statistics.
    public struct Statistics {

        /// The number of instances in the model.
        public var instanceCount: Int = .zero

        /// The number of meshes in the model.
        public var meshCount: Int = .zero

        /// The number of submeshes in the model.
        public var submeshCount: Int = .zero

        /// The number of x,y,z positions (vertices) in the model.
        public var positionsCount: Int = .zero

        /// The average latency
        public var averageLatency: Double = .zero

        /// The max latency
        public var maxLatency: Double = .zero

        /// The grid size of draw commands that are being executed.
        public var gridSize: MTLSize = .zero

        /// Convenience var that returns the total number of commands being executed per frame.
        public var totalCommands: Int {
            gridSize.width * gridSize.height
        }

        /// The number of commands that were actually executed in the frame (not culled).
        public var executedCommands: Int = .zero

        /// Returns the number of commands that have been prevented from executing (culled).
        public var culledCommands: Int {
            totalCommands - executedCommands
        }

        /// The percentage of commands that have been culled.
        public var cullingPercentage: Float {
            guard totalCommands != .zero else { return .zero }
            return Float(culledCommands) / Float(totalCommands)
        }

        /// Public initializer.
        public init() {}

        /// Resets the statistics.
        mutating func reset() {
            averageLatency = .zero
            maxLatency = .zero
        }
    }
}
