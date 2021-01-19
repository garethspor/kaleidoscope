//
//  ClipRecorder.swift
//  Kaleidoscope
//
//  Created by Gareth Spor on 1/19/21.
//

import AVFoundation
import CoreVideo
import Foundation
import Photos

class ClipRecorder {

    private let outputFilePath: String

    private let videoWriter: AVAssetWriter

    private var videoWriterInput: AVAssetWriterInput?

    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var firstClipTimeValue: CMTimeValue?

    private var stopped = false

    private var internalBufferCount = 0

    var bufferCount : Int {
        return internalBufferCount
    }

    private var internalRecordDuration = CMTime(value: 0, timescale: 1)

    var recordDuration : CMTime {
        return internalRecordDuration
    }

    required init?() {
        let outputFileName = NSUUID().uuidString
        self.outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
        do {
            self.videoWriter = try AVAssetWriter(outputURL: URL(fileURLWithPath: outputFilePath), fileType: AVFileType.mov)
        } catch {
            print("Error: \(error)")
            return nil
        }
    }

    func appendBuffer(_ buffer: CVImageBuffer, withTimestamp timestamp: CMTime) {
        if (stopped) { return }

        if firstClipTimeValue == nil {
            firstClipTimeValue = timestamp.value
            let videoSettings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                                AVVideoWidthKey: Int(CVPixelBufferGetWidth(buffer)),
                                                AVVideoHeightKey: Int(CVPixelBufferGetHeight(buffer))]
            self.videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
            self.videoWriterInput?.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi / 2))
            self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriterInput!, sourcePixelBufferAttributes: nil)
            if !videoWriter.canAdd(videoWriterInput!) {
                print("can't add video writer")
                return
            }
            videoWriterInput!.expectsMediaDataInRealTime = true
            videoWriter.add(videoWriterInput!)
            videoWriter.startWriting()
            let startFrameTime = CMTimeMake(value: 0, timescale: 600)
            videoWriter.startSession(atSourceTime: startFrameTime)
            print("started session at \(startFrameTime)")
        }

        if pixelBufferAdaptor!.assetWriterInput.isReadyForMoreMediaData {
            internalRecordDuration = CMTime(value: timestamp.value - firstClipTimeValue!, timescale: timestamp.timescale)
            pixelBufferAdaptor!.append(buffer, withPresentationTime: internalRecordDuration)
            internalBufferCount += 1
        } else {
            print("adaptor not ready")
        }
    }
    
    func stopRecording() {
        stopped = true

        guard let unwrappedVideoWriterInput = videoWriterInput else {
            return
        }

        unwrappedVideoWriterInput.markAsFinished()
        videoWriter.finishWriting {
            print(self.videoWriter.error ?? "finished writing ok I think!")
        }

        func cleanup() {
            if FileManager.default.fileExists(atPath: outputFilePath) {
                do {
                    try FileManager.default.removeItem(atPath: outputFilePath)
                } catch {
                    print("Could not remove file at url: \(outputFilePath)")
                }
            }
        }

        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                // Save the movie file to the photo library and cleanup.
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .video, fileURL: URL(fileURLWithPath: self.outputFilePath), options: options)
                }, completionHandler: { success, error in
                    if !success {
                        print("KaleidoSpor couldn't save the movie to your photo library: \(String(describing: error))")
                    }
                    cleanup()
                })
            } else {
                cleanup()
            }
        }
    }

}
