// Minimal copy of MapLibre Native's custom layer interface.
//
// Source: include/mbgl/style/layers/custom_layer.hpp and
// custom_layer_render_parameters.hpp at tag android-v13.3.0.
//
// MapLibre takes ownership of a CustomLayerHost* passed to
// org.maplibre.android.style.layers.CustomLayer(id, host) and calls these
// virtual methods on its render thread. Only the vtable order and the
// parameter struct layout matter for ABI compatibility, so this copy must
// match upstream exactly. Re-check it whenever the MapLibre Android SDK
// version in build.gradle changes.
#pragma once

#include <array>

namespace mbgl {
namespace style {

struct CustomLayerRenderParameters {
    double width;
    double height;
    double latitude;
    double longitude;
    double zoom;
    double bearing;
    double pitch;
    double fieldOfView;                    // radians
    std::array<double, 16> projectionMatrix;  // column-major, world px (x, y) and metres (z)
};

class CustomLayerHost {
public:
    virtual ~CustomLayerHost() = default;
    virtual void initialize() = 0;
    virtual void render(const CustomLayerRenderParameters&) = 0;
    virtual void contextLost() = 0;
    virtual void deinitialize() = 0;
};

}  // namespace style
}  // namespace mbgl
