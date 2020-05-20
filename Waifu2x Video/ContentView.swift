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
import Combine

struct ContentView: View {
    @ObservedObject var observing = ContentViewObserving()
    
    var body: some View {
        NavigationView {
            AssetSelectionList()
                .environmentObject(self.observing)
            
            if observing.currentlyPresentingTask != nil {
                AssetConversionConfigurationView(
                    asset: observing.currentlyPresentingTask!
                ).environmentObject(observing)
            }
        }
        .sheet(isPresented: $observing.presentActionSheet, onDismiss: {
            print("[ContentView] Sheet has been dismissed")
        }) {
            AddAssetSheet(observing: self.observing)
        }
        .frame(minWidth: 700, minHeight: 400)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

class ContentViewObserving: ObservableObject {
    @Published var presentActionSheet: Bool = false
    @Published var tasks = [ sampleAsset ]
    @Published var currentlyPresentingTask: ConvertingAsset? = sampleAsset
    @Published var isProcessing: Bool = false
    
    private var _sinkListener: AnyCancellable?
    private var _taskIteratingTimer: Timer?
    
    func processNextIdleTask() {
        if !tasks.contains(where: { $0.currentState == .processing }) {
            let nextIdleTask = tasks.first {
                $0.currentState == .queued
            }
            
            if let nextIdleTask = nextIdleTask {
                nextIdleTask.beginConversion()
            } else {
                self.isProcessing = false
            }
        }
    }
    
    func stopAllRunningTasks() {
        tasks.forEach {
            if $0.currentState == .processing {
                $0.cancel()
            }
        }
    }
    
    init() {
        _taskIteratingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] _ in
            guard let self = self else {
                return
            }
            
            if self.isProcessing {
                DispatchQueue.main.async {
                    self.processNextIdleTask()
                }
            }
        }
        _sinkListener = self.$isProcessing.sink {
            if !$0 {
                self.stopAllRunningTasks()
            }
        }
    }
}
