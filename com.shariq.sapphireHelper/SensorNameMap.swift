//
//  SensorNameMap.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-24.
//

import Foundation

struct SensorNameMap {
    static func name(for key: String) -> String {
        if key.hasPrefix("TC") && (key.hasSuffix("c") || key.hasSuffix("C")) && key.count == 4 {
            let coreNumStr = String(key[key.index(key.startIndex, offsetBy: 2)])
            if let coreNum = Int(coreNumStr, radix: 16) {
                return "CPU Core \(coreNum + 1)"
            }
        }

        return knownSensors[key] ?? key
    }

    static let knownSensors: [String: String] = [
        "TA0P": "Ambient Air 1",
        "TA1P": "Ambient Air 2",
        "TA0p": "Ambient Air",
        "Th0H": "Heatpipe 1",
        "Th1H": "Heatpipe 2",
        "Th2H": "Heatpipe 3",
        "TZ0C": "Thermal Zone 1",
        "TZ1C": "Thermal Zone 2",

        "TC0D": "CPU Diode",
        "TC0E": "CPU Diode Virtual",
        "TC0F": "CPU Diode Filtered",
        "TC0H": "CPU Heatsink",
        "TC0P": "CPU Proximity",
        "TCAD": "CPU Package",
        "TCXC": "CPU Cores",
        "TCSc": "CPU SoC",

        "TCGC": "GPU Intel Graphics",
        "TG0D": "GPU Diode",
        "TGDD": "GPU AMD Radeon",
        "TG0H": "GPU Heatsink",
        "TG0P": "GPU Proximity",

        "Tm0P": "Mainboard",
        "TM0P": "Memory Slot Proximity",
        "TM0S": "Memory Slot 1",
        "TM1S": "Memory Slot 2",
        "TM2S": "Memory Slot 3",
        "TM3S": "Memory Slot 4",
        "TM4S": "Memory Slot 5",
        "TM5S": "Memory Slot 6",
        "TM6S": "Memory Slot 7",
        "TM7S": "Memory Slot 8",
        "TM8S": "Memory Slot A1",
        "TM9S": "Memory Slot A2",
        "TMA1": "RAM A1",
        "TMA2": "RAM A2",
        "TMA3": "RAM A3",
        "TMA4": "RAM A4",
        "TMB1": "RAM B1",
        "TMB2": "RAM B2",
        "TMB3": "RAM B3",
        "TMB4": "RAM B4",
        "TPCD": "Platform Controller Hub",

        "TB0T": "Battery 1",
        "TB1T": "Battery 2",
        "TB2T": "Battery 3",
        "TB3T": "Battery 4",
        "Tb0P": "Battery Proximity",
        "Tb0T": "Battery TS_MAX",

        "TW0P": "Airport Card",
        "TL0P": "Display",
        "TI0P": "Thunderbolt 1",
        "TI1P": "Thunderbolt 2",
        "TTLD": "Thunderbolt Left",
        "TTRD": "Thunderbolt Right",
        "TH0A": "Disk 1",
        "TH1A": "Disk 2",
        "TH2A": "Disk 3",
        "TH3A": "Disk 4",
        "TH0B": "Disk 5",
        "TH1B": "Disk 6",
        "TH2B": "Disk 7",
        "TH3B": "Disk 8",

        "TN0D": "Northbridge Diode",
        "TN0H": "Northbridge Heatsink",
        "TN0P": "Northbridge Proximity",

        "Tp09": "CPU Efficiency Core 1",
        "Tp0T": "CPU Efficiency Core 2",
        "Tp01": "CPU Performance Core 1",
        "Tp05": "CPU Performance Core 2",
        "Tp0D": "CPU Performance Core 3",
        "Tp0H": "CPU Performance Core 4",
        "Tp0L": "CPU Performance Core 5",
        "Tp0P": "CPU Performance Core 6",
        "Tp0X": "CPU Performance Core 7",
        "Tp0b": "CPU Performance Core 8",
        "Tg05": "GPU Cluster 1",
        "Tg0D": "GPU Cluster 2",
        "Tg0T": "GPU Cluster 4",
        "Tm02": "Memory 1",
        "Tm06": "Memory 2",
        "Tm08": "Memory 3",
        "Tm09": "Memory 4",

        "Tp1h": "CPU Efficiency Core 1",
        "Tp1t": "CPU Efficiency Core 2",
        "Tp1p": "CPU Efficiency Core 3",
        "Tp1l": "CPU Efficiency Core 4",
        "Tp0f": "CPU Performance Core 7",
        "Tp0j": "CPU Performance Core 8",
        "Tg0f": "GPU Cluster 1",

        "Te05": "CPU Efficiency Core 1",
        "Te0L": "CPU Efficiency Core 2",
        "Te0P": "CPU Efficiency Core 3",
        "Te0S": "CPU Efficiency Core 4",
        "Tf04": "CPU Performance Core 1",
        "Tf09": "CPU Performance Core 2",
        "Tf0A": "CPU Performance Core 3",
        "Tf0B": "CPU Performance Core 4",
        "Tf0D": "CPU Performance Core 5",
        "Tf0E": "CPU Performance Core 6",
        "Tf44": "CPU Performance Core 7",
        "Tf49": "CPU Performance Core 8",
        "Tf4A": "CPU Performance Core 9",
        "Tf4B": "CPU Performance Core 10",
        "Tf4D": "CPU Performance Core 11",
        "Tf4E": "CPU Performance Core 12",
        "Tf14": "GPU Cluster 1",
        "Tf18": "GPU Cluster 2",
        "Tf19": "GPU Cluster 3",
        "Tf1A": "GPU Cluster 4",
        "Tf24": "GPU Cluster 5",
        "Tf28": "GPU Cluster 6",
        "Tf29": "GPU Cluster 7",
        "Tf2A": "GPU Cluster 8",

        "Te09": "CPU Efficiency Core 3",
        "Te0H": "CPU Efficiency Core 4",
        "Tp0V": "CPU Performance Core 5",
        "Tp0Y": "CPU Performance Core 6",
        "Tp0e": "CPU Performance Core 8",
        "Tg0G": "GPU Cluster 1",
        "Tg0H": "GPU Cluster 2",
        "Tg1U": "GPU Cluster 1 (Pro/Max)",
        "Tg1k": "GPU Cluster 2 (Pro/Max)",
        "Tg0K": "GPU Cluster 3",
        "Tg0L": "GPU Cluster 4",
        "Tg0d": "GPU Cluster 5",
        "Tg0e": "GPU Cluster 6",
        "Tg0j": "GPU Cluster 7",
        "Tg0k": "GPU Cluster 8",
        "Tm0p": "Memory Proximity 1",
        "Tm1p": "Memory Proximity 2",
        "Tm2p": "Memory Proximity 3",

        "TaLP": "Airflow Left",
        "TaRF": "Airflow Right",
        "TH0x": "NAND",
        "TCHP": "Charger Proximity",
        "TCMb": "Core Media Engine",
        "TCMz": "Core Media Engine Block",
    ]
}