import CoreLocation
import Foundation

/*
 WGS-84 to GCJ-02 math adapted from https://github.com/wandergis/coordtransform.

 The MIT License (MIT)
 Copyright (c) 2015 记忆的残骸

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

/// An approximate, offline conversion for map presentation only.
enum GCJ02CoordinateConverter {
    static func fromWGS84(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D? {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite,
              CLLocationCoordinate2DIsValid(coordinate) else { return nil }

        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        // These conventional applicability bounds are a coarse rectangle, not a
        // country boundary or a way to detect the current MapKit data provider.
        guard longitude > 73.66, longitude < 135.05,
              latitude > 3.86, latitude < 53.55 else { return coordinate }

        let semiMajorAxis = 6_378_245.0
        let eccentricitySquared = 0.00669342162296594323
        let x = longitude - 105
        let y = latitude - 35
        let radians = latitude * .pi / 180
        let sinLatitude = sin(radians)
        let magic = 1 - eccentricitySquared * sinLatitude * sinLatitude
        let sqrtMagic = sqrt(magic)
        let latitudeDelta = latitudeOffset(x: x, y: y) * 180 /
            ((semiMajorAxis * (1 - eccentricitySquared)) / (magic * sqrtMagic) * .pi)
        let longitudeDelta = longitudeOffset(x: x, y: y) * 180 /
            (semiMajorAxis / sqrtMagic * cos(radians) * .pi)

        return CLLocationCoordinate2D(
            latitude: latitude + latitudeDelta,
            longitude: longitude + longitudeDelta
        )
    }

    private static func latitudeOffset(x: Double, y: Double) -> Double {
        var offset = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        offset += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        offset += (20 * sin(y * .pi) + 40 * sin(y / 3 * .pi)) * 2 / 3
        offset += (160 * sin(y / 12 * .pi) + 320 * sin(y * .pi / 30)) * 2 / 3
        return offset
    }

    private static func longitudeOffset(x: Double, y: Double) -> Double {
        var offset = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        offset += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        offset += (20 * sin(x * .pi) + 40 * sin(x / 3 * .pi)) * 2 / 3
        offset += (150 * sin(x / 12 * .pi) + 300 * sin(x / 30 * .pi)) * 2 / 3
        return offset
    }
}
