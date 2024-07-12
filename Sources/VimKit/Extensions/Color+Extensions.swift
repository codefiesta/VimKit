//
//  Color+Extensions.swift
//
//
//  Created by Kevin McKee
//

import SwiftUI

extension Color {

    /// Represents the default object selection color
    static let objectSelectionColor = Color("objectSelectionColor", bundle: Bundle.module)

    /// Provides a convenience var for accessing the color channels
    var channels: SIMD4<Float> {
        let resolved = resolve(in: .init())
        return [resolved.red, resolved.green, resolved.blue, resolved.opacity]
    }
}
