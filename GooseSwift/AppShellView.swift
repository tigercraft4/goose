import SwiftUI

struct AppShellView: View {
  @EnvironmentObject private var router: AppRouter
  @Environment(GooseAppModel.self) private var model
  @State private var homeHealthPath: [HealthRoute] = []
  @State private var homeSelectedDate = Date()
  @State private var hasLoadedCoach = false

  var body: some View {
    TabView(selection: tabSelection) {
      ForEach(GooseAppTab.allCases) { tab in
        tabNavigationStack(for: tab)
        .tabItem {
          Label(tab.title, systemImage: tab.systemImage)
        }
        .tag(tab)
      }
    }
    .onChange(of: router.selectedTab) { _, newTab in
      if newTab == .coach {
        hasLoadedCoach = true
      }
    }
  }

  private var tabSelection: Binding<GooseAppTab> {
    Binding {
      router.selectedTab
    } set: { newTab in
      if newTab == .coach {
        hasLoadedCoach = true
      }
      if newTab == router.selectedTab {
        router.reselect(newTab)
        return
      }
      router.selectedTab = newTab
    }
  }

  @ViewBuilder
  private func tabNavigationStack(for tab: GooseAppTab) -> some View {
    if tab == .home {
      NavigationStack(path: $homeHealthPath) {
        tabContent(for: tab)
          .navigationDestination(for: HealthRoute.self) { route in
            HealthRouteDestinationView(route: route, selectedDate: $homeSelectedDate)
          }
      }
    } else if tab == .health {
      NavigationStack(path: $router.healthPath) {
        tabContent(for: tab)
      }
    } else if tab == .more {
      NavigationStack(path: $router.morePath) {
        tabContent(for: tab)
      }
    } else {
      NavigationStack {
        tabContent(for: tab)
      }
    }
  }

  @ViewBuilder
  private func tabContent(for tab: GooseAppTab) -> some View {
    switch tab {
    case .home:
      HomeDashboardView(
        selectedDate: $homeSelectedDate,
        openHealthRoute: openHomeHealthRoute
      )
    case .health:
      HealthView()
    case .coach:
      if hasLoadedCoach || router.selectedTab == .coach {
        CoachView()
          .onAppear {
            hasLoadedCoach = true
          }
      } else {
        Color.clear
          .accessibilityHidden(true)
      }
    case .more:
      MoreView()
    }
  }

  private func openHomeHealthRoute(_ route: HealthRoute) {
    Task { @MainActor in
      homeHealthPath = [route]
    }
  }
}

enum GooseAppTab: String, CaseIterable, Identifiable {
  case home
  case health
  case coach
  case more

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home: String(localized: "Home")
    case .health: String(localized: "Health")
    case .coach: String(localized: "Coach")
    case .more: String(localized: "More")
    }
  }

  var systemImage: String {
    switch self {
    case .home: "house"
    case .health: "heart.text.square"
    case .coach: "sparkles"
    case .more: "ellipsis.circle"
    }
  }

}
