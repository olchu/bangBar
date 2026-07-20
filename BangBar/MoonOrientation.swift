import Foundation

enum MoonOrientation {
    static func brightLimbRotation(date: Date, latitude: Double, longitude: Double) -> Double {
        let days = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545
        let sun = sunEquatorial(days: days)
        let moon = moonEquatorial(days: days)

        let deltaRA = sun.ra - moon.ra
        let brightLimb = atan2(
            cos(sun.dec) * sin(deltaRA),
            sin(sun.dec) * cos(moon.dec) - cos(sun.dec) * sin(moon.dec) * cos(deltaRA)
        )

        let siderealDegrees = (280.46061837 + 360.98564736629 * days + longitude).normalizedDegrees
        let hourAngle = siderealDegrees.radians - moon.ra
        let observerLatitude = latitude.radians
        let parallactic = atan2(
            sin(hourAngle),
            tan(observerLatitude) * cos(moon.dec) - sin(moon.dec) * cos(hourAngle)
        )

        // The astronomical angle is measured from the disk's north point.
        // MoonIlluminationMask starts with its bright side pointing east (right).
        // SwiftUI's screen Y axis points down, so the converted angle must also
        // be mirrored to match the orientation seen against the local horizon.
        return -((brightLimb - parallactic) * 180 / .pi + 90)
    }

    private static func sunEquatorial(days: Double) -> (ra: Double, dec: Double) {
        let meanLongitude = (280.46646 + 0.98564736 * days).normalizedDegrees
        let anomaly = (357.52911 + 0.98560028 * days).normalizedDegrees
        let longitude = meanLongitude
            + 1.914602 * sin(anomaly.radians)
            + 0.019993 * sin((2 * anomaly).radians)
            + 0.000289 * sin((3 * anomaly).radians)
        return equatorial(longitude: longitude, latitude: 0, days: days)
    }

    private static func moonEquatorial(days: Double) -> (ra: Double, dec: Double) {
        let meanLongitude = (218.316 + 13.176396 * days).normalizedDegrees
        let anomaly = (134.963 + 13.064993 * days).normalizedDegrees
        let elongation = (297.850 + 12.190749 * days).normalizedDegrees
        let argument = (93.272 + 13.229350 * days).normalizedDegrees
        let longitude = meanLongitude
            + 6.289 * sin(anomaly.radians)
            + 1.274 * sin((2 * elongation - anomaly).radians)
            + 0.658 * sin((2 * elongation).radians)
            + 0.214 * sin((2 * anomaly).radians)
            - 0.186 * sin((357.529 + 0.98560028 * days).radians)
        let latitude = 5.128 * sin(argument.radians)
            + 0.280 * sin((anomaly + argument).radians)
            + 0.277 * sin((anomaly - argument).radians)
            + 0.173 * sin((2 * elongation - argument).radians)
        return equatorial(longitude: longitude, latitude: latitude, days: days)
    }

    private static func equatorial(longitude: Double, latitude: Double, days: Double) -> (ra: Double, dec: Double) {
        let obliquity = (23.439291 - 0.00000036 * days).radians
        let lon = longitude.radians
        let lat = latitude.radians
        let ra = atan2(sin(lon) * cos(obliquity) - tan(lat) * sin(obliquity), cos(lon))
        let dec = asin(sin(lat) * cos(obliquity) + cos(lat) * sin(obliquity) * sin(lon))
        return (ra, dec)
    }
}

private extension Double {
    var normalizedDegrees: Double {
        let value = truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }

    var radians: Double { self * .pi / 180 }
}
