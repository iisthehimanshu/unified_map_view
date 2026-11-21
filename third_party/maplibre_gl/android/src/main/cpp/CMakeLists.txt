cmake_minimum_required(VERSION 3.18.1)
project(maplibregl_wallimage LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Self-contained: only talks to libmaplibre.so through the CustomLayerHost
# vtable, so it doesn't link against MapLibre itself.
add_library(maplibregl_wallimage SHARED wall_image_layer.cpp)
target_compile_options(maplibregl_wallimage PRIVATE -Wall -Wextra -fvisibility=hidden)
target_link_libraries(maplibregl_wallimage GLESv3 log)
