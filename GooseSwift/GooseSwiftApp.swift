import BackgroundTasks
import SwiftUI

@main
struct GooseSwiftApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @State private var model = GooseAppModel()
  @State private var accountSession = AccountSession()
  @StateObject private var router = AppRouter()

  // Weak reference used by the BGTask handler closure to reach the model.
  // Set in .onAppear before any background wakeup can occur.
  nonisolated(unsafe) static weak var sharedModel: GooseAppModel?

  init() {
    GooseTheme.configureAppearance()
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: "com.goose.swift.bg-sync",
      using: nil
    ) { task in
      guard let bgTask = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      Task { @MainActor in
        if let model = GooseSwiftApp.sharedModel {
          model.handleBGAppRefresh(task: bgTask)
        } else {
          bgTask.setTaskCompleted(success: false)
        }
      }
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(model)
        .environment(accountSession)
        .environmentObject(model.packetMonitor)
        .environmentObject(model.ble.messageStore)
        .environmentObject(router)
        .onAppear {
          GooseSwiftApp.sharedModel = model
          model.scheduleNextBGAppRefresh()
        }
        .onOpenURL { url in
          if model.handleDebugCommandDeepLink(url) {
            router.selectedTab = .more
          } else {
            _ = router.handleDeepLink(url)
          }
        }
        .onChange(of: scenePhase) { _, phase in
          switch phase {
          case .active:
            model.handleAppLifecycleChange("active")
          case .inactive:
            model.handleAppLifecycleChange("inactive")
          case .background:
            model.handleAppLifecycleChange("background")
          @unknown default:
            model.handleAppLifecycleChange("unknown")
          }
        }
    }
  }
}
