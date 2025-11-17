//
//  HelperProtocol.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-02
//

import Foundation

@objc(FanInfo)
public class FanInfo: NSObject, NSSecureCoding, Identifiable {
    public static var supportsSecureCoding: Bool = true
    @objc public var id: Int
    @objc var name: String
    @objc var minRPM: Int
    @objc var maxRPM: Int
    @objc var currentRPM: Int

    @objc public init(id: Int, name: String, minRPM: Int, maxRPM: Int, currentRPM: Int) {
        self.id = id; self.name = name; self.minRPM = minRPM; self.maxRPM = maxRPM; self.currentRPM = currentRPM
    }

    public func encode(with coder: NSCoder) {
        coder.encode(id, forKey: "id"); coder.encode(name, forKey: "name"); coder.encode(minRPM, forKey: "minRPM"); coder.encode(maxRPM, forKey: "maxRPM"); coder.encode(currentRPM, forKey: "currentRPM")
    }

    public required init?(coder: NSCoder) {
        id = coder.decodeInteger(forKey: "id")
        name = coder.decodeObject(of: NSString.self, forKey: "name") as String? ?? "Unknown"
        minRPM = coder.decodeInteger(forKey: "minRPM")
        maxRPM = coder.decodeInteger(forKey: "maxRPM")
        currentRPM = coder.decodeInteger(forKey: "currentRPM")
    }
}

@objc protocol HelperProtocol {
    func setChargeLimit(_ limit: Int, reply: @escaping (Error?) -> Void)
    func enableCharging(_ enabled: Bool, reply: @escaping (Error?) -> Void)
    func setDischarge(_ discharging: Bool, reply: @escaping (Error?) -> Void)
    func setMagSafeLED(color: Int, reply: @escaping (Error?) -> Void)
    func startCalibration(reply: @escaping (Error?) -> Void)
    func getFanCount(reply: @escaping (Int) -> Void)
    func getFanInfo(fanIndex: Int, reply: @escaping (FanInfo?) -> Void)
    func setFanMode(fanIndex: Int, mode: UInt8, reply: @escaping (Error?) -> Void)
    func setFanTargetSpeed(fanIndex: Int, speed: Int, reply: @escaping (Error?) -> Void)
    func setFanToConstantRPM(fanIndex: Int, speed: Int, reply: @escaping (Error?) -> Void)
    func getBatteryTemperature(reply: @escaping (Double) -> Void)
    func getAllSMCKeys(reply: @escaping ([String]) -> Void)
    func getSensorValue(key: String, reply: @escaping (Double) -> Void)
    func getVersion(reply: @escaping (String) -> Void)

    func enableLowPowerMode(reply: @escaping (Error?) -> Void)
    func disableLowPowerMode(reply: @escaping (Error?) -> Void)

    func createAggregateDevice(subDeviceUIDs: [String], masterDeviceUID: String, reply: @escaping (UInt32) -> Void)
    func destroyAggregateDevice(id: UInt32, reply: @escaping (Bool) -> Void)
    func setAggregateSubDeviceVolume(aggregateDeviceID: UInt32, subDeviceUID: String, volume: Float, reply: @escaping (Bool) -> Void)

    func setAggregateSubDeviceBalance(aggregateDeviceID: UInt32, subDeviceUID: String, balance: Float, reply: @escaping (Bool) -> Void)
    func setAggregateSubDeviceDelay(aggregateDeviceID: UInt32, subDeviceUID: String, delayInSeconds: Float, reply: @escaping (Bool) -> Void)

    func preventSystemSleep(reply: @escaping (Error?) -> Void)
    func allowSystemSleep(reply: @escaping (Error?) -> Void)

}