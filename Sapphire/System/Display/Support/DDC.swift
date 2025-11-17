//
//  DDC.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-18.
//

import Foundation

// MARK: - DDC Communication Wrapper
public class DDC {
  private let ddc: IntelDDC?

  public init?(for displayId: CGDirectDisplayID) {
    self.ddc = IntelDDC(for: displayId)
  }

  public func write(command: UInt8, value: UInt16) -> Bool {
    return self.ddc?.write(command: command, value: value) ?? false
  }

  public func read(command: UInt8, tries: UInt) -> (UInt16, UInt16)? {
    return self.ddc?.read(command: command, tries: tries)
  }
}