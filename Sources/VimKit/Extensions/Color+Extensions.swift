//
//  Color+Extensions.swift
//
//
//  Created by Kevin McKee
//

import Metal
import SwiftUI

extension Color {

    /// Represents the default object selection color.
    /// Note: This should go away in the future and should be able to initialized via a
    /// `ColorResource` with `.init(.objectSection)`.
    /// See: https://forums.swift.org/t/generate-images-and-colors-inside-a-swift-package/65674/9
    public static let objectSelectionColor = Color("objectSelectionColor", bundle: .module)


    /// A constant for the sky bue color.
    public static let skyBlueColor = Color("skyBlueColor", bundle: .module)

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
    /// - Parameter resource: the color resource
    init(_ resource: ColorResource) {
        let color = Color(resource)
        let channels = color.channels
        self.init(channels.x, channels.y, channels.z, channels.w)
    }
}
