//
//  DirectoryMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-17.
//

import Foundation
import Combine

class DirectoryMonitor {
    let url: URL
    let fileDidChangePublisher = PassthroughSubject<Void, Never>()

    private var fileDescriptor: CInt = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private let dispatchQueue = DispatchQueue(label: "com.sapphire.directorymonitor.queue", qos: .userInitiated)

    init(url: URL) {
        self.url = url
    }

    func start() {
        guard dispatchSource == nil, fileDescriptor == -1 else { return }

        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor != -1 else { return }

        let descriptor = fileDescriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: dispatchQueue
        )
        dispatchSource = source

        source.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.fileDidChangePublisher.send()
            }
        }

        source.setCancelHandler {
            close(descriptor)
        }

        source.resume()
    }

    func stop() {
        guard let source = dispatchSource else { return }
        dispatchSource = nil
        fileDescriptor = -1
        source.cancel()
    }

    deinit {
        stop()
    }
}