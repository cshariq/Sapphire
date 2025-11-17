//
//  PrefKey.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-10-20

enum PrefKey: String {

  case SUEnableAutomaticChecks

  case isBetaChannel

  case buildNumber

  case appAlreadyLaunched

  case menuIcon

  case menuItemStyle

  case keyboardBrightness

  case keyboardVolume

  case disableAltBrightnessKeys

  case hideBrightness

  case showContrast

  case hideVolume

  case disableCombinedBrightness

  case separateCombinedScale

  case hideAppleFromMenu

  case enableSliderSnap

  case enableSliderPercent

  case showTickMarks

  case startupAction

  case showAdvancedSettings

  case allowZeroSwBrightness

  case multiKeyboardBrightness

  case multiKeyboardVolume

  case useFineScaleBrightness

  case useFineScaleVolume

  case disableSmoothBrightness

  case enableBrightnessSync

  case multiSliders

  case enableMuteUnmute

  case hideOsd

  case longerDelay

  case pollingMode

  case pollingCount

  case avoidGamma

  case audioDeviceNameOverride

  case isDisabled

  case forceSw

  case SwBrightness

  case combinedBrightnessSwitchingPoint

  case friendlyName

  case value

  case isTouched

  case minDDCOverride

  case maxDDC

  case maxDDCOverride

  case curveDDC

  case unavailableDDC

  case invertDDC

  case remapDDC
}

enum MultiKeyboardBrightness: Int {
  case mouse = 0
  case allScreens = 1
  case focusInsteadOfMouse = 2
}

enum MultiKeyboardVolume: Int {
  case mouse = 0
  case allScreens = 1
  case audioDeviceNameMatching = 2
}

enum StartupAction: Int {
  case doNothing = 0
  case write = 1
  case read = 2
}

enum MultiSliders: Int {
  case separate = 0
  case relevant = 1
  case combine = 2
}

enum PollingMode: Int {
  case none = -2
  case minimal = -1
  case normal = 0
  case heavy = 1
  case custom = 2
}

enum MenuIcon: Int {
  case show = 0
  case sliderOnly = 1
  case hide = 2
}

enum MenuItemStyle: Int {
  case icon = 0
  case text = 1
  case hide = 2
}

enum KeyboardBrightness: Int {
  case media = 0
  case custom = 1
  case both = 2
  case disabled = 3
}

enum KeyboardVolume: Int {
  case media = 0
  case custom = 1
  case both = 2
  case disabled = 3
}