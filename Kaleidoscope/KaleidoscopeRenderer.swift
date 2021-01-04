/*
The kaleidoscope filter renderer, implemented with Metal.
*/

import CoreMedia
import CoreVideo
import Metal

class KaleidoscopeRenderer: FilterRenderer {

    var description: String = "Kaleidoscope"

    var filterParams: KaleidoscopeFilterParams?

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

    var mirrorCorners: [CGPoint]?

    required init() {
        let defaultLibrary = metalDevice.makeDefaultLibrary()!
        let kernelFunction = defaultLibrary.makeFunction(name: "kaleidoscope")
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

        guard let unwrappedMirrorCorners = mirrorCorners else {
            print("mirrorCorners unset")
            CVMetalTextureCacheFlush(textureCache!, 0)
            return nil
        }

        var mirrors: [LineSegment] = []
        for i in 0..<unwrappedMirrorCorners.count {
            mirrors.append(MakeLineSegment(p0: unwrappedMirrorCorners[i],
                                           p1: unwrappedMirrorCorners[(i + 1) % unwrappedMirrorCorners.count]))
        }

        guard var unwrappedFilterParams = filterParams else {
            print("filterParams unset")
            CVMetalTextureCacheFlush(textureCache!, 0)
            return nil
        }

        guard unwrappedFilterParams.numSegments == unwrappedMirrorCorners.count else {
            print("Error: filterParams.numSegments: \(unwrappedFilterParams.numSegments) != mirrorCorners.count: \(unwrappedMirrorCorners.count)")
            return nil
        }

        commandEncoder.label = "Kaleidoscope"
        commandEncoder.setComputePipelineState(computePipelineState!)
        commandEncoder.setTexture(inputTexture, index: 0)
        commandEncoder.setTexture(outputTexture, index: 1)
        commandEncoder.setBytes(&unwrappedFilterParams,
                                length: MemoryLayout<KaleidoscopeFilterParams>.stride,
                                index: 0)
        commandEncoder.setBytes(mirrors,
                                length: MemoryLayout<LineSegment>.stride * mirrors.count,
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
