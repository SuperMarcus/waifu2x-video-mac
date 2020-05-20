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

import SwiftUI
import AVKit
import Metal
import CoreML

struct AssetConversionConfigurationView: View {
    @ObservedObject var asset: ConvertingAsset
    @ObservedObject var availableMetalDevices = MetalDeviceObserver()
    @EnvironmentObject var observing: ContentViewObserving
    
    var body: some View {
        return ScrollView(.vertical) {
            VStack {
                HStack {
                    previewImage()
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 150, height: 94)
                        .cornerRadius(6)
                        .shadow(radius: 4)
                        .clipped()
                    
                    VStack(alignment: .leading) {
                        Text(asset.name)
                            .font(.title)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(generateDescriptions())
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    } .padding(.leading, 8)
                    
                    Spacer()
                }
                .frame(height: 100)
                .padding(.bottom, 12)
                
                statusView
                detailedStatusView
                configurationView
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var statusIcon: Image {
        let image: NSImage
        
        switch asset.currentState {
        case .queued: image = NSImage(imageLiteralResourceName: NSImage.statusNoneName)
        case .processing: image = NSImage(imageLiteralResourceName: NSImage.statusPartiallyAvailableName)
        case .finished: image = NSImage(imageLiteralResourceName: NSImage.statusAvailableName)
        case .failed: image = NSImage(imageLiteralResourceName: NSImage.statusUnavailableName)
        }
        
        return Image(nsImage: image)
    }
    
    private var statusView: some View {
        VStack(alignment: .leading) {
            HStack {
                statusIcon
                Text(asset.currentStateDescription)
                Spacer()
                Text(progressString)
            }
            .animation(nil)
            
            if asset.currentState == .failed {
                HStack {
                    Text("Error: \(asset.error!.localizedDescription)")
                        .foregroundColor(Color.secondary)
                    Spacer()
                    Button(action: {
                        self.asset.reset()
                    }) {
                        Text("Reset")
                    }
                } .animation(nil)
            }
        }
        .animation(.default)
        .padding(12)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            alignment: .topLeading
        )
    }
    
    private var configurationView: some View {
        VStack {
            // Configurations
            HStack {
                Text("Input File")
                    .frame(width: 130, alignment: .leading)
                Spacer()
                Text(asset.inputUrl.path)
                    .truncationMode(.middle)
                    .lineLimit(1)
                    .foregroundColor(Color.secondary)
                Button(action: {
                    let assetInputUrl = self.asset.inputUrl
                    NSWorkspace.shared.selectFile(
                        assetInputUrl.path,
                        inFileViewerRootedAtPath: assetInputUrl
                            .deletingLastPathComponent()
                            .path
                    )
                }) {
                    Image(
                        nsImage: NSImage(
                            imageLiteralResourceName: NSImage.followLinkFreestandingTemplateName
                        )
                    )
                } .buttonStyle(PlainButtonStyle())
            }
            
            HStack {
                Text("Output Location")
                    .frame(width: 130, alignment: .leading)
                Spacer()
                Text(asset.outputUrl.path)
                    .truncationMode(.middle)
                    .lineLimit(1)
                    .foregroundColor(Color.secondary)
                
                if asset.currentState == .finished {
                    Button(action: {
                        let assetOutputUrl = self.asset.outputUrl
                        NSWorkspace.shared.selectFile(
                            assetOutputUrl.path,
                            inFileViewerRootedAtPath: assetOutputUrl
                                .deletingLastPathComponent()
                                .path
                        )
                    }) {
                        Image(
                            nsImage: NSImage(
                                imageLiteralResourceName: NSImage.followLinkFreestandingTemplateName
                            )
                        )
                    } .buttonStyle(PlainButtonStyle())
                } else {
                    Button(action: {
                        let saveFilePanel = NSSavePanel()
                        saveFilePanel.prompt = "Save"
                        saveFilePanel.isExtensionHidden = false
                        
                        let originalOutputUrl = self.asset.outputUrl
                        let assetOptions = NewAssetOptions()
                        assetOptions.inputPath = self.asset.inputUrl
                        assetOptions.outputPath = originalOutputUrl
                        assetOptions.outputFormat = self.asset.outputFileType
                        
                        saveFilePanel.accessoryView = NSHostingView(
                            rootView: SaveFilePanelAccessory(
                                savePanel: saveFilePanel,
                                options: assetOptions
                            )
                        )
                        
                        saveFilePanel.directoryURL = originalOutputUrl.deletingLastPathComponent()
                        saveFilePanel.nameFieldStringValue = originalOutputUrl.lastPathComponent
                        saveFilePanel.allowedFileTypes = [
                            assetOptions.outputFormat.fileExtension
                        ]
                        
                        saveFilePanel.begin {
                            response in
                            if response == .OK, let url = saveFilePanel.url {
                                self.asset.outputUrl = url
                                self.asset.outputFileType = assetOptions.outputFormat
                            }
                        }
                    }) {
                        Text("Change")
                    } .disabled(asset.currentState == .processing)
                }
            }
            
            Picker(
                selection: self.$asset.model,
                label: Text("Model")
                    .frame(width: 130, alignment: .leading)
            ) {
                ForEach(ConvertingAsset.Model.all, id: \.mlModelUrl) {
                    model in Text(model.name)
                        .tag(model)
                }
            } .disabled(asset.currentState == .processing)
            
            Picker(
                selection: self.$asset.outputCodec,
                label: Text("Output Codec")
                    .frame(width: 130, alignment: .leading)
            ) {
                ForEach(ConvertingAsset.allowedCodecs, id: \.rawValue) {
                    codec in Text(codec.description)
                        .tag(codec)
                }
            } .disabled(asset.currentState == .processing)
            
            Picker(
                selection: self.$asset.preferredHardwareDeviceId,
                label: Text("Compute Device")
                    .frame(width: 130, alignment: .leading)
            ) {
                ForEach(self.availableMetalDevices.devices, id: \.registryID) {
                    device in Text(device.name)
                        .tag(device.registryID)
                }
            } .disabled(asset.currentState == .processing)
        } .padding(6)
    }
    
    private var detailedStatusView: some View {
        var elapsedTime: String = "N/A"
        var startTime: String = "N/A"
        var startDate: String = "N/A"
        var currentFps: String = "0.00"
        
        if asset.currentState == .processing,
            let startTime = asset.startTime {
            let elapsedTimeFormatter = DateComponentsFormatter()
            elapsedTimeFormatter.unitsStyle = .full
            elapsedTimeFormatter.allowedUnits = [ .hour, .minute, .second ]
            elapsedTimeFormatter.maximumUnitCount = 2
            elapsedTime = elapsedTimeFormatter.string(
                from: startTime,
                to: Date()
            ) ?? elapsedTime
        }
        
        if let startTimeDate = asset.startTime {
            let startTimeFormatter = DateFormatter()
            
            startTimeFormatter.timeStyle = .long
            startTimeFormatter.dateStyle = .none
            startTime = startTimeFormatter.string(from: startTimeDate)
            
            startTimeFormatter.timeStyle = .none
            startTimeFormatter.dateStyle = .long
            startDate = startTimeFormatter.string(from: startTimeDate)
        }
        
        if asset.currentState == .processing {
            let fpsFormatter = NumberFormatter()
            fpsFormatter.numberStyle = .decimal
            fpsFormatter.minimumFractionDigits = 2
            fpsFormatter.maximumFractionDigits = 2
            
            if let formattedFps = fpsFormatter.string(from: .init(
                value: asset.currentFramesPerSecond
            )) {
                currentFps = formattedFps
            }
        }
        
        return VStack(spacing: 8) {
            HStack(spacing: 16) {
                LabelDetailView(
                    label: "Elapsed Time",
                    detail: elapsedTime
                )
                LabelDetailView(
                    label: "Start Time",
                    detail: startTime
                )
            }
            HStack(spacing: 16) {
                LabelDetailView(
                    label: "Current FPS",
                    detail: currentFps
                )
                LabelDetailView(
                    label: "Start Date",
                    detail: startDate
                )
            }
            HStack(spacing: 16) {
                LabelDetailView(
                    label: "Input Resolution",
                    detail: "\(Int(asset.inputResolution.width)) × \(Int(asset.inputResolution.height))"
                )
                LabelDetailView(
                    label: "Output Resolution",
                    detail: "\(Int(asset.outputResolution.width)) × \(Int(asset.outputResolution.height))"
                )
            }
            LabelDetailView(
                label: "Output File Format",
                detail: asset.outputFileType.description
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 12)
    }
    
    private var progressString: String {
        var progressBuilder = [String]()
        
        if asset.currentState == .queued,
            !observing.isProcessing {
            progressBuilder.append("Ready to Start")
        } else {
            progressBuilder.append(asset.formattedProgress)
        }
        
        return progressBuilder.joined(separator: ", ")
    }
    
    func generateDescriptions() -> String {
        var descriptions = [String]()
        
        let avAsset = asset.avAsset
        let videoTrack = avAsset
            .tracks(withMediaType: .video)
            .first
        
        // Current Model
        descriptions.append(asset.model.name)
        
        // Duration
        let duration = TimeInterval(CMTimeGetSeconds(avAsset.duration))
        
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [ .hour, .minute, .second ]
        formatter.maximumUnitCount = 2
        
        if let durationString = formatter.string(from: duration) {
            descriptions.append(durationString)
        }
        
        if let videoTrack = videoTrack {
            // Frame Count
            let frameCount = Int(duration * Double(videoTrack.nominalFrameRate))
            descriptions.append("\(frameCount) frames")
        }
        
        return descriptions.joined(separator: ", ")
    }
    
    func previewImage() -> Image {
        if let sampleImage = asset.generatedPreview {
            return Image(
                sampleImage,
                scale: 1,
                label: Text("Preview")
            )
        } else {
            asset.generatePreview()
            return Image("Question Mark Preview")
        }
    }
}

struct LabelDetailView: View {
    var label: String
    var detail: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(Color.primary)
                .lineLimit(1)
            Spacer()
            Text(detail)
                .foregroundColor(Color.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
    }
}

class MetalDeviceObserver: ObservableObject {
    @Published var devices = MTLCopyAllDevices()
    
    init() { }
}

struct AssetConversionConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        AssetConversionConfigurationView(
            asset: sampleAsset
        )
        .environmentObject(ContentViewObserving())
        .frame(width: 500, height: 600)
    }
}
