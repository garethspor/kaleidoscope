/*
The kaleidoscope filter renderer, implemented with Metal.
*/

import CoreMedia
import CoreVideo
import Metal

class Kaleidoscope2Renderer: FilterRenderer {

    var description: String = "Kaleidoscope2"

    var mirrored: Bool = false;

    var isPrepared = false

    private(set) var inputFormatDescription: CMFormatDescription?

    private(set) var outputFormatDescription: CMFormatDescription?

    private var outputPixelBufferPool: CVPixelBufferPool?

    private let metalDevice = MTLCreateSystemDefaultDevice()!

    private var computePipelineState: MTLComputePipelineState?

    private var textureCache: CVMetalTextureCache!

    private lazy var commandQueue: MTLCommandQueue? = {
        return self.metalDevice.makeCommandQueue()
    }()

    required init() {
        let defaultLibrary = metalDevice.makeDefaultLibrary()!
        let kernelFunction = defaultLibrary.makeFunction(name: "kaleidoscope2")
        do {
            computePipelineState = try metalDevice.makeComputePipelineState(function: kernelFunction!)
        } catch {
            print("Could not create pipeline state: \(error)")
        }
    }

    func prepare(with formatDescription: CMFormatDescription, outputRetainedBufferCountHint: Int) {
        reset()

        (outputPixelBufferPool, _, outputFormatDescription) = allocateOutputBufferPool(
            with: formatDescription,
            outputRetainedBufferCountHint: outputRetainedBufferCountHint)
        if outputPixelBufferPool == nil {
            return
        }
        inputFormatDescription = formatDescription

        var metalTextureCache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &metalTextureCache) != kCVReturnSuccess {
            assertionFailure("Unable to allocate texture cache")
        } else {
            textureCache = metalTextureCache
        }

        isPrepared = true
    }

    func reset() {
        outputPixelBufferPool = nil
        outputFormatDescription = nil
        inputFormatDescription = nil
        textureCache = nil
        isPrepared = false
    }

    /// - Tag: Kaleidoscope Metal

    private struct FilterParams {
        var numSegments: Int = 3
        var mirrored: Bool = false
      }

    func render(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        if !isPrepared {
            assertionFailure("Invalid state: Not prepared.")
            return nil
        }

        var newPixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPixelBufferPool!, &newPixelBuffer)
        guard let outputPixelBuffer = newPixelBuffer else {
            print("Allocation failure: Could not get pixel buffer from pool. (\(self.description))")
            return nil
        }
        guard let inputTexture = makeTextureFromCVPixelBuffer(pixelBuffer: pixelBuffer, textureFormat: .bgra8Unorm),
            let outputTexture = makeTextureFromCVPixelBuffer(pixelBuffer: outputPixelBuffer, textureFormat: .bgra8Unorm) else {
                return nil
        }

        // Set up command queue, buffer, and encoder.
        guard let commandQueue = commandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
                print("Failed to create a Metal command queue.")
                CVMetalTextureCacheFlush(textureCache!, 0)
                return nil
        }

        var params = FilterParams(
            numSegments: 3,
            mirrored: mirrored
        )

        let mirrorCorners: [Vec2f] = [
            Vec2f(x: 0.7, y: 0.475),
            Vec2f(x: 0.4, y: 0.375),
            Vec2f(x: 0.37, y: 0.475),
        ]

        // TODO: auto generate
        let mirrors: [LineSegment] = [
            MakeLineSegment(p0: mirrorCorners[0], p1: mirrorCorners[1]),
            MakeLineSegment(p0: mirrorCorners[1], p1: mirrorCorners[2]),
            MakeLineSegment(p0: mirrorCorners[2], p1: mirrorCorners[0]),
        ]


        commandEncoder.label = "Kaleidoscope"
        commandEncoder.setComputePipelineState(computePipelineState!)
        commandEncoder.setTexture(inputTexture, index: 0)
        commandEncoder.setTexture(outputTexture, index: 1)
        commandEncoder.setBytes(&params,
                                length: MemoryLayout<FilterParams>.stride,
                                index: 0)
        commandEncoder.setBytes(mirrors,
                                length: MemoryLayout<LineSegment>.stride * params.numSegments,
                                index: 1)

        // Set up the thread groups.
        let width = computePipelineState!.threadExecutionWidth
        let height = computePipelineState!.maxTotalThreadsPerThreadgroup / width
        let threadsPerThreadgroup = MTLSizeMake(width, height, 1)
        let threadgroupsPerGrid = MTLSize(width: (inputTexture.width + width - 1) / width,
                                          height: (inputTexture.height + height - 1) / height,
                                          depth: 1)
        commandEncoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)

        commandEncoder.endEncoding()
        commandBuffer.commit()
        return outputPixelBuffer
    }

    func makeTextureFromCVPixelBuffer(pixelBuffer: CVPixelBuffer, textureFormat: MTLPixelFormat) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Create a Metal texture from the image buffer.
        var cvTextureOut: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, textureFormat, width, height, 0, &cvTextureOut)

        guard let cvTexture = cvTextureOut, let texture = CVMetalTextureGetTexture(cvTexture) else {
            CVMetalTextureCacheFlush(textureCache, 0)

            return nil
        }

        return texture
    }
}
