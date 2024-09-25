//
//  Database+ValueTransformers.swift
//  
//
//  Created by Kevin McKee
//

import Foundation
import simd
import SwiftData

public class SIMD3FloatValueTransformer: ValueTransformer {

    static let name = NSValueTransformerName(rawValue: String(describing: SIMD3FloatValueTransformer.self))

    override public init() {
        super.init()
    }

    override public func transformedValue(_ value: Any?) -> Any? {
        guard let value = value as? String else { return nil }
        let parts = value.split(separator: ",")
        guard parts.count == 3 else { return nil }
        let x = Float(parts[0]) ?? .zero
        let y = Float(parts[1]) ?? .zero
        let z = Float(parts[2]) ?? .zero
        return SIMD3<Float>(x, y, z)
    }

    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let value = value as? SIMD3<Float> else { return nil }
        return "\(value.x),\(value.y),\(value.z)"
    }

    override public class func allowsReverseTransformation() -> Bool { true }

    public static func register() {
        ValueTransformer.setValueTransformer(SIMD3FloatValueTransformer(), forName: name)
    }
}

public class SIMD3DoubleValueTransformer: ValueTransformer {

    static let name = NSValueTransformerName(rawValue: String(describing: SIMD3DoubleValueTransformer.self))

    override public init() {
        super.init()
    }

    override public func transformedValue(_ value: Any?) -> Any? {
        guard let value = value as? String else { return nil }
        let parts = value.split(separator: ",")
        guard parts.count == 3 else { return nil }
        let x = Double(parts[0]) ?? .zero
        let y = Double(parts[1]) ?? .zero
        let z = Double(parts[2]) ?? .zero
        return SIMD3<Double>(x, y, z)
    }

    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let value = value as? SIMD3<Double> else { return nil }
        return "\(value.x),\(value.y),\(value.z)"
    }

    override public class func allowsReverseTransformation() -> Bool { true }

    public static func register() {
        ValueTransformer.setValueTransformer(SIMD3DoubleValueTransformer(), forName: name)
    }
}
