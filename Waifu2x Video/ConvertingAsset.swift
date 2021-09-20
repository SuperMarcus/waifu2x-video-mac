//
//  This file is part of the Waifu2x Video project.
//
//  Copyright © 2018-2020 Marcus Zhou. All rights reserved.
//
//  Waifu2x Video is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Waifu2x Video is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with Waifu2x Video.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import AVKit
import CoreML

class ConvertingAsset: Hashable, ObservableObject {
    static var allowedCodecs: [AVVideoCodecType] {
        [ .h264, .hevc ]
    }
    
    let inputUrl: URL
    
    @Published var name: String
    @Published var outputUrl: URL
    @Published var outputFileType: AVFileType
    @Published var outputCodec: AVVideoCodecType = .h264
    @Published var model = Model.default
    @Published var generatedPreview: CGImage?
    @Published var currentState: State = .queued
    @Published var error: Error?
    @Published var currentProgress: Double = 0
    @Published var preferredHardwareDeviceId: UInt64 = MTLCreateSystemDefaultDevice()?.registryID ?? 0
    
    private(set) var currentFramesPerSecond: Double = 0
    private(set) var startTime: Date?
    private(set) var inputResolution: CGSize = .zero
    
    var outputResolution: CGSize {
        CGSize(
            width: inputResolution.width * CGFloat(model.options.inputOutputRatio),
            height: inputResolution.height * CGFloat(model.options.inputOutputRatio)
        )
    }
    
    var avAsset: AVAsset {
        AVAsset(url: inputUrl)
    }
    
