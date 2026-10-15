//
//  OtherDisplay.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-14.
//

import Foundation
import Cocoa
import os.log

final class OtherDisplay: Display {
  private(set) var method: DisplayBrightnessMethod = .probing
  var ddcDirectory: DDCServiceDirectory?

  private var channel: DDCChannel?
  private var hasLocalChange = false

  var prefersSoftware: Bool {
    self.isVirtual || self.isDummy || self.readPrefAsBool(key: .forceSw)
  }

  override var brightnessMethod: DisplayBrightnessMethod {
    self.prefersSoftware ? .software : self.method
  }

  var lastKnownSoftwareOnly: Bool {
    self.prefersSoftware || self.readPrefAsBool(key: .unavailableDDC, for: .brightness)
  }

  // MARK: - Brightness

  override func getBrightness() -> Float {
    let key = self.getPrefKey(for: .brightness) + PrefKey.value.rawValue
    guard let stored = UserDefaults.standard.object(forKey: key) as? NSNumber else { return 1 }
    return stored.floatValue.clamped(to: 0...1)
  }

  @discardableResult
  override func setBrightness(_ level: Float) -> Bool {
    let level = level.clamped(to: 0...1)
    self.hasLocalChange = true
    self.savePref(level, key: .value, for: .brightness)
    self.brightness = level
    return self.applyBrightness(level)
  }

  @discardableResult
  override func setDirectBrightness(_ level: Float) -> Bool {
    self.applyBrightness(level.clamped(to: 0...1))
  }

  func reapplyBrightness() {
    self.applyBrightness(self.getBrightness())
  }

  func prepareBrightnessControl() {
    guard !self.prefersSoftware, self.method == .probing else { return }
    self.ensureChannel().probe()
  }

  func setPrefersSoftware(_ prefersSoftware: Bool) {
    self.savePref(prefersSoftware, key: .forceSw)
    if !prefersSoftware {
      self.redetect()
    } else {
      self.reapplyBrightness()
      DisplayManager.shared.notifyBrightnessStateChanged()
    }
  }

  func redetect() {
    self.channel?.cancel()
    self.channel = nil
    self.method = .probing
    self.prepareBrightnessControl()
    DisplayManager.shared.notifyBrightnessStateChanged()
  }

  func restoreSoftwareDimming() {
    guard self.lastKnownSoftwareOnly else { return }
    if !self.prefersSoftware { self.method = .software }
    self.reapplyBrightness()
  }

  func invalidate() {
    self.channel?.cancel()
    self.channel = nil
  }

  @discardableResult
  private func applyBrightness(_ level: Float) -> Bool {
    let usesHardware = !self.prefersSoftware && self.method != .software
    let split = DisplayBrightnessMath.split(
      level: level,
      hardwareAvailable: usesHardware,
      extraDimming: DisplayManager.shared.isExtraDimmingEnabled
    )
    if let hardware = split.hardware {
      self.ensureChannel().writeBrightness(self.ddcValue(for: hardware))
    }
    return DisplayGammaController.shared.setFactor(split.gamma, for: self.identifier, source: .dimming)
  }

  // MARK: - DDC

  private var ddcMaximum: Int {
    self.prefExists(key: .maxDDC, for: .brightness) ? self.readPrefAsInt(key: .maxDDC, for: .brightness) : 100
  }

  private func ddcValue(for level: Float) -> UInt16 {
    DisplayBrightnessMath.ddcValue(
      level: level,
      minimum: self.readPrefAsInt(key: .minDDCOverride, for: .brightness),
      maximum: self.ddcMaximum
    )
  }

  private func ensureChannel() -> DDCChannel {
    if let channel = self.channel { return channel }
    let channel = DDCChannel(
      displayID: self.identifier,
      directory: self.ddcDirectory ?? DDCServiceDirectory(displayIDs: [self.identifier]),
      onProbe: { [weak self] outcome in
        MainActor.assumeIsolated { self?.handleProbe(outcome) }
      },
      onFailure: { [weak self] in
        MainActor.assumeIsolated { self?.handleDDCFailure() }
      }
    )
    self.channel = channel
    return channel
  }

  private func handleProbe(_ outcome: DDCChannel.ProbeOutcome) {
    switch outcome {
    case .unavailable:
      os_log("Display %{public}@ has no DDC, using software dimming", type: .info, String(self.identifier))
      self.method = .software
      self.savePref(true, key: .unavailableDDC, for: .brightness)
      self.reapplyBrightness()
    case .available(let current, let maximum):
      self.method = .ddc
      self.savePref(false, key: .unavailableDDC, for: .brightness)
      if let maximum, maximum > 0 {
        self.savePref(Int(maximum), key: .maxDDC, for: .brightness)
        if let current, !self.hasLocalChange {
          let minimum = self.readPrefAsInt(key: .minDDCOverride, for: .brightness)
          let hardware = Int(maximum) > minimum
            ? (Float(Int(current) - minimum) / Float(Int(maximum) - minimum)).clamped(to: 0...1)
            : 1
          let level = DisplayBrightnessMath.level(
            forHardware: hardware,
            currentLevel: self.getBrightness(),
            extraDimming: DisplayManager.shared.isExtraDimmingEnabled
          )
          self.savePref(level, key: .value, for: .brightness)
          self.brightness = level
        }
      }
      self.reapplyBrightness()
    }
    DisplayManager.shared.notifyBrightnessStateChanged()
  }

  private func handleDDCFailure() {
    guard self.method != .software else { return }
    os_log("DDC writes to display %{public}@ keep failing, switching to software dimming", type: .info, String(self.identifier))
    self.method = .software
    self.channel?.cancel()
    self.channel = nil
    self.reapplyBrightness()
    DisplayManager.shared.notifyBrightnessStateChanged()
  }
}