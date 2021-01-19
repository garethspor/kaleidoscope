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

    private let videoWriterInput: AVAssetWriterInput

    private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor

    private var firstClipTimeValue: CMTimeValue?

    private var stopped = false

    required init?(withSize processedSize: CGSize) {
        let outputFileName = NSUUID().uuidString
        self.outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
        do {
            self.videoWriter = try AVAssetWriter(outputURL: URL(fileURLWithPath: outputFilePath), fileType: AVFileType.mov)
            let videoSettings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                                AVVideoWidthKey: Int(processedSize.width),
                                                AVVideoHeightKey: Int(processedSize.height)]
            self.videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
            self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriterInput, sourcePixelBufferAttributes: nil)
            if !videoWriter.canAdd(videoWriterInput) {
                print("can't add video writer")
                return nil
            }
            videoWriterInput.expectsMediaDataInRealTime = true
            videoWriter.add(videoWriterInput)
            videoWriter.startWriting()
            let startFrameTime = CMTimeMake(value: 0, timescale: 600)
            videoWriter.startSession(atSourceTime: startFrameTime)
            print("started session at \(startFrameTime)")
        } catch {
            print("Error: \(error)")
            return nil
        }
    }

    func appendBuffer(_ buffer: CVImageBuffer, withTimestamp timestamp: CMTime) {
        if pixelBufferAdaptor.assetWriterInput.isReadyForMoreMediaData {
            if firstClipTimeValue == nil {
                firstClipTimeValue = timestamp.value
            }
            let videoTime = CMTime(value: timestamp.value - firstClipTimeValue!, timescale: timestamp.timescale)
            pixelBufferAdaptor.append(buffer, withPresentationTime: videoTime)
        } else {
            print("adaptor not ready")
        }
    }
    
    func stopRecording() {
        stopped = true
        videoWriterInput.markAsFinished()
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
