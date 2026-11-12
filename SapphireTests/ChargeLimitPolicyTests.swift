//
//  ChargeLimitPolicyTests.swift
//  Sapphire
//

import Foundation
import Testing
@testable import Sapphire

struct ChargeLimitPolicyTests {
    // A 100% limit means no limit, so it must never hold the battery (in .adapter mode that cuts AC power).
    @Test func fullLimitNeverHoldsWhileAwake() {
        for charge in [96, 99, 100] {
            for sailing in [true, false] {
                for isCharging in [true, false] {
                    let decision = ChargeLimitPolicy.awakeDecision(charge: charge, limit: 100, sailingEnabled: sailing, sailingLowerLimit: 10, isCharging: isCharging)
                    #expect(decision.shouldCharge)
                    #expect(decision.state == .charging)
                }
            }
        }
    }

    @Test func fullLimitOnlyStopsForSleepWhenAsked() {
        for charge in [96, 99, 100] {
            for isCharging in [true, false] {
                #expect(!ChargeLimitPolicy.shouldInhibitForSleep(charge: charge, limit: 100, isCharging: isCharging, stopChargingWhenSleeping: false))
                #expect(ChargeLimitPolicy.shouldInhibitForSleep(charge: charge, limit: 100, isCharging: isCharging, stopChargingWhenSleeping: true))
            }
        }
    }

    @Test func lowerLimitStillHoldsAndSails() {
        let atLimit = ChargeLimitPolicy.awakeDecision(charge: 80, limit: 80, sailingEnabled: false, sailingLowerLimit: 10, isCharging: true)
        #expect(!atLimit.shouldCharge)
        #expect(atLimit.state == .inhibited)
        let belowLimit = ChargeLimitPolicy.awakeDecision(charge: 79, limit: 80, sailingEnabled: false, sailingLowerLimit: 10, isCharging: false)
        #expect(belowLimit.shouldCharge)

        let sailing = ChargeLimitPolicy.awakeDecision(charge: 75, limit: 80, sailingEnabled: true, sailingLowerLimit: 10, isCharging: false)
        #expect(!sailing.shouldCharge)
        #expect(sailing.state == .sailing)
        let stillCharging = ChargeLimitPolicy.awakeDecision(charge: 75, limit: 80, sailingEnabled: true, sailingLowerLimit: 10, isCharging: true)
        #expect(stillCharging.shouldCharge)
        let belowSailing = ChargeLimitPolicy.awakeDecision(charge: 69, limit: 80, sailingEnabled: true, sailingLowerLimit: 10, isCharging: false)
        #expect(belowSailing.shouldCharge)

        #expect(ChargeLimitPolicy.shouldInhibitForSleep(charge: 80, limit: 80, isCharging: false, stopChargingWhenSleeping: false))
        #expect(ChargeLimitPolicy.shouldInhibitForSleep(charge: 50, limit: 80, isCharging: true, stopChargingWhenSleeping: false))
        #expect(!ChargeLimitPolicy.shouldInhibitForSleep(charge: 50, limit: 80, isCharging: false, stopChargingWhenSleeping: false))
    }
}