    var formattedProgress: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumSignificantDigits = 3
        return formatter.string(from: NSNumber(value: currentProgress)) ?? "\(currentProgress)"
    }
    
    var currentStateDescription: String {
        currentState == .processing && _interruptFlag ? "Cancelling" : currentState.rawValue
    }
    
    private var _interruptFlag = false
    private var _isGeneratingAsset = false
    private var _assetReader: AVAssetReader?
    private var _assetWriter: AVAssetWriter?
    private var _processingQueue = DispatchQueue(
        label: "com.marcuszhou.Waifu2x-Video.queue.processing",
        qos: .default
    )
    private var _videoTrackQueue = DispatchQueue(
        label: "com.marcuszhou.Waifu2x-Video.queue.processing.videoTrack",
        qos: .default
    )
    private var _audioTrackQueue = DispatchQueue(
        label: "com.marcuszhou.Waifu2x-Video.queue.processing.audioTrack",
        qos: .default
    )
    private var _audioTrackDidFinish: Bool = false
    private var _videoTrackDidFinish: Bool = false
    private var _previousFrameTimestamp: Date?
    
    init(name: String, inputUrl: URL, outputUrl: URL, outputFileType: AVFileType) {
        self.name = name
        self.inputUrl = inputUrl
        self.outputUrl = outputUrl
        self.outputFileType = outputFileType
    }
    
    func reset() {
        if self.currentState == .processing {
            self.cancel()
        } else {
            self.currentState = .queued
            self.currentProgress = 0
            self.error = nil
        }
    }
    
    func beginConversion() {
        guard currentState != .processing else {
            return
        }
        
        self.currentState = .processing
        self._interruptFlag = false
        self.startTime = Date()
        _processingQueue.async {
            do {
                try self._configureForConversion()
            } catch {
                DispatchQueue.main.sync {
                    self.currentState = .failed
                    self.error = error
                }
                print("[ConvertingAsset] Conversion failed with error: \(error)")
            }
        }
    }
    
    func generatePreview() {
        if generatedPreview == nil && !_isGeneratingAsset {
            _isGeneratingAsset = true
            let asset = avAsset
            guard let videoTrack = asset.tracks(withMediaType: .video).first else {
                return
            }
            self.inputResolution = videoTrack.naturalSize
            
            let duration = asset.duration
            let samplingTime = CMTime(
                value: CMTimeValue(Double(duration.value) * 0.3),
                timescale: duration.timescale
            )
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.generateCGImagesAsynchronously(forTimes: [ NSValue(time: samplingTime) ]) {
                [weak self] _, image, _, _, _ in DispatchQueue.main.async {
                    if self?.generatedPreview != image {
                        self?.generatedPreview = image
                    }
                    
                    self?._isGeneratingAsset = false
                }
            }
        }
    }
    
    func cancel() {
        print("[ConvertingAsset] Cancelling operations...")
        _interruptFlag = true
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(inputUrl)
    }
    
    private func _updateFps() {
        let now = Date()
        
        if let previous = _previousFrameTimestamp {
            let elapsed = now.timeIntervalSince(previous)
            self.currentFramesPerSecond = 1.0 / elapsed
        }
        
        _previousFrameTimestamp = now
    }
    
    private func _configureForConversion() throws {
        print("[SR] Beginning task...")
        print("[SR] Input: \(inputUrl.absoluteString)")
        print("[SR] Output: \(outputUrl.absoluteString)")
        
        let avAsset = self.avAsset
        guard let sampleVideoTrack = avAsset.tracks(withMediaType: .video).first,
            let sampleAudioTrack = avAsset.tracks(withMediaType: .audio).first else {
            throw SRError.tracksNotFound
        }
        let sampleVideoSize = sampleVideoTrack.naturalSize
        let outputVideoSize = CGSize(
            width: sampleVideoSize.width * CGFloat(model.options.inputOutputRatio),
            height: sampleVideoSize.height * CGFloat(model.options.inputOutputRatio)
        )
        let sampleVideoDuration = CMTimeGetSeconds(avAsset.duration)
        
        // Setup model
        let modelConfig = MLModelConfiguration()
        
        modelConfig.preferredMetalDevice = MTLCopyAllDevices().first {
            $0.registryID == self.preferredHardwareDeviceId
        } ?? MTLCreateSystemDefaultDevice()
        
        if let preferredDevice = modelConfig.preferredMetalDevice {
            print("[SR] Using metal device: '\(preferredDevice.name)'")
        }
        
        let predictionModel = try self.model.mlModel(config: modelConfig)
        
        // Setup reader
        let assetReader = try AVAssetReader(asset: avAsset)
        self._assetReader = assetReader
        let frameReadOutput = AVAssetReaderTrackOutput(
            track: sampleVideoTrack,
            outputSettings: [
                String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32ARGB
            ]
        )
        let audioReadOutput = AVAssetReaderTrackOutput(
            track: sampleAudioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM
            ]
        )
        frameReadOutput.alwaysCopiesSampleData = false
        assetReader.add(frameReadOutput)
        assetReader.add(audioReadOutput)
        
        // Remove existing file
        if FileManager.default.fileExists(atPath: outputUrl.path) {
            print("[SR] Removing existing file at output location...")
            try FileManager.default.removeItem(at: outputUrl)
        }
        
        // Setup writer
        let assetWriter = try AVAssetWriter(outputURL: outputUrl, fileType: .mov)
        self._assetWriter = assetWriter
        
        let srFrameOutput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: outputCodec,
                AVVideoWidthKey: NSNumber(value: Int(outputVideoSize.width)),
                AVVideoHeightKey: NSNumber(value: Int(outputVideoSize.height))
            ]
        )
        srFrameOutput.expectsMediaDataInRealTime = false

        let srAudioOutput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: nil
        )

        assetWriter.add(srFrameOutput)
        assetWriter.add(srAudioOutput)
                
        // Reset flags
        self._audioTrackDidFinish = false
        self._videoTrackDidFinish = false
        
        // Start reading and writing
        assetReader.startReading()
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
        
        print("[ConvertingAsset] Current reader status is \(assetReader.status.rawValue), writer status is \(assetWriter.status.rawValue)")
        
        // Process frames
        srFrameOutput.requestMediaDataWhenReady(on: _videoTrackQueue) { [weak self] in
            guard let self = self else { return }
            let cleanup = {
                self._videoTrackDidFinish = true
                srFrameOutput.markAsFinished()
                self._onTrackFinish()
            }
            
            do {
                while srFrameOutput.isReadyForMoreMediaData {
                    try autoreleasepool {
                        if self._interruptFlag {
                            DispatchQueue.main.sync {
                                self.currentState = .queued
                                cleanup()
                            }
                            return
                        }
                        
                        if assetReader.status != .reading {
                            if let error = assetReader.error {
                                DispatchQueue.main.sync {
                                    print("[SR] Reader error: \(error)")
                                    self._interruptFlag = true
                                    self.error = error
                                    self.currentState = .failed
                                }
                            }
                            cleanup()
                            return
                        }
                        
                        if assetWriter.status == .failed {
                            DispatchQueue.main.sync {
                                print("[SR] Reader error: \(assetWriter.error!)")
                                self._interruptFlag = true
                                self.error = assetWriter.error
                                self.currentState = .failed
                                cleanup()
                            }
                            return
                        }
                        
                        guard let frameBuf = frameReadOutput.copyNextSampleBuffer() else {
                            print("[SR] Reached the end of video frames.")
                            cleanup()
                            return
                        }
                        let frameImgBuf = CMSampleBufferGetImageBuffer(frameBuf)!
                        
                        let frameTimestamp = CMSampleBufferGetPresentationTimeStamp(frameBuf)
                        let frameTime = CMTimeGetSeconds(frameTimestamp)
                        
                        DispatchQueue.main.async {
                            self._updateFps()
                            self.currentProgress = Double(frameTime / sampleVideoDuration)
                        }

                        let frameWidth = CVPixelBufferGetWidth(frameImgBuf)
                        let frameHeight = CVPixelBufferGetHeight(frameImgBuf)

                        let batchProvider = try Waifu2xModelFrameBatchProvider(frameImgBuf, options: self.model.options)
                        let predictions = try predictionModel.predictions(fromBatch: batchProvider)
                        

                        let outputCollector = Waifu2xModelOutputCollector(
                            outputSize: (
                                frameWidth * self.model.options.inputOutputRatio,
                                frameHeight * self.model.options.inputOutputRatio
                            ),
                            options: self.model.options
                        )

                        let srFrame = try outputCollector.collect(predictions)

                        let srFrameBuf = try createSampleBuffer(
                            reference: frameBuf,
                            pixelBuffer: srFrame
                        )

                        srFrameOutput.append(srFrameBuf)
                    }
                }
            } catch {
                DispatchQueue.main.sync {
                    print("[SR] Errored: \(error)")
                    self._interruptFlag = true
                    self.error = error
                    self.currentState = .failed
                    cleanup()
                }
            }
        }

        srAudioOutput.requestMediaDataWhenReady(on: _audioTrackQueue) { [weak self] in
            guard let self = self else { return }
            let cleanup = {
                self._audioTrackDidFinish = true
                srAudioOutput.markAsFinished()
                self._onTrackFinish()
            }
            
            while srAudioOutput.isReadyForMoreMediaData {
                autoreleasepool {
                    if self._interruptFlag {
                        cleanup()
                        return
                    }
                    
                    if assetReader.status != .reading {
                        cleanup()
                        return
                    }
                    
                    guard let nextSample = audioReadOutput.copyNextSampleBuffer() else {
                        print("[SR] Reached the end of audio track.")
                        cleanup()
                        return
                    }
                    
                    srAudioOutput.append(nextSample)
                }
            }
        }
    }
    
    private func _onTrackFinish() {
        if _audioTrackDidFinish && _videoTrackDidFinish {
            if let writer = self._assetWriter {
                writer.finishWriting {
                    DispatchQueue.main.async {
                        print("[SR] Finished writing to file.")
                        self._assetReader = nil
                        self._assetWriter = nil
                        self.currentProgress = 1.0
                        
                        if self.currentState == .processing {
                            self.currentState = .finished
                        }
                    }
                }
            }
        }
    }
    
    static func == (lhs: ConvertingAsset, rhs: ConvertingAsset) -> Bool {
        lhs.inputUrl == rhs.inputUrl
    }
}

