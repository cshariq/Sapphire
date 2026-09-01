//
//  DesktopManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-04
//

import AppKit
import Combine

class DesktopManager: ObservableObject {

    @Published private(set) var currentDesktopNumber: Int?
    @Published private(set) var perDisplayDesktopNumbers: [String: Int] = [:]

    init() {
        self.currentDesktopNumber = CGSHelper.getActiveDesktopNumber()
        self.perDisplayDesktopNumbers = CGSHelper.getActiveDesktopNumbersByDisplay()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    @objc private func activeSpaceDidChange() {
        DispatchQueue.main.async {
            self.currentDesktopNumber = CGSHelper.getActiveDesktopNumber()
            self.perDisplayDesktopNumbers = CGSHelper.getActiveDesktopNumbersByDisplay()
        }
    }

    func desktopNumber(for screen: NSScreen?) -> Int? {
        guard let screen,
              let cgsID = screen.cgsDisplayIdentifier,
              let number = perDisplayDesktopNumbers[cgsID] else {
            return currentDesktopNumber
        }
        return number
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}