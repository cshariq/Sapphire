//
//  BluetoothDeviceResolver.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-12
//

import Foundation
import SQLite3

class BluetoothDeviceResolver {
    static let shared = BluetoothDeviceResolver()

    private var db_paired: OpaquePointer?
    private var db_other: OpaquePointer?

    private var stmt_paired: OpaquePointer?
    private var stmt_other: OpaquePointer?

    private var didInitializeDBs = false

    private let queue = DispatchQueue(label: "com.sapphire.resolver", qos: .userInitiated)

    private init() {
        connectToDatabases()
    }

    deinit {
        if let stmt = stmt_paired { sqlite3_finalize(stmt) }
        if let stmt = stmt_other { sqlite3_finalize(stmt) }
        if let db = db_paired { sqlite3_close(db) }
        if let db = db_other { sqlite3_close(db) }
    }

    private func connectToDatabases() {
        guard !didInitializeDBs else { return }
        didInitializeDBs = true

        let pairedDBPath = "/Library/Bluetooth/com.apple.MobileBluetooth.ledevices.paired.db"
        let otherDBPath = "/Library/Bluetooth/com.apple.MobileBluetooth.ledevices.other.db"

        if sqlite3_open_v2(pairedDBPath, &db_paired, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("[Resolver] Could not open paired devices database at \(pairedDBPath)")
            db_paired = nil
        }

        if sqlite3_open_v2(otherDBPath, &db_other, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("[Resolver] Could not open other devices database at \(otherDBPath)")
            db_other = nil
        }

        let queryPaired = "SELECT Name, Address, ResolvedAddress FROM PairedDevices WHERE Uuid=? LIMIT 1"
        if let db = db_paired {
            if sqlite3_prepare_v2(db, queryPaired, -1, &stmt_paired, nil) != SQLITE_OK {
                print("[Resolver] Failed to prepare paired statement")
            }
        }

        let queryOther = "SELECT Name, Address, ResolvedAddress FROM OtherDevices WHERE Uuid=? LIMIT 1"
        if let db = db_other {
            if sqlite3_prepare_v2(db, queryOther, -1, &stmt_other, nil) != SQLITE_OK {
                print("[Resolver] Failed to prepare other statement")
            }
        }
    }

    func getLEDeviceInfo(from uuid: String) -> (name: String?, macAddr: String?)? {
        return queue.sync {
            connectToDatabases()

            if let pairedInfo = executeQuery(stmt: stmt_paired, uuid: uuid) {
                return pairedInfo
            }
            if let otherInfo = executeQuery(stmt: stmt_other, uuid: uuid) {
                return otherInfo
            }

            return nil
        }
    }

    private func executeQuery(stmt: OpaquePointer?, uuid: String) -> (name: String?, macAddr: String?)? {
        guard let stmt = stmt else { return nil }

        sqlite3_reset(stmt)

        guard sqlite3_bind_text(stmt, 1, uuid, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK else {
            return nil
        }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let name = getStringFrom(stmt: stmt, index: 0)
        let address = getStringFrom(stmt: stmt, index: 1)
        let resolvedAddress = getStringFrom(stmt: stmt, index: 2)

        let mac = parseMAC(from: resolvedAddress ?? address)

        if name == nil && mac == nil { return nil }

        return (name: name, macAddr: mac)
    }

    private func getStringFrom(stmt: OpaquePointer?, index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) == SQLITE_TEXT,
              let cString = sqlite3_column_text(stmt, index) else { return nil }
        let string = String(cString: cString).trimmingCharacters(in: .whitespacesAndNewlines)
        return string.isEmpty ? nil : string
    }

    private func parseMAC(from addressString: String?) -> String? {
        guard let addr = addressString else { return nil }
        if addr.count < 10 { return nil }

        let parts = addr.split(separator: " ")
        if let macPart = parts.last {
            return String(macPart)
        }
        return nil
    }

    func getMACFromPlist(for uuid: String) -> String? {
        guard let plist = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.Bluetooth.plist"),
              let cbcache = plist["CoreBluetoothCache"] as? NSDictionary,
              let device = cbcache[uuid] as? NSDictionary,
              let address = device["DeviceAddress"] as? String else {
            return nil
        }
        return address
    }

    func getNameFromPlist(for mac: String) -> String? {
        guard let plist = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.Bluetooth.plist"),
              let devcache = plist["DeviceCache"] as? NSDictionary,
              let device = devcache[mac] as? NSDictionary,
              let name = device["Name"] as? String else {
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}