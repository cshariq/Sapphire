//
//  SharingManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-02.
//

import AppKit

class SharingManager: NSObject, NSSharingServiceDelegate {

    static let shared = SharingManager()

    private var activeServices = [NSSharingService]()

    func share(items: [Any], via serviceName: NSSharingService.Name) {
        guard let service = NSSharingService(named: serviceName) else {
            print("Error: Sharing service '\(serviceName.rawValue)' is not available.")
            return
        }

        service.delegate = self

        activeServices.append(service)

        service.perform(withItems: items)
    }

    // MARK: - NSSharingServiceDelegate

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        print("Successfully shared items.")
        removeService(sharingService)
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        print("Failed to share items: \(error.localizedDescription)")
        removeService(sharingService)
    }

    private func removeService(_ service: NSSharingService) {
        if let index = activeServices.firstIndex(of: service) {
            activeServices.remove(at: index)
        }
    }
}