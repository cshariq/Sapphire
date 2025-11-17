//
//  values.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-23
//

import Foundation

public enum SensorType: String, Codable, CaseIterable {
    case temperature = "Temperature"
    case voltage = "Voltage"
    case current = "Current"
    case power = "Power"
    case fan = "Fans"
    case energy = "Energy"
    case unknown = "Unknown"
}
public enum SensorGroup: String, Codable, CaseIterable {
    case CPU = "CPU", GPU = "GPU", system = "Systems", sensor = "Sensors", hid = "HID", unknown = "Unknown"
}

public struct SensorDefinition {
    public let key: String
    public let name: String
    public let type: SensorType
    public let group: SensorGroup
}

internal let SENSORS_LIST: [SensorDefinition] = [
    SensorDefinition(key: "TA%P", name: "Ambient %", type: .temperature, group: .sensor),
    SensorDefinition(key: "Th%H", name: "Heatpipe %", type: .temperature, group: .sensor),
    SensorDefinition(key: "TZ%C", name: "Thermal zone %", type: .temperature, group: .sensor),

    SensorDefinition(key: "TC0D", name: "CPU diode", type: .temperature, group: .CPU),
    SensorDefinition(key: "TC0E", name: "CPU diode virtual", type: .temperature, group: .CPU),
    SensorDefinition(key: "TC0F", name: "CPU diode filtered", type: .temperature, group: .CPU),
    SensorDefinition(key: "TC0H", name: "CPU heatsink", type: .temperature, group: .CPU),
    SensorDefinition(key: "TC0P", name: "CPU proximity", type: .temperature, group: .CPU),
    SensorDefinition(key: "TCAD", name: "CPU package", type: .temperature, group: .CPU),

    SensorDefinition(key: "TC%c", name: "CPU core %", type: .temperature, group: .CPU),
    SensorDefinition(key: "TC%C", name: "CPU Core %", type: .temperature, group: .CPU),

    SensorDefinition(key: "TCGC", name: "GPU Intel Graphics", type: .temperature, group: .GPU),
    SensorDefinition(key: "TG0D", name: "GPU diode", type: .temperature, group: .GPU),
    SensorDefinition(key: "TGDD", name: "GPU AMD Radeon", type: .temperature, group: .GPU),
    SensorDefinition(key: "TG0H", name: "GPU heatsink", type: .temperature, group: .GPU),
    SensorDefinition(key: "TG0P", name: "GPU proximity", type: .temperature, group: .GPU),

    SensorDefinition(key: "Tm0P", name: "Mainboard", type: .temperature, group: .system),
    SensorDefinition(key: "Tp0P", name: "Powerboard", type: .temperature, group: .system),
    SensorDefinition(key: "TB1T", name: "Battery", type: .temperature, group: .system),
    SensorDefinition(key: "TW0P", name: "Airport", type: .temperature, group: .system),
    SensorDefinition(key: "TL0P", name: "Display", type: .temperature, group: .system),
    SensorDefinition(key: "TI%P", name: "Thunderbolt %", type: .temperature, group: .system),
    SensorDefinition(key: "TH%A", name: "Disk % (A)", type: .temperature, group: .system),
    SensorDefinition(key: "TH%B", name: "Disk % (B)", type: .temperature, group: .system),
    SensorDefinition(key: "TH%C", name: "Disk % (C)", type: .temperature, group: .system),

    SensorDefinition(key: "TTLD", name: "Thunderbolt left", type: .temperature, group: .system),
    SensorDefinition(key: "TTRD", name: "Thunderbolt right", type: .temperature, group: .system),

    SensorDefinition(key: "TN0D", name: "Northbridge diode", type: .temperature, group: .system),
    SensorDefinition(key: "TN0H", name: "Northbridge heatsink", type: .temperature, group: .system),
    SensorDefinition(key: "TN0P", name: "Northbridge proximity", type: .temperature, group: .system),

    SensorDefinition(key: "Tp09", name: "CPU efficiency core 1", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tp0T", name: "CPU efficiency core 2", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tp01", name: "CPU performance core 1", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tp05", name: "CPU performance core 2", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tp0D", name: "CPU performance core 3", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tp0H", name: "CPU performance core 4", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tp0L", name: "CPU performance core 5", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tp0P", name: "CPU performance core 6", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tp0X", name: "CPU performance core 7", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tp0b", name: "CPU performance core 8", type: .temperature, group: .CPU),

    SensorDefinition(key: "Tg05", name: "GPU 1", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tg0D", name: "GPU 2", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tg0L", name: "GPU 3", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tg0T", name: "GPU 4", type: .temperature, group: .GPU),

    SensorDefinition(key: "Tm02", name: "Memory 1", type: .temperature, group: .sensor),
    SensorDefinition(key: "Tm06", name: "Memory 2", type: .temperature, group: .sensor),
    SensorDefinition(key: "Tm08", name: "Memory 3", type: .temperature, group: .sensor),
    SensorDefinition(key: "Tm09", name: "Memory 4", type: .temperature, group: .sensor),

    SensorDefinition(key: "Tp1h", name: "CPU efficiency core 1", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tp1t", name: "CPU efficiency core 2", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tp1p", name: "CPU efficiency core 3", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tp1l", name: "CPU efficiency core 4", type: .temperature, group: .CPU),

    SensorDefinition(key: "Tp0f", name: "CPU performance core 7", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tp0j", name: "CPU performance core 8", type: .temperature, group: .CPU),

    SensorDefinition(key: "Tg0f", name: "GPU 1", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tg0j", name: "GPU 2", type: .temperature, group: .GPU),

    SensorDefinition(key: "Te05", name: "CPU efficiency core 1", type: .temperature, group: .CPU),
    SensorDefinition(key: "Te0L", name: "CPU efficiency core 2", type: .temperature, group: .CPU),
    SensorDefinition(key: "Te0P", name: "CPU efficiency core 3", type: .temperature, group: .CPU),
    SensorDefinition(key: "Te0S", name: "CPU efficiency core 4", type: .temperature, group: .CPU),

    SensorDefinition(key: "Tf04", name: "CPU performance core 1", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tf09", name: "CPU performance core 2", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tf0A", name: "CPU performance core 3", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tf0B", name: "CPU performance core 4", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tf0D", name: "CPU performance core 5", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tf0E", name: "CPU performance core 6", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tf44", name: "CPU performance core 7", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tf49", name: "CPU performance core 8", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tf4A", name: "CPU performance core 9", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tf4B", name: "CPU performance core 10", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tf4D", name: "CPU performance core 11", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tf4E", name: "CPU performance core 12", type: .temperature, group: .CPU),

    SensorDefinition(key: "Tf14", name: "GPU 1", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tf18", name: "GPU 2", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tf19", name: "GPU 3", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tf1A", name: "GPU 4", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tf24", name: "GPU 5", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tf28", name: "GPU 6", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tf29", name: "GPU 7", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tf2A", name: "GPU 8", type: .temperature, group: .GPU),

    SensorDefinition(key: "Te09", name: "CPU efficiency core 3", type: .temperature, group: .CPU),
    SensorDefinition(key: "Te0H", name: "CPU efficiency core 4", type: .temperature, group: .CPU),

    SensorDefinition(key: "Tp0V", name: "CPU performance core 5", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tp0Y", name: "CPU performance core 6", type: .temperature, group: .CPU),
    SensorDefinition(key: "Tp0e", name: "CPU performance core 8", type: .temperature, group: .CPU),

    SensorDefinition(key: "Tg0G", name: "GPU 1", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tg0H", name: "GPU 2", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tg1U", name: "GPU 1", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tg1k", name: "GPU 2", type: .temperature, group: .GPU),

    SensorDefinition(key: "Tg0K", name: "GPU 3", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tg0L", name: "GPU 4", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tg0d", name: "GPU 5", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tg0e", name: "GPU 6", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tg0j", name: "GPU 7", type: .temperature, group: .GPU),
    SensorDefinition(key: "Tg0k", name: "GPU 8", type: .temperature, group: .GPU),

    SensorDefinition(key: "Tm0p", name: "Memory Proximity 1", type: .temperature, group: .sensor),
    SensorDefinition(key: "Tm1p", name: "Memory Proximity 2", type: .temperature, group: .sensor),
    SensorDefinition(key: "Tm2p", name: "Memory Proximity 3", type: .temperature, group: .sensor),

    SensorDefinition(key: "TaLP", name: "Airflow left", type: .temperature, group: .sensor),
    SensorDefinition(key: "TaRF", name: "Airflow right", type: .temperature, group: .sensor),

    SensorDefinition(key: "TH0x", name: "NAND", type: .temperature, group: .system),
    SensorDefinition(key: "TB1T", name: "Battery 1", type: .temperature, group: .system),
    SensorDefinition(key: "TB2T", name: "Battery 2", type: .temperature, group: .system),
    SensorDefinition(key: "TW0P", name: "Airport", type: .temperature, group: .system),

    SensorDefinition(key: "VCAC", name: "CPU IA", type: .voltage, group: .CPU),
    SensorDefinition(key: "VCSC", name: "CPU System Agent", type: .voltage, group: .CPU),
    SensorDefinition(key: "VC%C", name: "CPU Core %", type: .voltage, group: .CPU),

    SensorDefinition(key: "VCTC", name: "GPU Intel Graphics", type: .voltage, group: .GPU),
    SensorDefinition(key: "VG0C", name: "GPU", type: .voltage, group: .GPU),

    SensorDefinition(key: "VM0R", name: "Memory", type: .voltage, group: .system),
    SensorDefinition(key: "Vb0R", name: "CMOS", type: .voltage, group: .system),

    SensorDefinition(key: "VD0R", name: "DC In", type: .voltage, group: .sensor),
    SensorDefinition(key: "VP0R", name: "12V rail", type: .voltage, group: .sensor),
    SensorDefinition(key: "Vp0C", name: "12V vcc", type: .voltage, group: .sensor),
    SensorDefinition(key: "VV2S", name: "3V", type: .voltage, group: .sensor),
    SensorDefinition(key: "VR3R", name: "3.3V", type: .voltage, group: .sensor),
    SensorDefinition(key: "VV1S", name: "5V", type: .voltage, group: .sensor),
    SensorDefinition(key: "VV9S", name: "12V", type: .voltage, group: .sensor),
    SensorDefinition(key: "VeES", name: "PCI 12V", type: .voltage, group: .sensor),

    SensorDefinition(key: "IC0R", name: "CPU High side", type: .current, group: .sensor),
    SensorDefinition(key: "IG0R", name: "GPU High side", type: .current, group: .sensor),
    SensorDefinition(key: "ID0R", name: "DC In", type: .current, group: .sensor),
    SensorDefinition(key: "IBAC", name: "Battery", type: .current, group: .sensor),

    SensorDefinition(key: "PC0C", name: "CPU Core", type: .power, group: .CPU),
    SensorDefinition(key: "PCPC", name: "CPU Package", type: .power, group: .CPU),
    SensorDefinition(key: "PCTR", name: "CPU Total", type: .power, group: .CPU),
    SensorDefinition(key: "PCPT", name: "CPU Package total", type: .power, group: .CPU),
    SensorDefinition(key: "PCPR", name: "CPU Package total (SMC)", type: .power, group: .CPU),
    SensorDefinition(key: "PC0R", name: "CPU Computing high side", type: .power, group: .CPU),

    SensorDefinition(key: "PCPG", name: "GPU Intel Graphics", type: .power, group: .GPU),
    SensorDefinition(key: "PG0C", name: "GPU", type: .power, group: .GPU),
    SensorDefinition(key: "PCGC", name: "Intel GPU", type: .power, group: .GPU),

    SensorDefinition(key: "PC3C", name: "RAM", type: .power, group: .sensor),
    SensorDefinition(key: "PPBR", name: "Battery", type: .power, group: .sensor),
    SensorDefinition(key: "PDTR", name: "DC In", type: .power, group: .sensor),
    SensorDefinition(key: "PSTR", name: "System Total", type: .power, group: .sensor)
]