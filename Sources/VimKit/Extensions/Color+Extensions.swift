//
//  Color+Extensions.swift
//
//
//  Created by Kevin McKee
//

import Metal
import SwiftUI

extension Color {

    /// Provides a convenience var for accessing the color channels
    var channels: SIMD4<Float> {
        let resolved = resolve(in: .init())
        return [resolved.red, resolved.green, resolved.blue, resolved.opacity]
    }

    /// Returns a MTLClearColor equivalent of this color.
    public var mtlClearColor: MTLClearColor {
        let c = channels
        return MTLClearColor(red: Double(c.x), green: Double(c.y), blue: Double(c.z), alpha: Double(c.w))
    }
}

extension SIMD4 where Scalar == Float {

    /// Initialize rgba values from a color resource.
    init(_ resource: ColorResource) {
        let color = Color(resource)
        let channels = color.channels
        self.init(channels.x, channels.y, channels.z, channels.w)
    }
}
