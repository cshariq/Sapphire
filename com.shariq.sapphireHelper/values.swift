//
//  values.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-23
//

import Foundation

public enum SensorType: String {
    case temperature = "Temperature"
    case voltage = "Voltage"
    case current = "Current"
    case power = "Power"
    case fan = "Fans"
}

public struct SensorDefinition {
    public let key: String
    public let name: String
    public let type: SensorType
}

internal let SENSORS_LIST: [SensorDefinition] = [
    // MARK: - Temperatures
    SensorDefinition(key: "TA0P", name: "Ambient Air 1", type: .temperature),
    SensorDefinition(key: "TA1P", name: "Ambient Air 2", type: .temperature),
    SensorDefinition(key: "Th0H", name: "Heatpipe 1", type: .temperature),
    SensorDefinition(key: "Th1H", name: "Heatpipe 2", type: .temperature),
    SensorDefinition(key: "TZ0C", name: "Thermal Zone 1", type: .temperature),
    SensorDefinition(key: "TZ1C", name: "Thermal Zone 2", type: .temperature),

    SensorDefinition(key: "TC0D", name: "CPU Core 1 (Diode)", type: .temperature),
    SensorDefinition(key: "TC1D", name: "CPU Core 2 (Diode)", type: .temperature),
    SensorDefinition(key: "TC2D", name: "CPU Core 3 (Diode)", type: .temperature),
    SensorDefinition(key: "TC3D", name: "CPU Core 4 (Diode)", type: .temperature),
    SensorDefinition(key: "TC4D", name: "CPU Core 5 (Diode)", type: .temperature),
    SensorDefinition(key: "TC5D", name: "CPU Core 6 (Diode)", type: .temperature),
    SensorDefinition(key: "TC6D", name: "CPU Core 7 (Diode)", type: .temperature),
    SensorDefinition(key: "TC7D", name: "CPU Core 8 (Diode)", type: .temperature),
    SensorDefinition(key: "TC0E", name: "CPU Core 1 (PECI)", type: .temperature),
    SensorDefinition(key: "TC1E", name: "CPU Core 2 (PECI)", type: .temperature),
    SensorDefinition(key: "TC2E", name: "CPU Core 3 (PECI)", type: .temperature),
    SensorDefinition(key: "TC3E", name: "CPU Core 4 (PECI)", type: .temperature),
    SensorDefinition(key: "TC0F", name: "CPU Core 1 (PECI)", type: .temperature),
    SensorDefinition(key: "TC1F", name: "CPU Core 2 (PECI)", type: .temperature),
    SensorDefinition(key: "TC2F", name: "CPU Core 3 (PECI)", type: .temperature),
    SensorDefinition(key: "TC3F", name: "CPU Core 4 (PECI)", type: .temperature),
    SensorDefinition(key: "TC0H", name: "CPU Heatsink", type: .temperature),
    SensorDefinition(key: "TC0P", name: "CPU Proximity", type: .temperature),
    SensorDefinition(key: "TCAD", name: "CPU Package", type: .temperature),

    SensorDefinition(key: "TCGC", name: "GPU Intel Graphics", type: .temperature),
    SensorDefinition(key: "TG0D", name: "GPU Diode", type: .temperature),
    SensorDefinition(key: "TGDD", name: "GPU AMD Radeon", type: .temperature),
    SensorDefinition(key: "TG0H", name: "GPU Heatsink", type: .temperature),
    SensorDefinition(key: "TG0P", name: "GPU Proximity", type: .temperature),

    SensorDefinition(key: "Tm0P", name: "Mainboard", type: .temperature),
    SensorDefinition(key: "Tp0P", name: "Powerboard", type: .temperature),
    SensorDefinition(key: "TB0T", name: "Battery 1", type: .temperature),
    SensorDefinition(key: "TB1T", name: "Battery 2", type: .temperature),
    SensorDefinition(key: "TB2T", name: "Battery 3", type: .temperature),
    SensorDefinition(key: "TW0P", name: "Airport Proximity", type: .temperature),
    SensorDefinition(key: "TL0P", name: "Display", type: .temperature),
    SensorDefinition(key: "TN0D", name: "Northbridge Diode", type: .temperature),
    SensorDefinition(key: "TN0H", name: "Northbridge Heatsink", type: .temperature),
    SensorDefinition(key: "TN0P", name: "Northbridge Proximity", type: .temperature),

    // MARK: - Apple Silicon Temperatures
    SensorDefinition(key: "Tp0C", name: "CPU Core Average", type: .temperature),

    SensorDefinition(key: "Te05", name: "CPU E-Core 1", type: .temperature),
    SensorDefinition(key: "Te0L", name: "CPU E-Core 2", type: .temperature),
    SensorDefinition(key: "Te0P", name: "CPU E-Core 3", type: .temperature),
    SensorDefinition(key: "Te0S", name: "CPU E-Core 4", type: .temperature),
    SensorDefinition(key: "Te09", name: "CPU E-Core (M1/M4)", type: .temperature),
    SensorDefinition(key: "Te0H", name: "CPU E-Core (M4)", type: .temperature),
    SensorDefinition(key: "Tp1h", name: "CPU E-Core 1 (M2)", type: .temperature),
    SensorDefinition(key: "Tp1t", name: "CPU E-Core 2 (M2)", type: .temperature),
    SensorDefinition(key: "Tp1p", name: "CPU E-Core 3 (M2)", type: .temperature),
    SensorDefinition(key: "Tp1l", name: "CPU E-Core 4 (M2)", type: .temperature),

    SensorDefinition(key: "Tp01", name: "CPU P-Core 1", type: .temperature),
    SensorDefinition(key: "Tp05", name: "CPU P-Core 2", type: .temperature),
    SensorDefinition(key: "Tp09", name: "CPU P-Core 3", type: .temperature),
    SensorDefinition(key: "Tp0D", name: "CPU P-Core 4", type: .temperature),
    SensorDefinition(key: "Tp0X", name: "CPU P-Core 5", type: .temperature),
    SensorDefinition(key: "Tp0b", name: "CPU P-Core 6", type: .temperature),
    SensorDefinition(key: "Tf04", name: "CPU P-Core (M3)", type: .temperature),
    SensorDefinition(key: "Tf09", name: "CPU P-Core (M3)", type: .temperature),

    SensorDefinition(key: "Tg0G", name: "GPU Core 1", type: .temperature),
    SensorDefinition(key: "Tg0H", name: "GPU Core 2", type: .temperature),
    SensorDefinition(key: "Tg0K", name: "GPU Core 3", type: .temperature),
    SensorDefinition(key: "Tg0L", name: "GPU Core 4", type: .temperature),
    SensorDefinition(key: "Tg0d", name: "GPU Core 5", type: .temperature),
    SensorDefinition(key: "Tg0e", name: "GPU Core 6", type: .temperature),
    SensorDefinition(key: "Tg0j", name: "GPU Core 7", type: .temperature),
    SensorDefinition(key: "Tg0k", name: "GPU Core 8", type: .temperature),

    SensorDefinition(key: "TH0x", name: "NAND Flash", type: .temperature),

    // MARK: - Voltages
    SensorDefinition(key: "VCAC", name: "CPU IA Voltage", type: .voltage),
    SensorDefinition(key: "VCSC", name: "CPU System Agent Voltage", type: .voltage),
    SensorDefinition(key: "VC0C", name: "CPU Core 1 Voltage", type: .voltage),
    SensorDefinition(key: "VC1C", name: "CPU Core 2 Voltage", type: .voltage),
    SensorDefinition(key: "VCTC", name: "GPU Intel Graphics Voltage", type: .voltage),
    SensorDefinition(key: "VG0C", name: "GPU Voltage", type: .voltage),
    SensorDefinition(key: "VM0R", name: "Memory Voltage", type: .voltage),
    SensorDefinition(key: "VD0R", name: "DC In Voltage", type: .voltage),

    // MARK: - Currents
    SensorDefinition(key: "IC0R", name: "CPU High Side Current", type: .current),
    SensorDefinition(key: "IG0R", name: "GPU High Side Current", type: .current),
    SensorDefinition(key: "ID0R", name: "DC In Current", type: .current),
    SensorDefinition(key: "IBAC", name: "Battery Current", type: .current),

    // MARK: - Powers
    SensorDefinition(key: "PCPC", name: "CPU Package Power", type: .power),
    SensorDefinition(key: "PCTR", name: "CPU Total Power", type: .power),
    SensorDefinition(key: "PCPT", name: "CPU Package Total (IMON)", type: .power),
    SensorDefinition(key: "PCPR", name: "CPU Package Total (SMC)", type: .power),
    SensorDefinition(key: "PC0R", name: "CPU Computing High Side Power", type: .power),
    SensorDefinition(key: "PCGC", name: "Intel GPU Power", type: .power),
    SensorDefinition(key: "PG0R", name: "GPU Power", type: .power),
    SensorDefinition(key: "PSTR", name: "System Total Power", type: .power),
    SensorDefinition(key: "PPBR", name: "Battery Power", type: .power),
    SensorDefinition(key: "PDTR", name: "DC In Power", type: .power),

    // MARK: - Fans (for completeness)
    SensorDefinition(key: "FNum", name: "Fan Count", type: .fan)
]