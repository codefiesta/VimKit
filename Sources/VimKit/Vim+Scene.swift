//
//  Vim+Scene.swift
//
//
//  Created by Kevin McKee
//

import Foundation

extension Vim {

    /// Holds observable scene settings.
    public class Scene: ObservableObject {

        /// Haze in the sky. 0 is a clear - 1 spreads the sun’s color
        @Published
        public var turbidity: Float = 1.0
        /// How high the sun is in the sky. 0.5 is on the horizon. 1.0 is overhead.
        @Published
        public var sunElevation: Float = 0.75
        /// Atmospheric scattering influences the color of the sky from reddish through orange tones to the sky at midday.
        @Published
        public var upperAtmosphereScattering: Float = 0.75
        /// How clear the sky is. 0 is clear, 10 can produce intense colors. It’s best to keep turbidity and upper atmosphere scattering low if high albedo.
        @Published
        public var groundAlbedo: Float = 0.1
    }

}
