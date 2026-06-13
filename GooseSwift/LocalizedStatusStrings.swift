import Foundation


// MARK: - Display-layer localisation for dynamic @Published status strings
//
// Raw @Published values (e.g. "disconnected", "idle", "poweredOn") are state-machine
// constants — they must remain unchanged in GooseBLEClient and GooseAppModel.
// These extension methods are the only translation boundary: call .localizedXxx only
// at view display sites (Text, LabeledContent value:, statusText). Never use them in
// guards, comparisons, or switch statements that drive control flow (Pitfall 2 / D-03).
//
// Keys are the English source strings; translations live in Localizable.xcstrings.

extension String {

  // MARK: - BLE Connection State (GooseBLEClient.connectionState)
  // Raw values: "disconnected", "connecting", "connected", "discovering", "ready"

  var localizedConnectionState: String {
    switch self {
    case "disconnected": return String(localized: "Disconnected")
    case "connecting": return String(localized: "Connecting...")
    case "connected": return String(localized: "Connected")
    case "discovering": return String(localized: "Discovering...")
    case "ready": return String(localized: "Ready")
    default: return self
    }
  }

  // MARK: - HR Monitor Connection State (GooseBLEClient.hrConnectionState)
  // Raw values: "disconnected", "connecting", "connected"

  var localizedHRConnectionState: String {
    switch self {
    case "disconnected": return String(localized: "Disconnected")
    case "connecting": return String(localized: "Connecting...")
    case "connected": return String(localized: "Connected")
    default: return self
    }
  }

  // MARK: - Bluetooth State (GooseBLEClient.bluetoothState)
  // Raw values: "not requested", "powered on", "powered off", "unauthorized",
  //             "unsupported", "resetting", "unknown", "bluetooth unavailable"

  var localizedBluetoothState: String {
    switch self {
    case "powered on":   return String(localized: "Active")
    case "powered off":  return String(localized: "BLUETOOTH OFF")
    case "unauthorized": return String(localized: "NOT AUTHORISED")
    case "unsupported":  return String(localized: "Not supported")
    case "resetting":    return String(localized: "Resetting...")
    case "not requested": return String(localized: "Not requested")
    case "unknown":      return String(localized: "Unknown")
    case "bluetooth unavailable": return String(localized: "NOT AUTHORISED")
    default: return self
    }
  }

  // MARK: - HR Bluetooth State (GooseBLEClient.hrBluetoothState)
  // Raw values match centralManagerDidUpdateState: "poweredOn", "poweredOff",
  //             "unauthorized", "unsupported", "resetting", "unknown"

  var localizedHRBluetoothState: String {
    switch self {
    case "poweredOn":    return String(localized: "Active")
    case "poweredOff":   return String(localized: "BLUETOOTH OFF")
    case "unauthorized": return String(localized: "NOT AUTHORISED")
    case "unsupported":  return String(localized: "Not supported")
    case "resetting":    return String(localized: "Resetting...")
    case "unknown":      return String(localized: "Unknown")
    default: return self
    }
  }

  // MARK: - Reconnect State (GooseBLEClient.reconnectState)
  // Raw values include "idle", "already connected", "forgotten", "remembered rejected",
  //   "blocked", "waiting for bluetooth", "no remembered device", "retrieving remembered",
  //   "remembered was not WHOOP", "scanning for remembered WHOOP", "scanning for remembered",
  //   "scanning for WHOOP physiology", "failed after 10 attempts", "connecting",
  //   "reconnecting (attempt N/10)" (from ReconnectBackoff.statusString)

  var localizedReconnectState: String {
    switch self {
    case "idle":               return String(localized: "Idle")
    case "already connected":  return String(localized: "Already connected")
    case "connecting":         return String(localized: "Connecting...")
    case "failed after 10 attempts": return String(localized: "Failed after 10 attempts")
    case "blocked":            return String(localized: "Blocked")
    case "waiting for bluetooth": return String(localized: "Waiting for Bluetooth")
    case "no remembered device": return String(localized: "No saved device")
    case "retrieving remembered": return String(localized: "Retrieving saved device...")
    case "remembered was not WHOOP": return String(localized: "Saved device is not WHOOP")
    case "scanning for remembered WHOOP": return String(localized: "Scanning for saved WHOOP...")
    case "scanning for remembered": return String(localized: "Scanning for saved device...")
    case "scanning for WHOOP physiology": return String(localized: "Scanning for WHOOP physiology...")
    case "forgotten": return String(localized: "Forgotten")
    case "remembered rejected": return String(localized: "Device rejected")
    default:
      if self.hasPrefix("reconnecting") {
        return String(localized: "Reconnecting...")
      }
      return self
    }
  }

