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
import CoreML
import CoreVideo
import AVFoundation
import AVKit

public enum SRError: Error {
    case pixelBufferLockingError(CVReturn)
    case pixelBufferCreateError(CVReturn)
    case pixelBufferBaseAddressNil
    case sampleTimingInfoInvalid(OSStatus)
    case sampleDescriptionCreateError(OSStatus)
    case sampleBufferCreateError(OSStatus)
    case modelOutputSizeMismatch
    case modelOutputInvalid
    case userCancelled
    case tracksNotFound
}

public typealias Size = (width: Int, height: Int)
public typealias Coordinate = (x: Int, y: Int)

public struct Waifu2xModelOptions {
    public var inputBlockWidth: Int
    public var inputBlockMargin: Int
    public var outputBlockWidth: Int
    public var inputOutputRatio: Int
    
    public init(inputBlockWidth: Int, inputBlockMargin: Int, outputBlockWidth: Int, inputOutputRatio: Int) {
        self.inputBlockWidth = inputBlockWidth
        self.inputBlockMargin = inputBlockMargin
        self.outputBlockWidth = outputBlockWidth
        self.inputOutputRatio = inputOutputRatio
    }
}

public class Waifu2xModelBlockProvider: MLFeatureProvider {
    public static let CLIP_ETA8 = (1.0 / 255.0) * 0.5 - (1.0e-7 * (1.0 / 255.0) * 0.5)
    
    public var featureNames: Set<String> = [ "input" ]
    
    public let frameBuffer: CVPixelBuffer
    public let frameSize: Size
    public let origin: Coordinate
    public let options: Waifu2xModelOptions
    
    private var _cachedFeatureValue: MLFeatureValue?
    
    public init(_ frameBuffer: CVPixelBuffer,
         origin: Coordinate,
         frameSize: Size,
         options: Waifu2xModelOptions) {
        self.frameBuffer = frameBuffer
        self.frameSize = frameSize
        self.origin = origin
        self.options = options
    }
    
    public func featureValue(for featureName: String) -> MLFeatureValue? {
        guard featureName == "input" else { return nil }
        
        if let cached = self._cachedFeatureValue {
            return cached
        }
        
        do {
            let completeInputBlockWidth = options.inputBlockWidth + options.inputBlockMargin * 2
            let channelSize = completeInputBlockWidth * completeInputBlockWidth
            let featureValue = try MLMultiArray(
                shape: [
                    3,
                    NSNumber(value: completeInputBlockWidth),
                    NSNumber(value: completeInputBlockWidth)
                ],
                dataType: .double
            )
            
            let rChPtr = featureValue
                .dataPointer
                .assumingMemoryBound(to: Double.self)
            let gChPtr = rChPtr.advanced(by: channelSize)
            let bChPtr = gChPtr.advanced(by: channelSize)
            
            let pixelBufferLockStatus = CVPixelBufferLockBaseAddress(
                self.frameBuffer,
                .readOnly
            )
            defer { CVPixelBufferUnlockBaseAddress(self.frameBuffer, .readOnly) }
            
            if pixelBufferLockStatus != kCVReturnSuccess {
                throw SRError.pixelBufferLockingError(pixelBufferLockStatus)
            }
            
            guard let pixelBufferPtr = CVPixelBufferGetBaseAddress(self.frameBuffer)?.assumingMemoryBound(to: UInt8.self) else {
                throw SRError.pixelBufferBaseAddressNil
            }
            
            let validXCoords = (0...self.frameSize.width - 1)
            let validYCoords = (0...self.frameSize.height - 1)
            
            for y in 0..<completeInputBlockWidth {
                for x in 0..<completeInputBlockWidth {
                    let srcX = validXCoords.clamp(value: x + self.origin.x)
                    let srcY = validYCoords.clamp(value: y + self.origin.y)
                    let srcPixelPtr = pixelBufferPtr
                        .advanced(by: srcY * self.frameSize.width * 4 + srcX * 4)
                    let dstOffset = y * completeInputBlockWidth + x
                    rChPtr.advanced(by: dstOffset).pointee =
                        Double(srcPixelPtr.advanced(by: 1).pointee) / 255.0
                        + Waifu2xModelBlockProvider.CLIP_ETA8
                    gChPtr.advanced(by: dstOffset).pointee =
                        Double(srcPixelPtr.advanced(by: 2).pointee) / 255.0
                        + Waifu2xModelBlockProvider.CLIP_ETA8
                    bChPtr.advanced(by: dstOffset).pointee =
                        Double(srcPixelPtr.advanced(by: 3).pointee) / 255.0
                        + Waifu2xModelBlockProvider.CLIP_ETA8
                }
            }
            
            let mlFeatureValue = MLFeatureValue(multiArray: featureValue)
            self._cachedFeatureValue = mlFeatureValue
            return mlFeatureValue
        } catch {
            debugPrint("[Waifu2xModelBlockProvider] Error obtaining feature value at \(origin). Error: \(error)")
        }
        
        return nil
    }
}

