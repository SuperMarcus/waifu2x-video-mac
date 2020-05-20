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

struct AssetSelectionList: View {
    @EnvironmentObject var observing: ContentViewObserving
    
    var body: some View {
        return List(selection: self.$observing.currentlyPresentingTask) {
            ForEach(observing.tasks, id: \.inputUrl) {
                video in
                AssetSelectionCell(asset: video)
                    .contextMenu {
                        Button(action: {
                            self.remove(task: video)
                        }) {
                            Text("Remove Task")
                        }
                        Button(action: {
                            self.removeAll()
                        }) {
                            Text("Clear All")
                        }
                    }
                    .animation(nil)
                    .tag(video)
            }
        }
        .animation(.easeInOut)
        .frame(minWidth: 200.0, maxWidth: 400)
        .listStyle(SidebarListStyle())
        .contextMenu {
            Button(action: {
                self.removeAll()
            }) { Text("Remove All") }
        }
    }
    
    func remove(task: ConvertingAsset) {
        self.observing.tasks.removeAll {
            $0 == task
        }
        task.cancel()
        
        if self.observing.tasks.isEmpty {
            self.observing.tasks = [ sampleAsset ]
            self.observing.currentlyPresentingTask = sampleAsset
        } else {
            self.observing.currentlyPresentingTask = self.observing.tasks.first
        }
    }
    
    func removeAll() {
        self.observing.tasks.forEach {
            $0.cancel()
        }
        self.observing.tasks = [ sampleAsset ]
        self.observing.currentlyPresentingTask = sampleAsset
    }
}

struct AssetSelectionList_Previews: PreviewProvider {
    static var previews: some View {
        AssetSelectionList()
            .environmentObject(ContentViewObserving())
    }
}
