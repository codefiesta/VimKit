//
//  LayerRenderer+Extensions.swift
//  
//
//  Created by Kevin McKee
//

#if canImport(CompositorServices)
import CompositorServices
import VimKit

extension LayerRenderer.Clock.Instant.Duration {

    var timeInterval: TimeInterval {
        let nanoseconds = TimeInterval(components.attoseconds / 1_000_000_000)
        return TimeInterval(components.seconds) + (nanoseconds / TimeInterval(NSEC_PER_SEC))
    }
}

#endif