public class Waifu2xModelFrameBatchProvider: MLBatchProvider {
    private(set) var frameBuffer: CVPixelBuffer
    
    public let options: Waifu2xModelOptions
    public let frameSize: Size
    public let gridDimension: Coordinate
    
    public var count: Int { gridDimension.x * gridDimension.y }
    
    private var _cachedFeatures = [Int: Waifu2xModelBlockProvider]()
    
    public func features(at index: Int) -> MLFeatureProvider {
        if let cached = self._cachedFeatures[index] {
            return cached
        }
        
        let gridCoordinate = (
            x: index % gridDimension.x,
            y: index / gridDimension.x
        )
        
        let blockProvider = Waifu2xModelBlockProvider(
            self.frameBuffer,
            origin: (
                x: gridCoordinate.x * self.options.inputBlockWidth - self.options.inputBlockMargin,
                y: gridCoordinate.y * self.options.inputBlockWidth - self.options.inputBlockMargin
            ),
            frameSize: self.frameSize,
            options: self.options
        )
        
        self._cachedFeatures[index] = blockProvider
        return blockProvider
    }
    
    public init(_ frameBuffer: CVPixelBuffer, options: Waifu2xModelOptions) throws {
        self.frameBuffer = frameBuffer
        self.options = options
        
        self.frameSize = (
            width: CVPixelBufferGetWidth(frameBuffer),
            height: CVPixelBufferGetHeight(frameBuffer)
        )
        self.gridDimension = (
            Int(ceil(Double(self.frameSize.width) / Double(options.inputBlockWidth))),
            Int(ceil(Double(self.frameSize.height) / Double(options.inputBlockWidth)))
        )
    }
}

public class Waifu2xModelOutputCollector {
    public let outputSize: Size
    public let options: Waifu2xModelOptions
    public let gridDimension: Size
    
    public init(outputSize: Size, options: Waifu2xModelOptions) {
        self.outputSize = outputSize
        self.options = options
        self.gridDimension = (
            Int(ceil(Double(outputSize.width) / Double(options.outputBlockWidth))),
            Int(ceil(Double(outputSize.height) / Double(options.outputBlockWidth)))
        )
    }
    
