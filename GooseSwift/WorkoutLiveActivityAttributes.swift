import ActivityKit
import Foundation

struct WorkoutLiveActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var status: String
    var timerStartDate: Date?
    var elapsedSeconds: TimeInterval
    var currentHeartRate: Int?
    var averageHeartRate: Int?
    var maxHeartRate: Int?
    var activeCalories: Int
    var distanceMeters: Double?
    var isPaused: Bool
    var updatedAt: Date
  }

  var sessionID: String
  var activityName: String
  var activitySystemImage: String
  var activityTintHex: String
  var environmentName: String
  var usesGPS: Bool
  var usesImperialUnits: Bool
}
