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

    private let clipWriter: AVAssetWriter

    private var clipWriterVideoInput: AVAssetWriterInput?
    private var clipWriterAudioInput: AVAssetWriterInput?

    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var firstBufferTime: CMTime?
    private var lastBufferTime: CMTime?

    private var stopped = false

    private var internalBufferCount = 0

    var bufferCount : Int {
        return internalBufferCount
    }

    var recordDuration : CMTime {
        if firstBufferTime == nil || lastBufferTime == nil {
            return CMTime(value: 0, timescale: 1)
        }
        if firstBufferTime!.timescale != lastBufferTime!.timescale {
            // Not sure easiest way to reconcile different timescales, punt for now
            return CMTime(value: 0, timescale: 1)
        }
        return CMTime(value: lastBufferTime!.value - firstBufferTime!.value, timescale: firstBufferTime!.timescale)
    }

    required init?() {
        let outputFileName = NSUUID().uuidString
        self.outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
        do {
            self.clipWriter = try AVAssetWriter(outputURL: URL(fileURLWithPath: outputFilePath), fileType: AVFileType.mov)
        } catch {
            print("Error: \(error)")
            return nil
        }
    }

    func appendImageBuffer(_ buffer: CVImageBuffer, withOriginalSampleBuffer originalSampleBuffer: CMSampleBuffer) {
        if (stopped) { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(originalSampleBuffer)

        if firstBufferTime == nil {
            firstBufferTime = timestamp

            let videoSettings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264,
                                                AVVideoWidthKey: Int(CVPixelBufferGetWidth(buffer)),
                                                AVVideoHeightKey: Int(CVPixelBufferGetHeight(buffer))]
            self.clipWriterVideoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)
            // Set transform so videos are recorded in portrait mode, same as UI
            self.clipWriterVideoInput!.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi / 2))
            self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: clipWriterVideoInput!, sourcePixelBufferAttributes: nil)
            if !clipWriter.canAdd(clipWriterVideoInput!) {
                print("can't add video writer")
                return
            }
            clipWriterVideoInput!.expectsMediaDataInRealTime = true
            clipWriter.add(clipWriterVideoInput!)

            let audioSettings : [String : Any] = [
                AVFormatIDKey : kAudioFormatMPEG4AAC,
                AVSampleRateKey : 44100,
                AVEncoderBitRateKey : 64000,
                AVNumberOfChannelsKey: 1
            ]
            clipWriterAudioInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioSettings)
            clipWriterAudioInput!.expectsMediaDataInRealTime = true;
            if clipWriter.canAdd(clipWriterAudioInput!) {
                clipWriter.add(clipWriterAudioInput!)
            } else{
                print("Could not add videoWriterAudioInput to clipWriter")
            }

            clipWriter.startWriting()
            clipWriter.startSession(atSourceTime: timestamp)
        }

        if pixelBufferAdaptor!.assetWriterInput.isReadyForMoreMediaData {
            pixelBufferAdaptor!.append(buffer, withPresentationTime: timestamp)
            lastBufferTime = timestamp
            internalBufferCount += 1
        } else {
            print("adaptor not ready for image data")
        }

    }

    func appendAudioBuffer(_ originalSampleBuffer: CMSampleBuffer) {
        if (stopped) { return }

        if let unwrappedClipWriterAudioInput = clipWriterAudioInput, unwrappedClipWriterAudioInput.isReadyForMoreMediaData {
            unwrappedClipWriterAudioInput.append(originalSampleBuffer)
        } else {
            print("adaptor doesn't exist or isn't ready for audio data")
        }
    }

    func stopRecording() {
        stopped = true

        guard let unwrappedClipWriterVideoInput = clipWriterVideoInput,
              let unwrappedClipWriterAudioInput = clipWriterAudioInput else {
            return
        }

        if clipWriter.status.rawValue == 1 {
            unwrappedClipWriterVideoInput.markAsFinished()
            unwrappedClipWriterAudioInput.markAsFinished()
            print("clip finished")
        } else {
            print("clip not written, clipWriter status: \(clipWriter.status.rawValue)")
        }

        clipWriter.finishWriting {
            print(self.clipWriter.error ?? "finished writing ok")
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

    func statusString() -> String {
        if internalBufferCount == 0 {
            return "Recording Clip - Starting"
        }
        if stopped {
            return String(format: "Recorded Clip - %.2f\" - Done", CMTimeGetSeconds(recordDuration))
        }
        return String(format: "Recording Clip - %.2f\"", CMTimeGetSeconds(recordDuration))
    }

}