    public func collect(_ provider: MLBatchProvider) throws -> CVPixelBuffer {
        let expectedBlockCount = self.gridDimension.width * self.gridDimension.height
        
        guard provider.count == expectedBlockCount else {
            throw SRError.modelOutputSizeMismatch
        }
        
        let outputBlocks = (0..<provider.count).compactMap {
            provider.features(at: $0)
                .featureValue(for: "conv7")?
                .multiArrayValue
        }
        
        guard outputBlocks.count == expectedBlockCount else {
            throw SRError.modelOutputInvalid
        }
        
        var outputPixelBufferRaw: CVPixelBuffer?
        let pixelBufferCreateResult = CVPixelBufferCreate(
            kCFAllocatorDefault,
            self.outputSize.width,
            self.outputSize.height,
            kCVPixelFormatType_32ARGB,
            nil,
            &outputPixelBufferRaw
        )
        
        guard pixelBufferCreateResult == kCVReturnSuccess,
            let outputPixelBuffer = outputPixelBufferRaw else {
            throw SRError.pixelBufferCreateError(pixelBufferCreateResult)
        }
        
        let pixelBufLockResult = CVPixelBufferLockBaseAddress(outputPixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(outputPixelBuffer, []) }
        
        guard pixelBufLockResult == kCVReturnSuccess else {
            throw SRError.pixelBufferLockingError(pixelBufLockResult)
        }
        
        guard let outputPixelBufferPtr = CVPixelBufferGetBaseAddress(outputPixelBuffer)?
            .assumingMemoryBound(to: UInt8.self) else {
            throw SRError.pixelBufferBaseAddressNil
        }
        
        let channelSize = self.options.outputBlockWidth * self.options.outputBlockWidth
        let validRgb = 0...255
        
        for blockY in 0..<self.gridDimension.height {
            for blockX in 0..<self.gridDimension.width {
                let blockPredictionResult = outputBlocks[
                    blockY * self.gridDimension.width + blockX
                ]
                
                let rChPtr = blockPredictionResult
                    .dataPointer
                    .assumingMemoryBound(to: Double.self)
                let gChPtr = rChPtr.advanced(by: channelSize)
                let bChPtr = gChPtr.advanced(by: channelSize)
                
                let blockOrigin = Coordinate(
                    blockX * self.options.outputBlockWidth,
                    blockY * self.options.outputBlockWidth
                )
                let blockEndpoint = Coordinate(
                    min(
                        blockX * self.options.outputBlockWidth + self.options.outputBlockWidth,
                        self.outputSize.width
                    ),
                    min(
                        blockY * self.options.outputBlockWidth + self.options.outputBlockWidth,
                        self.outputSize.height
                    )
                )
                
                for y in blockOrigin.y..<blockEndpoint.y {
                    let localY = y - blockOrigin.y
                    let lineOffset = y * self.outputSize.width
                    let localLineOffset = localY * self.options.outputBlockWidth
                    
                    for x in blockOrigin.x..<blockEndpoint.x {
                        let localX = x - blockOrigin.x
                        let dstOffset = (lineOffset + x) * 4
                        let localOffset = localLineOffset + localX
                        
                        let dstPixelPtr = outputPixelBufferPtr.advanced(by: dstOffset)
                        
                        dstPixelPtr.pointee = 255 //a
                        dstPixelPtr.advanced(by: 1).pointee = UInt8(
                            validRgb.clamp(
                                value: Int(rChPtr.advanced(by: localOffset).pointee * 255)
                            )
                        )
                        dstPixelPtr.advanced(by: 2).pointee = UInt8(
                            validRgb.clamp(
                                value: Int(gChPtr.advanced(by: localOffset).pointee * 255)
                            )
                        )
                        dstPixelPtr.advanced(by: 3).pointee = UInt8(
                            validRgb.clamp(
                                value: Int(bChPtr.advanced(by: localOffset).pointee * 255)
                            )
                        )
                    }
                }
            }
        }
        
        return outputPixelBuffer
    }
}

public func createSampleBuffer(reference: CMSampleBuffer, pixelBuffer: CVPixelBuffer) throws -> CMSampleBuffer {
    var referenceTimingInfo = CMSampleTimingInfo()
    let getTimingInfoResult = CMSampleBufferGetSampleTimingInfo(
        reference,
        at: 0,
        timingInfoOut: &referenceTimingInfo
    )
    
    guard getTimingInfoResult == 0 else {
        throw SRError.sampleTimingInfoInvalid(getTimingInfoResult)
    }
    
    var formatDescriptionRaw: CMVideoFormatDescription?
    let createFormatDescRes = CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &formatDescriptionRaw
    )
    
    guard createFormatDescRes == 0, let formatDescription = formatDescriptionRaw else {
        throw SRError.sampleDescriptionCreateError(createFormatDescRes)
    }
    
    var sampleBufferRaw: CMSampleBuffer?
    let sampleBufferCreateRes = CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescription: formatDescription,
        sampleTiming: &referenceTimingInfo,
        sampleBufferOut: &sampleBufferRaw
    )
    
    guard sampleBufferCreateRes == 0, let sampleBuffer = sampleBufferRaw else {
        throw SRError.sampleBufferCreateError(sampleBufferCreateRes)
    }
    
    return sampleBuffer
}
