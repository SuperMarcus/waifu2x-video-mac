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

import Cocoa
import Combine
import SwiftUI

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate {
    static var shared: AppDelegate!

    var window: NSWindow!
    var contentView: ContentView!
    var toolbarStartStopButton: NSButton?
    var processingButtonSink: AnyCancellable?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        AppDelegate.shared = self
        
        // Create the SwiftUI view that provides the window contents.
        contentView = ContentView()

        // Create the window and set the content view. 
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.contentView = NSHostingView(rootView: contentView)
        
        let toolbar = NSToolbar()
        toolbar.delegate = self
        toolbar.sizeMode = .regular
        
//        toolbar.showsBaselineSeparator = false
        window.styleMask.insert(.fullSizeContentView)
//        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = toolbar
        
        window.makeKeyAndOrderFront(nil)
        
        self.processingButtonSink = contentView.observing.$isProcessing.sink {
            self.updateStartStopButton($0)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            .addButton,
            .startStopButton
        ]
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .space,
            .flexibleSpace,
            .startStopButton,
            .addButton
        ]
    }
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let toolbarItem = NSToolbarItem(
            itemIdentifier: itemIdentifier
        )
        
        if itemIdentifier == .startStopButton {
            toolbarStartStopButton = NSButton(
                title: "",
                target: self,
                action: #selector(toggleProcessingEnabled(_:))
            )
            self.updateStartStopButton()
            
            toolbarItem.view = toolbarStartStopButton
        }
        
        if itemIdentifier == .addButton {
            let addButton = NSButton(
                title: "",
                target: self,
                action: #selector(onAddButtonDidTap(_:))
            )
            addButton.image = NSImage(named: NSImage.addTemplateName)
            toolbarItem.view = addButton
        }
        
        return toolbarItem
    }
    
    @objc private func onAddButtonDidTap(_ sender: Any) {
        DispatchQueue.main.async {
            self.contentView.observing.presentActionSheet = true
        }
    }
    
    @objc private func toggleProcessingEnabled(_ sender: Any) {
        DispatchQueue.main.async {
            self.contentView.observing.isProcessing.toggle()
            self.updateStartStopButton()
        }
    }
    
    private func updateStartStopButton(_ value: Bool? = nil) {
        let runIcon = NSImage(named: "Run Toolbar Icon")
        let stopIcon = NSImage(named: "Stop Toolbar Icon")
        
        self.toolbarStartStopButton?.image =
            (value ?? self.contentView.observing.isProcessing) ? stopIcon : runIcon
    }
}

extension NSToolbarItem.Identifier {
    static let startStopButton = NSToolbarItem.Identifier("com.marcuszhou.startStopButton")
    
    static let addButton = NSToolbarItem.Identifier("com.marcuszhou.addButton")
}
