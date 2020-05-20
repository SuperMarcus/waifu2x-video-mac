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

import AVFoundation

extension AVFileType {
    /// Fetch and extension for a file from UTI string
    ///
    /// https://stackoverflow.com/a/49982657
    var fileExtension: String {
        if let ext = UTTypeCopyPreferredTagWithClass(self as CFString, kUTTagClassFilenameExtension)?.takeRetainedValue() {
            return ext as String
        }
        return rawValue
    }
    
    var description: String {
        switch self {
        case .mp4: return "MPEG-4 Video (mp4)"
        case .m4v: return "iTunes Video (m4v)"
        case .mov: return "QuickTime Movie (mov)"
        default: return "Video Format (\(fileExtension))"
        }
    }
}
