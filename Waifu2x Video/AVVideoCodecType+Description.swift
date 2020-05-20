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

extension AVVideoCodecType {
    var description: String {
        switch self {
        case .h264: return "H.264 - Advanced Video Coding"
        case .hevc: return "H.265 - High Efficiency Video Coding"
        default: return "AVCodec"
        }
    }
}
