import Foundation
import SwiftUI
import simd

// Standalone regression executable: bash scripts/test_moon_geometry.sh
@main
struct MoonGeometryTests {
    static func main() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        var configurations = 0

        // Independent oracle: project the Sun into the observer's screen plane.
        // It uses cross/dot products, not bright-limb or parallactic angles.
        for latitude in [-90.0, -70, -33.9, 0, 44.8, 70, 90] {
            for sidereal in stride(from: 0.0, to: 360, by: 45) {
                let zenith = direction(ra: radians(sidereal), dec: radians(latitude))
                for moonDeclination in [-25.0, 0, 25] {
                    let moon = (ra: radians(30), dec: radians(moonDeclination))
                    let sightline = direction(ra: moon.ra, dec: moon.dec)
                    let upProjection = zenith - simd_dot(zenith, sightline) * sightline
                    guard simd_length(upProjection) > 1e-8 else { continue }
                    let up = simd_normalize(upProjection)
                    let right = simd_normalize(simd_cross(sightline, up))

                    // Both sides of the Moon: waxing and waning, crescent and gibbous.
                    for separation in [-150.0, -90, -30, 30, 90, 150] {
                        let sun = (ra: moon.ra + radians(separation), dec: radians(10))
                        let sunlight = direction(ra: sun.ra, dec: sun.dec)
                        let expected = simd_normalize(SIMD2(
                            simd_dot(sunlight, right), -simd_dot(sunlight, up)
                        ))
                        let rotation = MoonOrientation.brightLimbRotation(
                            sun: sun, moon: moon, latitude: latitude, siderealDegrees: sidereal
                        )
                        let actual = SIMD2(cos(radians(rotation)), sin(radians(rotation)))
                        precondition(simd_dot(expected, actual) > 0.999999,
                                     "Sun direction mismatch at latitude \(latitude), LST \(sidereal)")

                        for illumination in [0.2, 0.5, 0.8] {
                            let path = MoonIlluminationMask(illumination: illumination)
                                .rotation(.degrees(rotation)).path(in: rect)
                            let litPoint = CGPoint(x: 50 + expected.x * 45, y: 50 + expected.y * 45)
                            let darkPoint = CGPoint(x: 50 - expected.x * 45, y: 50 - expected.y * 45)
                            precondition(path.contains(litPoint), "Sun-facing limb must be illuminated")
                            precondition(!path.contains(darkPoint), "Opposite limb must be in shadow")
                        }
                        configurations += 1
                    }
                }
            }
        }

        // Check the actual mask's area, including both sides of quarter phase.
        for illumination in [0.1, 0.25, 0.5, 0.75, 0.9] {
            let path = MoonIlluminationMask(illumination: illumination).path(in: rect)
            var count = 0
            for x in 0..<200 {
                for y in 0..<200 {
                    if path.contains(CGPoint(x: (Double(x) + 0.5) / 2, y: (Double(y) + 0.5) / 2)) {
                        count += 1
                    }
                }
            }
            let fraction = Double(count) / (Double.pi * 100 * 100)
            precondition(abs(fraction - illumination) < 0.01, "Incorrect illuminated area")
        }
        precondition(MoonIlluminationMask(illumination: 0).path(in: rect).isEmpty)
        precondition(MoonIlluminationMask(illumination: 1).path(in: rect).contains(CGPoint(x: 50, y: 50)))

        // Exercise the date/longitude entry point over a full lunar cycle.
        let start = ISO8601DateFormatter().date(from: "2026-09-01T12:00:00Z")!
        for day in 0..<30 {
            let date = start.addingTimeInterval(Double(day) * 86_400)
            for latitude in [-89.9, -33.9, 0, 44.8, 89.9] {
                let west = MoonOrientation.brightLimbRotation(date: date, latitude: latitude, longitude: -180)
                let east = MoonOrientation.brightLimbRotation(date: date, latitude: latitude, longitude: 180)
                precondition(west.isFinite && east.isFinite)
                precondition(abs(sin(radians(west - east) / 2)) < 1e-8, "Date line discontinuity")
            }
            // Compare near quarter phases: near new/full the projected sunlight
            // can turn rapidly as the Moon moves, so a one-hour comparison is invalid.
            guard [3, 4, 5, 18, 19, 20].contains(day) else { continue }
            // Positive east longitude advances the local sidereal time.
            let east = MoonOrientation.brightLimbRotation(date: date, latitude: 44.8, longitude: 35)
            let later = MoonOrientation.brightLimbRotation(
                date: date.addingTimeInterval(3_600), latitude: 44.8, longitude: 20
            )
            precondition(abs(sin(radians(east - later) / 2)) < sin(radians(3) / 2),
                         "Longitude sign or sidereal-time conversion is incorrect")
        }
        print("PASS: \(configurations) sky configurations, rotated crescent/quarter/gibbous masks, mask areas, and 30-day coordinate checks")
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    private static func direction(ra: Double, dec: Double) -> SIMD3<Double> {
        SIMD3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
    }
}
