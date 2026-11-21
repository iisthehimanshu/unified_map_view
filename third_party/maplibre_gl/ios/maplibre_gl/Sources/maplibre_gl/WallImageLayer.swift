import CoreGraphics
import Flutter
import Foundation
import MapLibre
import Metal
import MetalKit
import UIKit
import simd

/// Wall images: textured rectangles standing upright between pairs of
/// coordinates, all sharing one image, drawn with Metal as a single MapLibre
/// custom layer in one draw call.
///
/// The camera math mirrors android/src/main/cpp/wall_image_math.hpp; keep the
/// two in step.
final class WallImageStyleLayer: MLNCustomStyleLayer {
    private static let earthRadius = 6378137.0
    private static let tileSize = 512.0
    private static let maxTextureSize = 4096

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn { packed_float3 pos; packed_float2 uv; };
    struct Uniforms { float4x4 matrix; float opacity; };
    struct VertexOut { float4 position [[position]]; float2 uv; };

    vertex VertexOut wall_vertex(uint vid [[vertex_id]],
                                 const device VertexIn *vertices [[buffer(0)]],
                                 constant Uniforms &u [[buffer(1)]]) {
        VertexOut out;
        out.position = u.matrix * float4(float3(vertices[vid].pos), 1.0);
        out.uv = float2(vertices[vid].uv);
        return out;
    }

