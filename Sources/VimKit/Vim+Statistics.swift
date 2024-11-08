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

        /// The average latency
        public var averageLatency: Double = .zero

        /// The max latency
        public var maxLatency: Double = .zero

        /// The range of draw commands that have been executed in the GPU.
        public var executionRange: MTLIndirectCommandBufferExecutionRange = .init()

        /// The range of commands that have been executed on the CPU.
        public var commandRange: MTLIndirectCommandBufferExecutionRange = .init()

        /// Public initializer.
        public init() {}

        /// Resets the statistics.
        mutating func reset() {
            averageLatency = .zero
            maxLatency = .zero
            executionRange = .init()
            commandRange = .init()
        }
    }
}
