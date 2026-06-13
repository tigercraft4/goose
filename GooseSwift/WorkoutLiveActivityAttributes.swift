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
    var usesImperialUnits: Bool

    init(
      status: String,
      timerStartDate: Date?,
      elapsedSeconds: TimeInterval,
      currentHeartRate: Int?,
      averageHeartRate: Int?,
      maxHeartRate: Int?,
      activeCalories: Int,
      distanceMeters: Double?,
      isPaused: Bool,
      updatedAt: Date,
      usesImperialUnits: Bool
    ) {
      self.status = status
      self.timerStartDate = timerStartDate
      self.elapsedSeconds = elapsedSeconds
      self.currentHeartRate = currentHeartRate
      self.averageHeartRate = averageHeartRate
      self.maxHeartRate = maxHeartRate
      self.activeCalories = activeCalories
      self.distanceMeters = distanceMeters
      self.isPaused = isPaused
      self.updatedAt = updatedAt
      self.usesImperialUnits = usesImperialUnits
    }

    enum CodingKeys: String, CodingKey {
      case status
      case timerStartDate
      case elapsedSeconds
      case currentHeartRate
      case averageHeartRate
      case maxHeartRate
      case activeCalories
      case distanceMeters
      case isPaused
      case updatedAt
      case usesImperialUnits
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      status = try container.decode(String.self, forKey: .status)
      timerStartDate = try container.decodeIfPresent(Date.self, forKey: .timerStartDate)
      elapsedSeconds = try container.decode(TimeInterval.self, forKey: .elapsedSeconds)
      currentHeartRate = try container.decodeIfPresent(Int.self, forKey: .currentHeartRate)
      averageHeartRate = try container.decodeIfPresent(Int.self, forKey: .averageHeartRate)
      maxHeartRate = try container.decodeIfPresent(Int.self, forKey: .maxHeartRate)
      activeCalories = try container.decode(Int.self, forKey: .activeCalories)
      distanceMeters = try container.decodeIfPresent(Double.self, forKey: .distanceMeters)
      isPaused = try container.decode(Bool.self, forKey: .isPaused)
      updatedAt = try container.decode(Date.self, forKey: .updatedAt)
      usesImperialUnits = try container.decodeIfPresent(Bool.self, forKey: .usesImperialUnits) ?? false
    }
  }

  var sessionID: String
  var activityName: String
  var activitySystemImage: String
  var activityTintHex: String
  var environmentName: String
  var usesGPS: Bool

  init(
    sessionID: String,
    activityName: String,
    activitySystemImage: String,
    activityTintHex: String,
    environmentName: String,
    usesGPS: Bool
  ) {
    self.sessionID = sessionID
    self.activityName = activityName
    self.activitySystemImage = activitySystemImage
    self.activityTintHex = activityTintHex
    self.environmentName = environmentName
    self.usesGPS = usesGPS
  }
}