    fragment float4 wall_fragment(VertexOut in [[stage_in]],
                                  texture2d<float> image [[texture(0)]],
                                  sampler imageSampler [[sampler(0)]],
                                  constant Uniforms &u [[buffer(1)]]) {
        // The texture holds premultiplied alpha, like the rest of MapLibre.
        float4 color = image.sample(imageSampler, in.uv) * u.opacity;
        if (color.a < 0.004) discard_fragment();  // keep transparent pixels out of the depth buffer
        return color;
    }
    """

    private struct Uniforms {
        var matrix: simd_float4x4
        var opacity: Float
    }

    private let originLat: Double
    private let originX: Double
    private let originY: Double
    /// Interleaved x, y, z (local metres east, north, up), u, v; six vertices
    /// (two triangles) per wall.
    private let vertices: [Float]
    private let opacity: Float
    private let doubleSided: Bool
    private let image: CGImage

    private var pipeline: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    private var vertexBuffer: MTLBuffer?
    private var texture: MTLTexture?
    private var sampler: MTLSamplerState?

    /// `walls` holds startLat, startLng, endLat, endLng, base, height per wall.
    init(
        identifier: String,
        walls: [Double],
        opacity: Double,
        doubleSided: Bool,
        image: CGImage
    ) {
        originLat = walls[0]
        let origin = Self.mercator(CLLocationCoordinate2D(latitude: walls[0], longitude: walls[1]))
        originX = origin.x
        originY = origin.y
        let metersPerUnit = cos(walls[0] * .pi / 180) * 2 * .pi * Self.earthRadius
        func local(_ lat: Double, _ lng: Double) -> (Float, Float) {
            let p = Self.mercator(CLLocationCoordinate2D(latitude: lat, longitude: lng))
            return (Float((p.x - origin.x) * metersPerUnit), Float(-(p.y - origin.y) * metersPerUnit))
        }
        var vertices: [Float] = []
        vertices.reserveCapacity(walls.count / 6 * 30)
        for i in stride(from: 0, to: walls.count - 5, by: 6) {
            let (ax, ay) = local(walls[i], walls[i + 1])
            let (bx, by) = local(walls[i + 2], walls[i + 3])
            let base = Float(walls[i + 4])
            let top = Float(walls[i + 4] + walls[i + 5])
            // Two triangles, counter-clockwise when seen from the front (start
            // on the left). Image row 0 is the top, so v = 0 at the top edge.
            vertices += [
                ax, ay, base, 0, 1,  bx, by, base, 1, 1,  bx, by, top, 1, 0,
                ax, ay, base, 0, 1,  bx, by, top, 1, 0,   ax, ay, top, 0, 0,
            ]
        }
        self.vertices = vertices
        self.opacity = Float(opacity)
        self.doubleSided = doubleSided
        self.image = image
        super.init(identifier: identifier)
    }

    // MARK: - MLNCustomStyleLayer

    override func didMove(to mapView: MLNMapView) {
        setUpResources(mapView)
    }

    override func willMove(from mapView: MLNMapView) {
        pipeline = nil
        depthState = nil
        vertexBuffer = nil
        texture = nil
        sampler = nil
    }

    override func draw(in mapView: MLNMapView, with context: MLNStyleLayerDrawingContext) {
        if pipeline == nil { setUpResources(mapView) }
        guard let encoder = renderEncoder, let pipeline, let depthState, let vertexBuffer,
              let texture, let sampler
        else { return }

        let projection = Self.nearClipped(
            Self.array(context.projectionMatrix),
            viewportHeight: Double(context.size.height),
            fov: Double(context.fieldOfView)
        )
        let mvp = Self.multiply(projection, model(zoom: context.zoomLevel))

        var uniforms = Uniforms(matrix: Self.floatMatrix(mvp), opacity: opacity)

        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setCullMode(doubleSided ? .none : .back)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count / 5)
        encoder.setCullMode(.none)
    }

    // MARK: - Metal setup

    private func setUpResources(_ mapView: MLNMapView) {
        let resource = mapView.backendResource()
        guard let device = resource.device ?? MTLCreateSystemDefaultDevice() else { return }
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "Wall image"
            descriptor.vertexFunction = library.makeFunction(name: "wall_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: "wall_fragment")

            let mtkView = resource.mtkView
            let color = descriptor.colorAttachments[0]!
            color.pixelFormat = mtkView?.colorPixelFormat ?? .bgra8Unorm
            color.isBlendingEnabled = true
            color.sourceRGBBlendFactor = .one
            color.sourceAlphaBlendFactor = .one
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha

            var depthFormat = mtkView?.depthStencilPixelFormat ?? .invalid
            if depthFormat == .invalid { depthFormat = .depth32Float_stencil8 }
            descriptor.depthAttachmentPixelFormat = depthFormat
            if depthFormat == .depth32Float_stencil8 || depthFormat == .stencil8 {
                descriptor.stencilAttachmentPixelFormat = depthFormat
            }
            descriptor.rasterSampleCount = max(1, mtkView?.sampleCount ?? 1)

            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("WallImageLayer: Metal pipeline failed: \(error)")
            return
        }

        // Same depth setup MapLibre uses for fill-extrusions. No stencil test.
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .lessEqual
        depth.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depth)

        vertexBuffer = device.makeBuffer(
            bytes: vertices, length: vertices.count * MemoryLayout<Float>.size, options: [])

        texture = makeTexture(device: device)

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.maxAnisotropy = 8
        sampler = device.makeSamplerState(descriptor: samplerDescriptor)
    }

    /// Premultiplied RGBA texture with mipmaps.
    private func makeTexture(device: MTLDevice) -> MTLTexture? {
        let scale = min(1.0, Double(Self.maxTextureSize) / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: true)
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
            withBytes: pixels, bytesPerRow: bytesPerRow)

        if let queue = device.makeCommandQueue(), let commands = queue.makeCommandBuffer(),
           let blit = commands.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
        }
        return texture
    }

    // MARK: - Camera math

    private static func mercator(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
        let lat = c.latitude * .pi / 180
        return ((c.longitude + 180) / 360, 0.5 - log(tan(.pi / 4 + lat / 2)) / (2 * .pi))
    }

    /// Local metres (east, north, up) around the first wall's start point → MapLibre world
    /// space (pixels at this zoom for x/y, metres for z). Column-major.
    private func model(zoom: Double) -> [Double] {
        let worldSize = Self.tileSize * pow(2, zoom)
        let pxPerMeter = worldSize / (cos(originLat * .pi / 180) * 2 * .pi * Self.earthRadius)
        return [
            pxPerMeter, 0, 0, 0,
            0, -pxPerMeter, 0, 0,
            0, 0, 1, 0,
            originX * worldSize, originY * worldSize, 0, 1,
        ]
    }

    private static func array(_ m: MLNMatrix4) -> [Double] {
        [m.m00, m.m01, m.m02, m.m03, m.m10, m.m11, m.m12, m.m13,
         m.m20, m.m21, m.m22, m.m23, m.m30, m.m31, m.m32, m.m33]
    }

    private static func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: 16)
        for c in 0..<4 {
            for r in 0..<4 {
                var s = 0.0
                for k in 0..<4 { s += a[k * 4 + r] * b[c * 4 + k] }
                out[c * 4 + r] = s
            }
        }
        return out
    }

    /// MapLibre gives custom layers a projection with near plane 1 but draws
    /// fill-extrusions with the near plane at 0.1 × camera-to-centre distance.
    /// Depth only lines up with buildings if we match it, so rebuild the z row.
    /// See wall_image_math.hpp for the derivation.
    private static func nearClipped(_ p: [Double], viewportHeight: Double, fov: Double) -> [Double] {
        var best = 0
        for c in 1..<3 where abs(p[c * 4 + 3]) > abs(p[best * 4 + 3]) { best = c }
        guard p[best * 4 + 3] != 0 else { return p }

        let c22 = -p[best * 4 + 2] / p[best * 4 + 3]
        let c23 = p[14] + c22 * p[15]
        let far = c23 / (c22 + 1)

        let cameraToCenter = 0.5 * viewportHeight / tan(fov / 2)
        let near = Double(UInt16(clamping: Int(0.1 * cameraToCenter)))  // MapLibre truncates to uint16
        guard near > 0, far > near else { return p }

        let n22 = (far + near) / (near - far)
        let n23 = 2 * far * near / (near - far)
        var out = p
        for c in 0..<4 { out[c * 4 + 2] = -n22 * p[c * 4 + 3] }
        out[14] += n23
        return out
    }

    private static func floatMatrix(_ m: [Double]) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(Float(m[0]), Float(m[1]), Float(m[2]), Float(m[3])),
            SIMD4(Float(m[4]), Float(m[5]), Float(m[6]), Float(m[7])),
            SIMD4(Float(m[8]), Float(m[9]), Float(m[10]), Float(m[11])),
            SIMD4(Float(m[12]), Float(m[13]), Float(m[14]), Float(m[15]))
        ))
    }
}

enum WallImageLayer {
    static func add(mapView: MLNMapView, arguments: [String: Any]) throws {
        guard let style = mapView.style else { throw WallImageError("Style is not loaded") }
        guard let id = arguments["id"] as? String,
              let wallData = arguments["walls"] as? FlutterStandardTypedData,
              let opacity = arguments["opacity"] as? Double,
              let doubleSided = arguments["doubleSided"] as? Bool,
              let bytes = arguments["image"] as? FlutterStandardTypedData
        else { throw WallImageError("Missing wall image arguments") }
        let walls: [Double] = wallData.data.withUnsafeBytes { Array($0.bindMemory(to: Double.self)) }
        guard walls.count >= 6, walls.count % 6 == 0 else {
            throw WallImageError("Walls must hold 6 values per wall")
        }
        guard let cgImage = UIImage(data: bytes.data)?.cgImage else {
            throw WallImageError("Could not decode the wall image")
        }

        if let existing = style.layer(withIdentifier: id) { style.removeLayer(existing) }

        let layer = WallImageStyleLayer(
            identifier: id, walls: walls, opacity: opacity, doubleSided: doubleSided,
            image: cgImage)

        if let belowId = arguments["belowLayerId"] as? String,
           let below = style.layer(withIdentifier: belowId) {
            style.insertLayer(layer, below: below)
        } else {
            style.addLayer(layer)
        }
        mapView.triggerRepaint()
    }

    static func remove(mapView: MLNMapView, id: String) {
        guard let style = mapView.style, let layer = style.layer(withIdentifier: id) else { return }
        style.removeLayer(layer)
        mapView.triggerRepaint()
    }
}

struct WallImageError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
