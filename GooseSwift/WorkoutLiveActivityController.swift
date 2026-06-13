import ActivityKit
import Foundation

@MainActor
final class WorkoutLiveActivityController {
  static let shared = WorkoutLiveActivityController()

  private var liveActivity: ActivityKit.Activity<WorkoutLiveActivityAttributes>?
  private var lastUpdateAt = Date.distantPast
  private var lastState: WorkoutLiveActivityAttributes.ContentState?
  private let minimumUpdateInterval: TimeInterval = 15

  private init() {}

  func start(
    activity: ActivityKind,
    session: ActivitySessionModel,
    heartRate: Int?,
    distanceMeters: Double
  ) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      return
    }

    if let liveActivity = currentLiveActivity {
      endLiveActivity(liveActivity, state: makeState(session: session, heartRate: heartRate, distanceMeters: distanceMeters, status: "Ended"))
    }

    let attributes = WorkoutLiveActivityAttributes(
      sessionID: UUID().uuidString,
      activityName: activity.fitnessTitle,
      activitySystemImage: activity.systemImage,
      activityTintHex: tintHex(for: activity),
      environmentName: environmentName(for: activity),
      usesGPS: activity.usesGPS
    )
    let state = makeState(session: session, heartRate: heartRate, distanceMeters: distanceMeters, status: session.statusText)
    let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(60 * 30))

    do {
      liveActivity = try ActivityKit.Activity.request(attributes: attributes, content: content, pushType: nil)
      lastState = state
      lastUpdateAt = Date()
    } catch {
      NSLog("GooseSwift workout Live Activity start failed: \(String(describing: error))")
    }
  }

  func update(
    session: ActivitySessionModel,
    heartRate: Int?,
    distanceMeters: Double,
    force: Bool = false
  ) {
    guard let liveActivity = currentLiveActivity else {
      return
    }

    let now = Date()
    let state = makeState(session: session, heartRate: heartRate, distanceMeters: distanceMeters, status: session.statusText)
    guard force || shouldUpdate(to: state, at: now) else {
      return
    }

    lastState = state
    lastUpdateAt = now
    Task {
      await liveActivity.update(ActivityContent(state: state, staleDate: now.addingTimeInterval(60 * 30)))
    }
  }

  func end(
    session: ActivitySessionModel,
    heartRate: Int?,
    distanceMeters: Double
  ) {
    guard let liveActivity = currentLiveActivity else {
      return
    }

    let state = makeState(session: session, heartRate: heartRate, distanceMeters: distanceMeters, status: "Ended")
    endLiveActivity(liveActivity, state: state)
  }

  private var currentLiveActivity: ActivityKit.Activity<WorkoutLiveActivityAttributes>? {
    if let liveActivity {
      return liveActivity
    }
    liveActivity = ActivityKit.Activity<WorkoutLiveActivityAttributes>.activities.first
    return liveActivity
  }

  private func endLiveActivity(
    _ liveActivity: ActivityKit.Activity<WorkoutLiveActivityAttributes>,
    state: WorkoutLiveActivityAttributes.ContentState
  ) {
    self.liveActivity = nil
    lastState = nil
    lastUpdateAt = .distantPast
    Task {
      await liveActivity.end(
        ActivityContent(state: state, staleDate: nil),
        dismissalPolicy: .after(Date().addingTimeInterval(30 * 60))
      )
    }
  }

  private func shouldUpdate(to state: WorkoutLiveActivityAttributes.ContentState, at now: Date) -> Bool {
    guard now.timeIntervalSince(lastUpdateAt) >= minimumUpdateInterval else {
      return statusChanged(to: state)
    }
    return true
  }

  private func statusChanged(to state: WorkoutLiveActivityAttributes.ContentState) -> Bool {
    guard let lastState else {
      return true
    }
    return lastState.status != state.status
      || lastState.isPaused != state.isPaused
      || lastState.currentHeartRate != state.currentHeartRate
      || lastState.distanceMeters != state.distanceMeters
  }

  private func makeState(
    session: ActivitySessionModel,
    heartRate: Int?,
    distanceMeters: Double,
    status: String
  ) -> WorkoutLiveActivityAttributes.ContentState {
    let now = Date()
    let elapsed = max(session.elapsed, 0)
    return WorkoutLiveActivityAttributes.ContentState(
      status: status,
      timerStartDate: session.isActive && !session.isPaused ? now.addingTimeInterval(-elapsed) : nil,
      elapsedSeconds: elapsed,
      currentHeartRate: heartRate,
      averageHeartRate: session.averageHeartRate,
      maxHeartRate: session.maxHeartRate,
      activeCalories: max(Int(elapsed / 8), 0),
      distanceMeters: distanceMeters > 0 ? distanceMeters : nil,
      isPaused: session.isPaused,
      updatedAt: now,
      usesImperialUnits: UnitPreference.isImperial
    )
  }

  private func environmentName(for activity: ActivityKind) -> String {
    switch activity.environment {
    case .outdoor: "Outdoor"
    case .indoor: "Indoor"
    case .pool: "Pool"
    }
  }

  private func tintHex(for activity: ActivityKind) -> String {
    switch activity {
    case .run, .stairStepper:
      return "FF9500"
    case .indoorRun, .strength:
      return "FF3B30"
    case .walk:
      return "34C759"
    case .indoorWalk, .mountainBike:
      return "00C7BE"
    case .hike:
      return "A2845E"
    case .roadRide:
      return "0A84FF"
    case .soccer:
      return "30D5C8"
    case .hiit, .barre:
      return "FF2D55"
    case .yoga, .pilates:
      return "BF5AF2"
    case .row, .poolSwim:
      return "64D2FF"
    case .indoorRide:
      return "5E5CE6"
    case .elliptical:
      return "FFD60A"
    case .functionalTraining:
      return "8E8E93"
    }
  }
}