extension ConvertingAsset {
    enum State: String {
        case queued = "Queued"
        case processing = "Processing"
        case finished = "Finished"
        case failed = "Failed"
    }
    
    struct Model: Hashable, Equatable {
        var mlModelUrl: URL
        var options: Waifu2xModelOptions
        var name: String
        
        func mlModel(config: MLModelConfiguration) throws -> MLModel {
            try MLModel(contentsOf: mlModelUrl, configuration: config)
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(self.mlModelUrl)
        }
        
        static func ==(lhs: Model, rhs: Model) -> Bool {
            lhs.mlModelUrl == rhs.mlModelUrl
        }
    }
}

extension ConvertingAsset.Model {
    static let `default` = ConvertingAsset.Model.anime_noise1_scale2
    
    static var all: [ConvertingAsset.Model] {
        [
            anime_noise0_scale2,
            anime_noise1_scale2,
            anime_noise2_scale2,
            anime_noise3_scale2,
            realistic_noise0_scale2,
            realistic_noise1_scale2,
            realistic_noise2_scale2,
            realistic_noise3_scale1,
            anime_noise0_scale1,
            anime_noise1_scale1,
            anime_noise2_scale1,
            anime_noise3_scale1,
            realistic_noise0_scale1,
            realistic_noise1_scale1,
            realistic_noise2_scale1,
            realistic_noise3_scale1
        ]
    }
    
    static let anime_noise0_scale2 = ConvertingAsset.Model(
        mlModelUrl: waifu2x_anime_noise0_scale2.urlOfModelInThisBundle,
        options: scale2ModelOptions,
        name: "Anime Denoise 0 Scale 2x"
    )
    
    static let anime_noise1_scale2 = ConvertingAsset.Model(
        mlModelUrl: waifu2x_anime_noise1_scale2.urlOfModelInThisBundle,
        options: scale2ModelOptions,
        name: "Anime Denoise 1 Scale 2x"
    )
    
