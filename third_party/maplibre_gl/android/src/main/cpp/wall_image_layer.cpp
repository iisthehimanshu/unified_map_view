// OpenGL ES renderer for wall images: textured rectangles standing upright
// between pairs of coordinates, all sharing one image, drawn as a single
// MapLibre custom layer with one draw call.

#include <GLES3/gl3.h>
#include <android/log.h>
#include <jni.h>

#include <cmath>
#include <cstdint>
#include <vector>

#include "mbgl_custom_layer_host.hpp"
#include "wall_image_math.hpp"

#define LOG_TAG "WallImageLayer"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

// Matches MapLibre's PaintParameters for the OpenGL backend.
constexpr double kNumSublayers = 3.0;
constexpr double kDepthEpsilon = 1.0 / 65536.0;

// Doubles per wall in the array handed over from Java:
// startLat, startLng, endLat, endLng, base, height.
constexpr int kWallStride = 6;
constexpr int kFloatsPerVertex = 5;  // x, y, z (local metres), u, v

const char* kVertexShader = R"(#version 300 es
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec2 a_uv;
uniform mat4 u_matrix;
out vec2 v_uv;
void main() {
    v_uv = a_uv;
    gl_Position = u_matrix * vec4(a_pos, 1.0);
}
)";

const char* kFragmentShader = R"(#version 300 es
precision mediump float;
in vec2 v_uv;
uniform sampler2D u_image;
uniform float u_opacity;
out vec4 fragColor;
void main() {
    // The texture holds premultiplied alpha, like the rest of MapLibre.
    vec4 color = texture(u_image, v_uv) * u_opacity;
    if (color.a < 0.004) discard;  // keep transparent pixels out of the depth buffer
    fragColor = color;
}
)";

GLuint compile(GLenum type, const char* source) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    GLint ok = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[512];
        glGetShaderInfoLog(shader, sizeof(log), nullptr, log);
        LOGE("Shader compile failed: %s", log);
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

class WallImageHost final : public mbgl::style::CustomLayerHost {
public:
    WallImageHost(const std::vector<double>& walls, double opacity, bool doubleSided,
                  std::vector<uint8_t> rgba, int width, int heightPx, int layerCount, int layersAbove)
        : originLat_(walls[0]),
          origin_(wallimage::toMercator(walls[0], walls[1])),
          opacity_(opacity),
          doubleSided_(doubleSided),
          pixels_(std::move(rgba)),
          imageWidth_(width),
          imageHeight_(heightPx),
          layerCount_(layerCount),
          layersAbove_(layersAbove) {
        const size_t count = walls.size() / kWallStride;
        vertices_.reserve(count * 6 * kFloatsPerVertex);
        for (size_t i = 0; i < count; ++i) {
            const double* w = &walls[i * kWallStride];
            double ax, ay, bx, by;
            wallimage::localOffset(originLat_, origin_, w[0], w[1], ax, ay);
            wallimage::localOffset(originLat_, origin_, w[2], w[3], bx, by);
            const float base = static_cast<float>(w[4]);
            const float top = static_cast<float>(w[4] + w[5]);
            // Two triangles, counter-clockwise when seen from the front
            // (start on the left). Image row 0 is the top, so v = 0 at the top.
            const float quad[6][kFloatsPerVertex] = {
                {float(ax), float(ay), base, 0.f, 1.f},  // start-bottom
                {float(bx), float(by), base, 1.f, 1.f},  // end-bottom
                {float(bx), float(by), top, 1.f, 0.f},   // end-top
                {float(ax), float(ay), base, 0.f, 1.f},  // start-bottom
                {float(bx), float(by), top, 1.f, 0.f},   // end-top
                {float(ax), float(ay), top, 0.f, 0.f},   // start-top
            };
            for (const auto& v : quad) vertices_.insert(vertices_.end(), v, v + kFloatsPerVertex);
        }
        vertexCount_ = static_cast<GLsizei>(count * 6);
    }

