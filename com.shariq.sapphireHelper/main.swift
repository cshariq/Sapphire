//
//  main.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-23

import Foundation

NSLog("[SMJBS]: Privileged Helper has started")

XPCServer.shared.start()

signal(SIGTERM, SIG_IGN)
let terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminationSource.setEventHandler {
    NSLog("[SMJBS]: SIGTERM received; restoring automatic fan control before exit.")
    XPCServer.shared.prepareForExit()
    exit(0)
}
terminationSource.resume()

CFRunLoopRun()