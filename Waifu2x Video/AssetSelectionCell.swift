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

struct AssetSelectionCell: View {
    var body: some View {
        VStack {
            HStack {
                Text(asset.name)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                
                Spacer()
            }
            Spacer()
            HStack {
//                statusIcon
                Text(asset.currentStateDescription)
                    .foregroundColor(.secondary)
                Spacer()
                
                if asset.currentState == .processing {
                    Text(asset.formattedProgress)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(height: 40.0)
        .padding(.vertical, 12.0)
    }
    
    @ObservedObject private(set) var asset: ConvertingAsset
    
    var statusIcon: Image {
        let image: NSImage
        
        switch asset.currentState {
        case .queued: image = NSImage(imageLiteralResourceName: NSImage.statusNoneName)
        case .processing: image = NSImage(imageLiteralResourceName: NSImage.statusPartiallyAvailableName)
        case .finished: image = NSImage(imageLiteralResourceName: NSImage.statusAvailableName)
        case .failed: image = NSImage(imageLiteralResourceName: NSImage.statusUnavailableName)
        }
        
        return Image(nsImage: image)
    }
    
    init(asset: ConvertingAsset) {
        self.asset = asset
    }
}

struct AssetSelectionCell_Previews: PreviewProvider {
    static var previews: some View {
        AssetSelectionCell(asset: sampleAsset)
    }
}
