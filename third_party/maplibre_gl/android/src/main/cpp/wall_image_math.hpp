// Camera math for wall images, shared logic with ios/.../WallImageLayer.swift.
// Keep the two in step.
#pragma once

#include <array>
#include <cmath>
#include <cstdint>

namespace wallimage {

using Mat4 = std::array<double, 16>;  // column-major

constexpr double kEarthRadiusM = 6378137.0;
constexpr double kTileSize = 512.0;
constexpr double kPi = 3.14159265358979323846;

struct Mercator {
    double x;  // 0..1, west to east
    double y;  // 0..1, north to south
};

inline Mercator toMercator(double lat, double lng) {
    const double latR = lat * kPi / 180.0;
    return {(lng + 180.0) / 360.0, 0.5 - std::log(std::tan(kPi / 4.0 + latR / 2.0)) / (2.0 * kPi)};
}

inline Mat4 multiply(const Mat4& a, const Mat4& b) {
    Mat4 out{};
    for (int c = 0; c < 4; ++c) {
        for (int r = 0; r < 4; ++r) {
            double s = 0;
            for (int k = 0; k < 4; ++k) s += a[k * 4 + r] * b[c * 4 + k];
            out[c * 4 + r] = s;
        }
    }
    return out;
}

// MapLibre gives custom layers a projection with near plane 1, but draws
// fill-extrusions with the near plane at 0.1 × camera-to-centre distance
// (TransformParameters::nearClippedProjMatrix). Depth only lines up with
// buildings if we use the same near plane, so rebuild the z row.
//
// P = C · W, where C is a GL perspective matrix and W is world-to-camera.
// Row 3 of P is −(row 2 of W), so row 2 of P = C22 · (−row3) + C23 · e3.
inline Mat4 nearClipped(const Mat4& p, double viewportHeight, double fovRad) {
    int best = 0;
    for (int c = 1; c < 3; ++c) {
        if (std::fabs(p[c * 4 + 3]) > std::fabs(p[best * 4 + 3])) best = c;
    }
    if (p[best * 4 + 3] == 0) return p;

    const double c22 = -p[best * 4 + 2] / p[best * 4 + 3];
    const double c23 = p[14] + c22 * p[15];
    const double far = c23 / (c22 + 1.0);

    const double cameraToCenter = 0.5 * viewportHeight / std::tan(fovRad / 2.0);
    // MapLibre truncates the near plane to uint16_t.
    const double near = static_cast<double>(static_cast<uint16_t>(0.1 * cameraToCenter));
    if (near <= 0 || far <= near) return p;

    const double n22 = (far + near) / (near - far);
    const double n23 = 2.0 * far * near / (near - far);

    Mat4 out = p;
    for (int c = 0; c < 4; ++c) out[c * 4 + 2] = -n22 * p[c * 4 + 3];
    out[14] += n23;
    return out;
}

// Model matrix: local metres (east, north, up) around `origin` → MapLibre
// world space (pixels at this zoom for x/y, metres for z).
inline Mat4 model(const Mercator& origin, double originLat, double zoom) {
    const double worldSize = kTileSize * std::pow(2.0, zoom);
    const double pxPerMeter = worldSize / (std::cos(originLat * kPi / 180.0) * 2.0 * kPi * kEarthRadiusM);
    Mat4 m{};
    m[0] = pxPerMeter;
    m[5] = -pxPerMeter;  // north is −y in world space
    m[10] = 1.0;
    m[12] = origin.x * worldSize;
    m[13] = origin.y * worldSize;
    m[15] = 1.0;
    return m;
}

// A coordinate in local metres (east, north) relative to `origin`.
inline void localOffset(double originLat, const Mercator& origin, double lat, double lng, double& east,
                        double& north) {
    const Mercator p = toMercator(lat, lng);
    const double metersPerUnit = std::cos(originLat * kPi / 180.0) * 2.0 * kPi * kEarthRadiusM;
    east = (p.x - origin.x) * metersPerUnit;
    north = -(p.y - origin.y) * metersPerUnit;
}

}  // namespace wallimage