  // MARK: - HR Reconnect State (GooseBLEClient.hrReconnectState)
  // Shares the same ReconnectBackoff pattern; simpler value set in practice.

  var localizedHRReconnectState: String {
    switch self {
    case "idle":              return String(localized: "Idle")
    case "already connected": return String(localized: "Already connected")
    case "failed after 10 attempts": return String(localized: "Failed after 10 attempts")
    default:
      if self.hasPrefix("reconnecting") {
        return String(localized: "Reconnecting...")
      }
      return self
    }
  }

  // MARK: - Historical Sync Status (GooseBLEClient.historicalSyncStatus)
  // Raw values: "idle", "syncing", "waiting", "synced", "failed"

  var localizedHistoricalSyncStatus: String {
    switch self {
    case "idle":    return String(localized: "Idle")
    case "syncing": return String(localized: "Syncing...")
    case "waiting": return String(localized: "Waiting...")
    case "synced":  return String(localized: "Synced")
    case "failed":  return String(localized: "Failed")
    default: return self
    }
  }

  // MARK: - Strap Clock Status (GooseBLEClient.strapClockStatus)
  // Raw values: "Not read", "Clock command already in flight",
  //   "Clock command blocked by alarm command", "Syncing clock",
  //   "Clock out by ...; syncing", "Clock in sync", "Clock synced",
  //   dynamic strings from clock offset calculations

  var localizedStrapClockStatus: String {
    switch self {
    case "Not read":    return String(localized: "Not read")
    case "Syncing clock": return String(localized: "Syncing clock...")
    case "Clock in sync": return String(localized: "Clock in sync")
    case "Clock synced":  return String(localized: "Clock synced")
    case "Clock command already in flight": return String(localized: "Clock command in progress")
    case "Clock command blocked by alarm command": return String(localized: "Clock blocked by alarm")
    default: return self
    }
  }

  // MARK: - Battery Power Status (GooseBLEClient.batteryPowerStatus)
  // Raw values: "Unknown", "Charging (inferred)", dynamic summary strings from BLE parsing

  var localizedBatteryPowerStatus: String {
    switch self {
    case "Unknown":            return String(localized: "Unknown")
    case "Charging (inferred)": return String(localized: "Charging (inferred)")
    default: return self
    }
  }

  // MARK: - Capture Status (GooseAppModel.healthPacketCaptureStatus)
  // Highly dynamic — pass through with known prefix localisation.

  var localizedCaptureStatus: String {
    switch self {
    case "No health packet capture": return String(localized: "No packet capture")
    case "No active health packet capture": return String(localized: "No active capture")
    default: return self
    }
  }

  // MARK: - Capture Target Summary (GooseAppModel.healthPacketCaptureTargetSummary)
  // Highly dynamic — passthrough with known base value.

  var localizedCaptureTargetSummary: String {
    switch self {
    case "No health packet capture": return String(localized: "No packet capture")
    default: return self
    }
  }

  // MARK: - Activity Detection Status (GooseAppModel.activityDetectionStatus)
  // Raw values include "Watching for movement packets", "Movement detected; priming GPS",
  //   "Candidate <title> recording", "Candidate <title> stored", dynamic pipeline strings.

  var localizedActivityDetectionStatus: String {
    switch self {
    case "Watching for movement packets": return String(localized: "Listening for motion packets")
    default: return self
    }
  }

  // MARK: - Packet Import Status (GooseAppModel.packetImportStatus)
  // Raw values include "No packet import", "Packet import failed", dynamic status strings.

  var localizedPacketImportStatus: String {
    switch self {
    case "No packet import":     return String(localized: "No packet import")
    case "Packet import failed": return String(localized: "Packet import failed")
    default: return self
    }
  }
}


extension GooseBLEBondingState {
  var localizedDescription: String {
    switch self {
    case .notStarted:         return String(localized: "Not started")
    case .started:            return String(localized: "Starting...")
    case .subscribed:         return String(localized: "Discovering...")
    case .completed:          return String(localized: "Connected")
    case .cancelled(let r):   return r.isEmpty ? String(localized: "Cancelled") : r
    }
  }
}
