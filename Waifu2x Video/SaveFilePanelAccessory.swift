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
import AVFoundation

struct SaveFilePanelAccessory: View {
    weak var savePanel: NSSavePanel?
    @ObservedObject var options: NewAssetOptions
    
    let allowedFileTypes: [AVFileType] = [
        .mp4, .m4v, .mov
    ]
    
    var body: some View {
        VStack(alignment: .center) {
            HStack {
                Picker(selection: self.$options.outputFormat, label: Text("Output Format")) {
                    ForEach(self.allowedFileTypes, id: \.rawValue) {
                        type in Text(type.description)
                            .tag(type)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 400, alignment: .center)
        .onReceive(self.options.$outputFormat) {
            newOutputFormat in
            guard let savePanel = self.savePanel else {
                return
            }
            
            let newExtension = newOutputFormat.fileExtension
            let currentUrl = URL(fileURLWithPath: savePanel.nameFieldStringValue)
            let newFileName = currentUrl
                .deletingPathExtension()
                .appendingPathExtension(newExtension)
                .lastPathComponent
            savePanel.nameFieldStringValue = newFileName
            savePanel.allowedFileTypes = [
                newExtension
            ]
        }
    }
}
