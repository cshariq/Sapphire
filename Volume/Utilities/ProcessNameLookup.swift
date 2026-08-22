//
//  ProcessNameLookup.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-21

import Darwin
import Foundation

enum ProcessNameLookup {
    static func name(for pid: pid_t) -> String? {
        guard pid > 0 else { return nil }

        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]

        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else {
            return nil
        }

        guard size > 0 else { return nil }

        let name = withUnsafePointer(to: &info.kp_proc.p_comm) { tuplePtr -> String in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: tuplePtr.pointee)) { cStr in
                String(cString: cStr)
            }
        }

        return name.isEmpty ? nil : name
    }
}