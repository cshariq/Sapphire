//
//  main.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-23

import Foundation

NSLog("[SMJBS]: Privileged Helper has started")

XPCServer.shared.start()

CFRunLoopRun()