    void initialize() override {
        GLuint vs = compile(GL_VERTEX_SHADER, kVertexShader);
        GLuint fs = compile(GL_FRAGMENT_SHADER, kFragmentShader);
        if (!vs || !fs) return;
        program_ = glCreateProgram();
        glAttachShader(program_, vs);
        glAttachShader(program_, fs);
        glLinkProgram(program_);
        glDeleteShader(vs);
        glDeleteShader(fs);
        GLint ok = GL_FALSE;
        glGetProgramiv(program_, GL_LINK_STATUS, &ok);
        if (!ok) {
            LOGE("Program link failed");
            glDeleteProgram(program_);
            program_ = 0;
            return;
        }
        uMatrix_ = glGetUniformLocation(program_, "u_matrix");
        uOpacity_ = glGetUniformLocation(program_, "u_opacity");
        uImage_ = glGetUniformLocation(program_, "u_image");

        // Own VAO, so we never change the attribute state of MapLibre's VAOs.
        glGenVertexArrays(1, &vao_);
        glBindVertexArray(vao_);
        glGenBuffers(1, &vbo_);
        glBindBuffer(GL_ARRAY_BUFFER, vbo_);
        glBufferData(GL_ARRAY_BUFFER, static_cast<GLsizeiptr>(vertices_.size() * sizeof(float)), vertices_.data(),
                     GL_STATIC_DRAW);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, kFloatsPerVertex * sizeof(float), nullptr);
        glEnableVertexAttribArray(1);
        glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, kFloatsPerVertex * sizeof(float),
                              reinterpret_cast<void*>(3 * sizeof(float)));
        glBindVertexArray(0);
        glBindBuffer(GL_ARRAY_BUFFER, 0);

        glGenTextures(1, &texture_);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, texture_);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, imageWidth_, imageHeight_, 0, GL_RGBA, GL_UNSIGNED_BYTE,
                     pixels_.data());
        glGenerateMipmap(GL_TEXTURE_2D);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glBindTexture(GL_TEXTURE_2D, 0);
    }

    void render(const mbgl::style::CustomLayerRenderParameters& params) override {
        if (!program_ || vertexCount_ == 0) return;

        const wallimage::Mat4 proj = wallimage::nearClipped(params.projectionMatrix, params.height, params.fieldOfView);
        const wallimage::Mat4 mvp = wallimage::multiply(proj, wallimage::model(origin_, originLat_, params.zoom));
        float matrix[16];
        for (int i = 0; i < 16; ++i) matrix[i] = static_cast<float>(mvp[i]);

        const double depthRangeSize = currentDepthRangeSize();

        glUseProgram(program_);
        glUniformMatrix4fv(uMatrix_, 1, GL_FALSE, matrix);
        glUniform1f(uOpacity_, static_cast<float>(opacity_));
        glUniform1i(uImage_, 0);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, texture_);

        // Same depth setup MapLibre uses for fill-extrusions (depthModeFor3D).
        glEnable(GL_DEPTH_TEST);
        glDepthFunc(GL_LEQUAL);
        glDepthMask(GL_TRUE);
        glDepthRangef(0.0f, static_cast<float>(depthRangeSize));
        glDisable(GL_STENCIL_TEST);
        if (doubleSided_) {
            glDisable(GL_CULL_FACE);
        } else {
            glEnable(GL_CULL_FACE);
            glFrontFace(GL_CCW);
            glCullFace(GL_BACK);
        }
        glEnable(GL_BLEND);
        glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

        glBindVertexArray(vao_);
        glDrawArrays(GL_TRIANGLES, 0, vertexCount_);
        glBindVertexArray(0);
        glBindTexture(GL_TEXTURE_2D, 0);
        glDisable(GL_CULL_FACE);
    }

    void contextLost() override {
        // The GL objects died with the context; initialize() will run again.
        program_ = vao_ = vbo_ = texture_ = 0;
    }

    void deinitialize() override {
        if (texture_) glDeleteTextures(1, &texture_);
        if (vbo_) glDeleteBuffers(1, &vbo_);
        if (vao_) glDeleteVertexArrays(1, &vao_);
        if (program_) glDeleteProgram(program_);
        program_ = vao_ = vbo_ = texture_ = 0;
    }

private:
    // MapLibre's GL backend maps 3D depth into [0, depthRangeSize], where
    // depthRangeSize = 1 − (layer groups + 2) · 3 · ε. Before calling us it
    // sets the depth range to one value for this layer, which encodes how
    // many layer groups are below us. Add the layers above us to get the
    // total. Fall back to the style's layer count if that state isn't set.
    double currentDepthRangeSize() const {
        double groups = layerCount_;
        if (glIsEnabled(GL_DEPTH_TEST)) {
            GLfloat range[2] = {0, 0};
            glGetFloatv(GL_DEPTH_RANGE, range);
            if (range[0] == range[1] && range[0] > 0.5f) {
                const double below = std::round((1.0 - range[0]) / (kNumSublayers * kDepthEpsilon)) - 2.0;
                if (below >= 0) groups = below + 1.0 + layersAbove_;
            }
        }
        return 1.0 - (groups + 2.0) * kNumSublayers * kDepthEpsilon;
    }

    const double originLat_;
    const wallimage::Mercator origin_;
    const double opacity_;
    const bool doubleSided_;
    const std::vector<uint8_t> pixels_;
    const int imageWidth_;
    const int imageHeight_;
    const int layerCount_;
    const int layersAbove_;
    std::vector<float> vertices_;
    GLsizei vertexCount_ = 0;

    GLuint program_ = 0, vao_ = 0, vbo_ = 0, texture_ = 0;
    GLint uMatrix_ = -1, uOpacity_ = -1, uImage_ = -1;
};

}  // namespace

extern "C" JNIEXPORT jlong JNICALL Java_org_maplibre_maplibregl_WallImageLayer_nativeCreate(
    JNIEnv* env, jclass, jdoubleArray walls, jdouble opacity, jboolean doubleSided, jobject rgba, jint width,
    jint heightPx, jint layerCount, jint layersAbove) {
    const jsize length = env->GetArrayLength(walls);
    if (length < kWallStride || length % kWallStride != 0) {
        LOGE("Wall array must hold 6 values per wall");
        return 0;
    }
    std::vector<double> wallValues(static_cast<size_t>(length));
    env->GetDoubleArrayRegion(walls, 0, length, wallValues.data());

    auto* data = static_cast<uint8_t*>(env->GetDirectBufferAddress(rgba));
    const jlong capacity = env->GetDirectBufferCapacity(rgba);
    const jlong needed = static_cast<jlong>(width) * heightPx * 4;
    if (!data || capacity < needed || width <= 0 || heightPx <= 0) {
        LOGE("Invalid image buffer");
        return 0;
    }
    std::vector<uint8_t> pixels(data, data + needed);
    auto* host = new WallImageHost(wallValues, opacity, doubleSided == JNI_TRUE, std::move(pixels), width, heightPx,
                                   layerCount, layersAbove);
    // MapLibre's CustomLayer takes ownership through a CustomLayerHost*.
    return reinterpret_cast<jlong>(static_cast<mbgl::style::CustomLayerHost*>(host));
}
