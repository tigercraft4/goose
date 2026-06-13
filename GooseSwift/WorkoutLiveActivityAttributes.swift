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

  init(
    sessionID: String,
    activityName: String,
    activitySystemImage: String,
    activityTintHex: String,
    environmentName: String,
    usesGPS: Bool,
    usesImperialUnits: Bool
  ) {
    self.sessionID = sessionID
    self.activityName = activityName
    self.activitySystemImage = activitySystemImage
    self.activityTintHex = activityTintHex
    self.environmentName = environmentName
    self.usesGPS = usesGPS
    self.usesImperialUnits = usesImperialUnits
  }

  enum CodingKeys: String, CodingKey {
    case sessionID
    case activityName
    case activitySystemImage
    case activityTintHex
    case environmentName
    case usesGPS
    case usesImperialUnits
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    sessionID = try container.decode(String.self, forKey: .sessionID)
    activityName = try container.decode(String.self, forKey: .activityName)
    activitySystemImage = try container.decode(String.self, forKey: .activitySystemImage)
    activityTintHex = try container.decode(String.self, forKey: .activityTintHex)
    environmentName = try container.decode(String.self, forKey: .environmentName)
    usesGPS = try container.decode(Bool.self, forKey: .usesGPS)
    usesImperialUnits = try container.decodeIfPresent(Bool.self, forKey: .usesImperialUnits) ?? false
  }
}
