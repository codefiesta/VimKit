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

        /// Public initializer.
        public init() {}

        /// Resets the statistics.
        mutating func reset() {
            averageLatency = .zero
            maxLatency = .zero
        }
    }
}
