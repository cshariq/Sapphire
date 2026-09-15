//
//  SystemMemorySnapshot.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-13

import Darwin
import Foundation

struct SystemMemorySnapshot: Equatable, Sendable {
    let totalBytes: UInt64
    let usedBytes: UInt64

    var usedFraction: Double {
        Double(usedBytes) / Double(totalBytes)
    }

    init?(
        totalBytes: UInt64,
        pageSize: UInt64,
        activePages: UInt64,
        wiredPages: UInt64,
        compressedPages: UInt64,
        speculativePages: UInt64
    ) {
        guard totalBytes > 0, pageSize > 0 else { return nil }

        let usedPages = [activePages, wiredPages, compressedPages, speculativePages]
            .reduce(UInt64.zero) { partial, pages in
                let (sum, overflowed) = partial.addingReportingOverflow(pages)
                return overflowed ? .max : sum
            }
        let (bytes, overflowed) = usedPages.multipliedReportingOverflow(by: pageSize)

        self.totalBytes = totalBytes
        self.usedBytes = min(overflowed ? .max : bytes, totalBytes)
    }

    static func sample() -> SystemMemorySnapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        return SystemMemorySnapshot(
            totalBytes: ProcessInfo.processInfo.physicalMemory,
            pageSize: UInt64(vm_kernel_page_size),
            activePages: UInt64(stats.active_count),
            wiredPages: UInt64(stats.wire_count),
            compressedPages: UInt64(stats.compressor_page_count),
            speculativePages: UInt64(stats.speculative_count)
        )
    }
}