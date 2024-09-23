//
//  Vim+Options.swift
//
//
//  Created by Kevin McKee
//

import Foundation

extension Vim {

    /// Holds observable rendering options.
    //public class Options: ObservableObject {
    public struct Options {

        /// A bool used to specify whether wireframing or fill mode should be applied while rendering.
        public var wireFrame: Bool = false

        /// A bool used to specify whether xray mode should be applied or not.
        public var xRay: Bool = false

        /// Haze in the sky. 0 is a clear - 1 spreads the sun’s color
        public var turbidity: Float = 1.0

        /// How high the sun is in the sky. 0.5 is on the horizon. 1.0 is overhead.
        public var sunElevation: Float = 0.75

        /// Atmospheric scattering influences the color of the sky from reddish through orange tones to the sky at midday.
        public var upperAtmosphereScattering: Float = 0.75

        /// How clear the sky is. 0 is clear, 10 can produce intense colors. It’s best to keep turbidity and upper atmosphere scattering low if high albedo.
        public var groundAlbedo: Float = 0.1
    }

}