    static let anime_noise2_scale2 = ConvertingAsset.Model(
        mlModelUrl: waifu2x_anime_noise2_scale2.urlOfModelInThisBundle,
        options: scale2ModelOptions,
        name: "Anime Denoise 2 Scale 2x"
    )
    
    static let anime_noise3_scale2 = ConvertingAsset.Model(
        mlModelUrl: waifu2x_anime_noise3_scale2.urlOfModelInThisBundle,
        options: scale2ModelOptions,
        name: "Anime Denoise 3 Scale 2x"
    )
    
    static let realistic_noise0_scale2 = ConvertingAsset.Model(
        mlModelUrl: waifu2x_photo_noise0_scale2.urlOfModelInThisBundle,
        options: scale2ModelOptions,
        name: "Realistic Denoise 0 Scale 2x"
    )
    
    static let realistic_noise1_scale2 = ConvertingAsset.Model(
        mlModelUrl: waifu2x_photo_noise1_scale2.urlOfModelInThisBundle,
        options: scale2ModelOptions,
        name: "Realistic Denoise 1 Scale 2x"
    )
    
    static let realistic_noise2_scale2 = ConvertingAsset.Model(
        mlModelUrl: waifu2x_photo_noise2_scale2.urlOfModelInThisBundle,
        options: scale2ModelOptions,
        name: "Realistic Denoise 2 Scale 2x"
    )
    
    static let realistic_noise3_scale2 = ConvertingAsset.Model(
        mlModelUrl: waifu2x_photo_noise3_scale2.urlOfModelInThisBundle,
        options: scale2ModelOptions,
        name: "Realistic Denoise 3 Scale 2x"
    )
    
    static let anime_noise0_scale1 = ConvertingAsset.Model(
        mlModelUrl: waifu2x_anime_noise0_scale1.urlOfModelInThisBundle,
        options: scale1ModelOptions,
        name: "Anime Denoise 0 Scale 1x"
    )
    
    static let anime_noise1_scale1 = ConvertingAsset.Model(
        mlModelUrl: waifu2x_anime_noise1_scale1.urlOfModelInThisBundle,
        options: scale1ModelOptions,
        name: "Anime Denoise 1 Scale 1x"
    )
    
    static let anime_noise2_scale1 = ConvertingAsset.Model(
        mlModelUrl: waifu2x_anime_noise2_scale1.urlOfModelInThisBundle,
        options: scale1ModelOptions,
        name: "Anime Denoise 2 Scale 1x"
    )
    
    static let anime_noise3_scale1 = ConvertingAsset.Model(
        mlModelUrl: waifu2x_anime_noise3_scale1.urlOfModelInThisBundle,
        options: scale1ModelOptions,
        name: "Anime Denoise 3 Scale 1x"
    )
    
    static let realistic_noise0_scale1 = ConvertingAsset.Model(
        mlModelUrl: waifu2x_photo_noise0_scale1.urlOfModelInThisBundle,
        options: scale1ModelOptions,
        name: "Realistic Denoise 0 Scale 1x"
    )
    
    static let realistic_noise1_scale1 = ConvertingAsset.Model(
        mlModelUrl: waifu2x_photo_noise1_scale1.urlOfModelInThisBundle,
        options: scale1ModelOptions,
        name: "Realistic Denoise 1 Scale 1x"
    )
    
    static let realistic_noise2_scale1 = ConvertingAsset.Model(
        mlModelUrl: waifu2x_photo_noise2_scale1.urlOfModelInThisBundle,
        options: scale1ModelOptions,
        name: "Realistic Denoise 2 Scale 1x"
    )
    
    static let realistic_noise3_scale1 = ConvertingAsset.Model(
        mlModelUrl: waifu2x_photo_noise3_scale1.urlOfModelInThisBundle,
        options: scale1ModelOptions,
        name: "Realistic Denoise 3 Scale 1x"
    )
    
    static let scale2ModelOptions = Waifu2xModelOptions(
        inputBlockWidth: 142,
        inputBlockMargin: 7,
        outputBlockWidth: 284,
        inputOutputRatio: 2
    )
    
    static let scale1ModelOptions = Waifu2xModelOptions(
        inputBlockWidth: 128,
        inputBlockMargin: 7,
        outputBlockWidth: 128,
        inputOutputRatio: 1
    )
}

let sampleAsset = ConvertingAsset(
    name: "Sample Video Clip",
    inputUrl: Bundle.main.url(forResource: "sample", withExtension: "mov")!,
    outputUrl: FileManager.default.temporaryDirectory.appendingPathComponent("sample_output.mov"),
    outputFileType: .mov
)
