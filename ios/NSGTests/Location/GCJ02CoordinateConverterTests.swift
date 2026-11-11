import CoreLocation
import Testing

@testable import NSG

@MainActor
struct GCJ02CoordinateConverterTests {
    @Test("Match reference WGS-84 to GCJ-02 results in Beijing and Shanghai")
    func conversionMatchesBeijingAndShanghaiReferences() throws {
        let samples = [
            (
                CLLocationCoordinate2D(latitude: 39.915, longitude: 116.404),
                CLLocationCoordinate2D(latitude: 39.91640428150164, longitude: 116.41024449916938)
            ),
            (
                CLLocationCoordinate2D(latitude: 31.230416, longitude: 121.473701),
                CLLocationCoordinate2D(latitude: 31.22847374224698, longitude: 121.47822405739267)
            ),
        ]

        for (source, expected) in samples {
            let result = try #require(GCJ02CoordinateConverter.fromWGS84(source))
            #expect(abs(result.latitude - expected.latitude) < 1e-9)
            #expect(abs(result.longitude - expected.longitude) < 1e-9)
        }
    }

    @Test("Preserve coordinates clearly outside the transform's applicability bounds")
    func conversionPreservesCoordinatesOutsideApplicableBounds() throws {
        for source in [
            CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
            CLLocationCoordinate2D(latitude: 35.6586, longitude: 139.7454),
        ] {
            let result = try #require(GCJ02CoordinateConverter.fromWGS84(source))
            #expect(result.latitude == source.latitude)
            #expect(result.longitude == source.longitude)
        }
    }

    @Test("Reject non-finite and out-of-range inputs before converting")
    func conversionRejectsInvalidCoordinates() {
        for source in [
            CLLocationCoordinate2D(latitude: .nan, longitude: 121),
            CLLocationCoordinate2D(latitude: 31, longitude: .infinity),
            CLLocationCoordinate2D(latitude: 91, longitude: 121),
            CLLocationCoordinate2D(latitude: 31, longitude: 181),
        ] {
            #expect(GCJ02CoordinateConverter.fromWGS84(source) == nil)
        }
    }
}
