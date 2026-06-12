import CoreLocation
import MapKit
import SwiftUI
import UIKit

enum FitnessColor {
  static let background = Color.black
  static let panel = Color(red: 0.10, green: 0.10, blue: 0.11)
  static let controlButton = Color(red: 0.16, green: 0.16, blue: 0.17)
  static let badge = Color(red: 0.18, green: 0.18, blue: 0.19)
  static let grabber = Color(red: 0.47, green: 0.47, blue: 0.50)
  static let pageDot = Color(red: 0.43, green: 0.43, blue: 0.45)
  static let secondaryText = Color(red: 0.58, green: 0.58, blue: 0.62)
  static let separator = Color.white.opacity(0.08)
  static let workoutYellow = Color(red: 1.0, green: 0.91, blue: 0.24)
  static let exerciseGreen = Color(red: 0.62, green: 1.0, blue: 0.12)
  static let lime = Color(red: 0.70, green: 1.0, blue: 0.18)
  static let movePink = Color(red: 1.0, green: 0.10, blue: 0.34)
  static let standCyan = Color(red: 0.39, green: 0.92, blue: 0.95)
  static let heartRed = Color(red: 1.0, green: 0.23, blue: 0.18)
  static let endRed = Color(red: 1.0, green: 0.25, blue: 0.27)
  static let segmentPink = Color(red: 1.0, green: 0.43, blue: 0.51)
  static let zoneBlue = Color(red: 0.34, green: 0.62, blue: 0.94)
  static let zoneTeal = Color(red: 0.18, green: 0.44, blue: 0.40)
  static let zoneGreen = Color(red: 0.33, green: 0.45, blue: 0.09)
  static let zoneOrange = Color(red: 0.39, green: 0.21, blue: 0.07)
  static let zoneRed = Color(red: 0.42, green: 0.04, blue: 0.18)
}

extension ActivityKind {
  var fitnessTitle: String {
    switch self {
    case .run: "Outdoor Run"
    case .indoorRun: "Indoor Run"
    case .walk: "Outdoor Walk"
    case .indoorWalk: "Indoor Walk"
    case .hike: "Hiking"
    case .roadRide: "Outdoor Cycle"
    case .mountainBike: "Mountain Biking"
    case .soccer: "Soccer"
    case .strength: "Traditional Strength Training"
    case .hiit: "High Intensity Interval Training"
    case .yoga: "Yoga"
    case .row: "Rowing"
    case .indoorRide: "Indoor Cycle"
    case .elliptical: "Elliptical"
    case .stairStepper: "Stair Stepper"
    case .pilates: "Pilates"
    case .barre: "Barre"
    case .functionalTraining: "Functional Training"
    case .poolSwim: "Pool Swim"
    }
  }
}

let fitnessMetersPerMile: Double = 1609.344
let fitnessFeetPerMeter: Double = 3.28084

func fitnessDistanceParts(_ meters: CLLocationDistance, imperial: Bool = UnitPreference.isImperial) -> (value: String, unit: String) {
  if imperial {
    return (String(format: "%.2f", max(meters, 0) / fitnessMetersPerMile), "MI")
  }
  if meters >= 1000 {
    return (String(format: "%.2f", meters / 1000), "KM")
  }
  return ("\(Int(max(meters, 0).rounded()))", "M")
}

// Pace inputs are always seconds-per-kilometer (the tracker's native unit);
// imperial display converts to seconds-per-mile here.
func formatFitnessPace(_ secondsPerKilometer: TimeInterval?, imperial: Bool = UnitPreference.isImperial) -> String {
  guard let secondsPerKilometer, secondsPerKilometer.isFinite else {
    return "--'--\""
  }
  let secondsPerUnit = imperial ? secondsPerKilometer * (fitnessMetersPerMile / 1000) : secondsPerKilometer
  let totalSeconds = max(Int(secondsPerUnit.rounded()), 0)
  return String(format: "%d'%02d\"", totalSeconds / 60, totalSeconds % 60)
}

func fitnessPaceUnitLabel(imperial: Bool = UnitPreference.isImperial) -> String {
  imperial ? "MI" : "KM"
}

func fitnessElevationParts(_ meters: Double, imperial: Bool = UnitPreference.isImperial) -> (value: String, unit: String) {
  if imperial {
    return ("\(Int((max(meters, 0) * fitnessFeetPerMeter).rounded()))", "FT")
  }
  return ("\(Int(max(meters, 0).rounded()))", "M")
}

func formatFitnessDockDuration(_ elapsed: TimeInterval) -> String {
  let seconds = max(elapsed, 0)
  let minutes = Int(seconds) / 60
  let wholeSeconds = Int(seconds) % 60
  let hundredths = Int((seconds - floor(seconds)) * 100)
  return String(format: "%02d:%02d.%02d", minutes, wholeSeconds, hundredths)
}

func formatDuration(_ elapsed: TimeInterval) -> String {
  let seconds = max(Int(elapsed.rounded()), 0)
  let hours = seconds / 3600
  let minutes = (seconds % 3600) / 60
  let remainingSeconds = seconds % 60
  if hours > 0 {
    return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
  }
  return String(format: "%02d:%02d", minutes, remainingSeconds)
}

func authorizationText(_ status: CLAuthorizationStatus) -> String {
  switch status {
  case .notDetermined: "not determined"
  case .restricted: "restricted"
  case .denied: "denied"
  case .authorizedAlways: "authorized always"
  case .authorizedWhenInUse: "authorized when in use"
  @unknown default: "unknown"
  }
}
