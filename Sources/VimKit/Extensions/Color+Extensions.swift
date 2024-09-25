//
//  Color+Extensions.swift
//
//
//  Created by Kevin McKee
//

import Metal
import SwiftUI

extension Color {

    /// Represents the default object selection color
    public static let objectSelectionColor = Color("objectSelectionColor", bundle: .module)

    /// Represents the sky blue color
    public static let skyBlue = Color("skyBlueColor", bundle: .module)

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
