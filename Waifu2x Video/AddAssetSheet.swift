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

struct AddAssetSheet: View {
    @ObservedObject var observing: ContentViewObserving
    @ObservedObject var newAssetConfig = NewAssetOptions()
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Create Task...")
                .animation(nil)
                .multilineTextAlignment(.leading)
                .padding(.bottom, 6)
            
            HStack {
                Text(newAssetConfig.inputPath == nil
                    ? "No Input Specified"
                    : newAssetConfig.inputPath!.path
                )
                .truncationMode(.middle)
                .lineLimit(1)
                .foregroundColor(Color.secondary)
                
                Spacer()
                
                Button(action: {
                    let selectFilePanel = NSOpenPanel()
                    selectFilePanel.prompt = "Select Input"
                    selectFilePanel.worksWhenModal = true
                    selectFilePanel.allowsMultipleSelection = false
                    selectFilePanel.canChooseDirectories = false
                    selectFilePanel.canChooseFiles = true
                    selectFilePanel.resolvesAliases = true
                    
                    let supportedTypes = AVURLAsset.audiovisualTypes()
                    selectFilePanel.allowedFileTypes = supportedTypes.map {
                        $0.rawValue
                    }
                    
                    selectFilePanel.begin {
                        response in
                        if response == .OK, let url = selectFilePanel.url,
                            self.validateInput(url: url) {
                            self.newAssetConfig.inputPath = url
                            self.newAssetConfig.note = self.generateDescription(forUrl: url)
                        }
                    }
                }) {
                    Text("Select Input").frame(width: 85)
                }
            }
            .animation(nil)
            
            HStack {
                Text(newAssetConfig.outputPath == nil
                    ? "No Output Specified"
                    : newAssetConfig.outputPath!.path
                )
                .truncationMode(.middle)
                .lineLimit(1)
                .foregroundColor(Color.secondary)
                
                Spacer()
                
                Button(action: {
                    let saveFilePanel = NSSavePanel()
                    saveFilePanel.prompt = "Save"
                    saveFilePanel.isExtensionHidden = false
                    
                    if let inputPath = self.newAssetConfig.inputPath {
                        let inputFileName = inputPath
                            .deletingPathExtension()
                            .lastPathComponent
                        
                        saveFilePanel.directoryURL = inputPath.deletingLastPathComponent()
                        saveFilePanel.nameFieldStringValue = "\(inputFileName)_Waifu2x_Video"
                    }
                    
                    saveFilePanel.accessoryView = NSHostingView(
                        rootView: SaveFilePanelAccessory(
                            savePanel: saveFilePanel,
                            options: self.newAssetConfig
                        )
                    )
                    
                    saveFilePanel.begin {
                        response in
                        if response == .OK, let url = saveFilePanel.url {
                            self.newAssetConfig.outputPath = url
                        }
                    }
                }) {
                    Text("Select Output").frame(width: 85)
                } .disabled(self.newAssetConfig.inputPath == nil)
            }
            .animation(nil)
            
            if self.newAssetConfig.note != nil {
                Text(self.newAssetConfig.note!)
                    .padding(.vertical, 6)
            }
            
            Spacer()
            
            HStack {
                Spacer()
                
                Button(action: {
                    guard let assetInput = self.newAssetConfig.inputPath,
                        let assetOutput = self.newAssetConfig.outputPath else {
                        return
                    }
                    let assetName = assetInput
                        .deletingPathExtension()
                        .lastPathComponent
                    let convertingAsset = ConvertingAsset(
                        name: assetName,
                        inputUrl: assetInput,
                        outputUrl: assetOutput,
                        outputFileType: self.newAssetConfig.outputFormat
                    )
                    self.observing.tasks.append(convertingAsset)
                    self.observing.currentlyPresentingTask = convertingAsset
                    self.observing.presentActionSheet = false
                }) {
                    Text("Add")
                } .disabled(newAssetConfig.inputPath == nil || newAssetConfig.outputPath == nil)
                
                Button(action: {
                    self.observing.presentActionSheet = false
                }) {
                    Text("Cancel")
                }
            } .padding(.top, 8)
        }
        .animation(.default)
        .padding(12)
        .frame(width: 400, alignment: .topLeading)
    }
    
    private func validateInput(url: URL) -> Bool {
        guard AVAsset(url: url).isReadable else {
            self.newAssetConfig.note = "Error: The selected file is invalid."
            return false
        }
        
        if observing.tasks.contains(where: { $0.inputUrl == url }) {
            self.newAssetConfig.note = "Error: Task already exists in the queue."
            return false
        }
        
        return true
    }
    
    private func generateDescription(forUrl url: URL) -> String {
        var descriptions = [String]()
        
        do {
            if let fileSize = try url.resourceValues(
                    forKeys: [.fileSizeKey]
                ).fileSize {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = .useAll
                formatter.countStyle = .file
                descriptions.append(formatter.string(fromByteCount: Int64(fileSize)))
            }
        } catch {
            print("[AddAssetSheet] Error retriving file parameters: \(error)")
        }
        
        let avAsset = AVAsset(url: url)
        
        // Duration
        let duration = TimeInterval(CMTimeGetSeconds(avAsset.duration))
        
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [ .hour, .minute, .second ]
        formatter.maximumUnitCount = 2
        
        if let durationString = formatter.string(from: duration) {
            descriptions.append(durationString)
        }
        
        if let videoTrack = avAsset.tracks(withMediaType: .video).first {
            // Frame Count
            let frameCount = Int(duration * Double(videoTrack.nominalFrameRate))
            descriptions.append("\(frameCount) frames")
        }
        
        return descriptions.joined(separator: ", ")
    }
}

class NewAssetOptions: ObservableObject {
    @Published var inputPath: URL? = nil
    @Published var outputPath: URL? = nil
    @Published var note: String?
    @Published var outputFormat: AVFileType = .mp4
}

struct AddAssetSheet_Previews: PreviewProvider {
    static var previews: some View {
        AddAssetSheet(observing: ContentViewObserving())
    }
}
