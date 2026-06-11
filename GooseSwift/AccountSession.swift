import Foundation
import Observation
import SwiftUI
import UIKit

struct GooseAccount: Codable, Equatable {
  let id: String
  let name: String?
  let email: String
}

struct ClaimedDevice: Codable, Identifiable {
  let deviceID: String
  let displayName: String?
  let nickname: String?

  var id: String { deviceID }

  enum CodingKeys: String, CodingKey {
    case deviceID = "device_id"
    case displayName = "display_name"
    case nickname
  }
}

struct MockDeviceMetric: Codable, Identifiable {
  let id: String
  let deviceID: String
  let recordedAt: Date
  let heartRate: Int?
  let battery: Double?

  enum CodingKeys: String, CodingKey {
    case id
    case deviceID = "device_id"
    case recordedAt = "recorded_at"
    case heartRate = "heart_rate"
    case battery
  }
}

private struct AccountAuthResponse: Decodable {
  let user: GooseAccount
  let apiToken: String

  enum CodingKeys: String, CodingKey {
    case user
    case apiToken = "api_token"
  }
}

private struct CurrentAccountResponse: Decodable {
  let user: GooseAccount?
}

private struct ClaimResponse: Decodable {
  let deviceID: String

  enum CodingKeys: String, CodingKey {
    case deviceID = "device_id"
  }
}

private struct APIErrorResponse: Decodable {
  let detail: String?
}

enum AccountAPIError: LocalizedError {
  case missingServer
  case invalidServer
  case signedOut
  case unauthorized
  case server(String)
  case invalidResponse

  var errorDescription: String? {
    switch self {
    case .missingServer: "Enter your Goose server URL."
    case .invalidServer: "Enter a valid HTTPS URL, or a local HTTP address."
    case .signedOut: "Sign in to continue."
    case .unauthorized: "Your session has expired. Sign in again."
    case .server(let message): message
    case .invalidResponse: "The server returned an invalid response."
    }
  }
}

@MainActor
@Observable
final class AccountSession {
  private static let accountKey = "goose.account.current"

  private(set) var account: GooseAccount?
  private(set) var claimedDevices: [ClaimedDevice] = []
  private(set) var mockMetrics: [MockDeviceMetric] = []
  private(set) var isLoadingMockMetrics = false
  private(set) var mockMetricsError: String?
  private(set) var isWorking = false
  private(set) var isRestoringSession = false
  private(set) var prefersLoginAfterLogout = false
  var errorMessage: String?

  var token: String {
    (try? RemoteServerKeychain.loadToken()) ?? ""
  }

  var isAuthenticated: Bool {
    account != nil && !token.isEmpty
  }

  init() {
    let storedToken = (try? RemoteServerKeychain.loadToken()) ?? ""
    if let data = UserDefaults.standard.data(forKey: Self.accountKey) {
      account = try? JSONDecoder().decode(GooseAccount.self, from: data)
    }
    if storedToken.isEmpty || account == nil {
      try? RemoteServerKeychain.deleteToken()
      UserDefaults.standard.removeObject(forKey: Self.accountKey)
      account = nil
    } else {
      isRestoringSession = true
    }
  }

  func login(serverURL: String, email: String, password: String) async -> Bool {
    await authenticate(
      path: "/v1/auth/login",
      serverURL: serverURL,
      body: ["email": email, "password": password]
    )
  }

  func signup(serverURL: String, name: String, email: String, password: String) async -> Bool {
    await authenticate(
      path: "/v1/auth/signup",
      serverURL: serverURL,
      body: ["name": name, "email": email, "password": password]
    )
  }

  func logout() {
    try? RemoteServerKeychain.deleteToken()
    UserDefaults.standard.removeObject(forKey: Self.accountKey)
    account = nil
    claimedDevices = []
    mockMetrics = []
    isLoadingMockMetrics = false
    mockMetricsError = nil
    isWorking = false
    isRestoringSession = false
    prefersLoginAfterLogout = true
    errorMessage = nil
  }

  func restoreSession() async {
    guard isRestoringSession else {
      return
    }
    defer { isRestoringSession = false }

    do {
      let response: CurrentAccountResponse = try await request(path: "/v1/me")
      guard let restoredAccount = response.user else {
        logout()
        return
      }
      account = restoredAccount
      UserDefaults.standard.set(
        try JSONEncoder().encode(restoredAccount),
        forKey: Self.accountKey
      )
      _ = try await fetchDevices()
    } catch AccountAPIError.unauthorized {
      logout()
    } catch AccountAPIError.signedOut {
      logout()
    } catch {
      // Keep a previously authenticated session available during temporary
      // connectivity failures. The next protected request will retry auth.
    }
  }

  func fetchDevices() async throws -> [ClaimedDevice] {
    let devices: [ClaimedDevice] = try await request(path: "/v1/devices")
    claimedDevices = devices
    return devices
  }

  func refreshClaimedDevices() async {
    guard isAuthenticated else {
      claimedDevices = []
      return
    }
    _ = try? await fetchDevices()
  }

  func claimDevice(deviceID: String, name: String) async throws {
    let body = ["device_id": deviceID, "name": name, "device_type": "whoop"]
    let _: ClaimResponse = try await request(path: "/v1/devices/claim", method: "POST", body: body)
    _ = try await fetchDevices()
  }

  func unclaimDevice(deviceID: String) async throws {
    let encoded = deviceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deviceID
    let _: ClaimResponse = try await request(path: "/v1/devices/\(encoded)/claim", method: "DELETE")
    _ = try await fetchDevices()
  }

  func insertMetric(deviceID: String, heartRate: Int, battery: Double) async throws {
    let body: [String: Any] = [
      "device_id": deviceID,
      "heart_rate": heartRate,
      "battery": battery,
    ]
    let inserted: MockDeviceMetric = try await request(
      path: "/v1/metrics",
      method: "POST",
      body: body
    )
    mockMetrics.removeAll { $0.id == inserted.id }
    mockMetrics.insert(inserted, at: 0)
    mockMetricsError = nil
  }

  func fetchMetrics() async throws -> [MockDeviceMetric] {
    let metrics: [MockDeviceMetric] = try await request(path: "/v1/metrics?limit=100")
    mockMetrics = metrics
    mockMetricsError = nil
    return metrics
  }

  func refreshMockMetrics() async {
    guard isAuthenticated else {
      mockMetrics = []
      mockMetricsError = nil
      return
    }

    isLoadingMockMetrics = true
    defer { isLoadingMockMetrics = false }
    do {
      _ = try await fetchMetrics()
    } catch {
      mockMetricsError = error.localizedDescription
    }
  }

  private func authenticate(
    path: String,
    serverURL: String,
    body: [String: String]
  ) async -> Bool {
    guard !serverURL.isEmpty else {
      errorMessage = AccountAPIError.missingServer.localizedDescription
      return false
    }
    guard RemoteServerURLValidator.validate(serverURL) else {
      errorMessage = AccountAPIError.invalidServer.localizedDescription
      return false
    }

    isWorking = true
    errorMessage = nil
    defer { isWorking = false }
    do {
      let normalizedURL = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      UserDefaults.standard.set(normalizedURL, forKey: RemoteServerStorage.serverURL)
      let response: AccountAuthResponse = try await request(
        path: path,
        method: "POST",
        body: body,
        authenticated: false
      )
      try RemoteServerKeychain.saveToken(response.apiToken)
      account = response.user
      isRestoringSession = false
      prefersLoginAfterLogout = false
      UserDefaults.standard.set(try JSONEncoder().encode(response.user), forKey: Self.accountKey)
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  private func request<Response: Decodable>(
    path: String,
    method: String = "GET",
    body: Any? = nil,
    authenticated: Bool = true
  ) async throws -> Response {
    let server = UserDefaults.standard.string(forKey: RemoteServerStorage.serverURL) ?? ""
    guard !server.isEmpty else { throw AccountAPIError.missingServer }
    guard let baseURL = URL(string: server),
          let url = URL(string: path, relativeTo: baseURL) else {
      throw AccountAPIError.invalidServer
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 20
    if let body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    if authenticated {
      guard !token.isEmpty else { throw AccountAPIError.signedOut }
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw AccountAPIError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      let detail = try? JSONDecoder().decode(APIErrorResponse.self, from: data).detail
      if http.statusCode == 401 {
        throw AccountAPIError.unauthorized
      }
      throw AccountAPIError.server(detail ?? "Request failed (\(http.statusCode)).")
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = fractional.date(from: value) {
        return date
      }
      let standard = ISO8601DateFormatter()
      if let date = standard.date(from: value) {
        return date
      }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid ISO-8601 date: \(value)"
      )
    }
    return try decoder.decode(Response.self, from: data)
  }
}

struct AccountWelcomeView: View {
  @Environment(AccountSession.self) private var session
  @Environment(\.colorScheme) private var colorScheme
  @State private var mode: AccountMode = .welcome
  @State private var serverURL = Self.initialServerURL
  @State private var name = ""
  @State private var email = ""
  @State private var password = ""

  var body: some View {
    GeometryReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if mode != .welcome {
            Button {
              session.errorMessage = nil
              mode = .welcome
            } label: {
              Label("Back", systemImage: "chevron.left")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(accountPrimaryText)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)
          }

          Spacer(minLength: mode == .welcome ? 54 : 12)

          VStack(alignment: .leading, spacing: 18) {
            ZStack {
              RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(accountIconBackground)
              Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(accountAccentGreen)
            }
            .frame(width: 66, height: 66)

            Text(mode.title)
              .font(.system(size: 38, weight: .black))
              .foregroundStyle(accountPrimaryText)
              .minimumScaleFactor(0.82)

            Text(mode.subtitle)
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(accountSecondaryText)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.bottom, 28)

          if mode == .welcome {
            welcomeActions
          } else {
            accountForm
          }

          Spacer(minLength: 40)
        }
        .frame(maxWidth: 520, minHeight: proxy.size.height, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(GooseTheme.appBackground.ignoresSafeArea())
    }
    .tint(accountAccentGreen)
    .animation(.easeOut(duration: 0.18), value: mode)
    .onAppear {
      if session.prefersLoginAfterLogout {
        mode = .login
      }
    }
  }

  private var welcomeActions: some View {
    VStack(spacing: 12) {
      Button("Log In") {
        session.errorMessage = nil
        mode = .login
      }
      .buttonStyle(AccountPrimaryButtonStyle())

      Button("Create Account") {
        session.errorMessage = nil
        mode = .signup
      }
      .buttonStyle(AccountSecondaryButtonStyle())
    }
  }

  private var accountForm: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        Text(mode.formTitle.uppercased())
          .font(.system(size: 13, weight: .black))
          .foregroundStyle(accountSecondaryText)
        Text(mode.formDetail)
          .font(.subheadline)
          .foregroundStyle(accountSecondaryText)
      }

      VStack(spacing: 12) {
        AccountInputField(
          title: "Server URL",
          text: $serverURL,
          contentType: .URL,
          keyboardType: .URL
        )

        if mode == .signup {
          AccountInputField(title: "Name", text: $name, contentType: .name)
        }

        AccountInputField(
          title: "Email",
          text: $email,
          contentType: .emailAddress,
          keyboardType: .emailAddress
        )

        AccountInputField(
          title: "Password",
          text: $password,
          contentType: mode == .signup ? .newPassword : .password,
          isSecure: true
        )
      }

      if mode == .signup {
        Text("Use at least 8 characters.")
          .font(.caption)
          .foregroundStyle(accountSecondaryText)
      }

      if let error = session.errorMessage {
        Label(error, systemImage: "exclamationmark.circle.fill")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(accountErrorRed)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
          .background(accountErrorRed.opacity(colorScheme == .dark ? 0.13 : 0.09))
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      }

      Button {
        submit()
      } label: {
        HStack(spacing: 10) {
          if session.isWorking {
            ProgressView()
              .tint(accountPrimaryButtonText)
          }
          Text(mode == .login ? "Log In" : "Create Account")
        }
      }
      .buttonStyle(AccountPrimaryButtonStyle())
      .disabled(!canSubmit)
    }
    .padding(18)
    .background(accountCardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .stroke(accountDivider, lineWidth: 1)
    }
  }

  private var canSubmit: Bool {
    guard !session.isWorking,
          !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !password.isEmpty else {
      return false
    }
    if mode == .signup {
      return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && password.count >= 8
    }
    return true
  }

  private func submit() {
    guard canSubmit else { return }
    Task {
      if mode == .login {
        _ = await session.login(serverURL: serverURL, email: email, password: password)
      } else {
        _ = await session.signup(
          serverURL: serverURL,
          name: name,
          email: email,
          password: password
        )
      }
    }
  }

  private static var initialServerURL: String {
    if let stored = UserDefaults.standard.string(forKey: RemoteServerStorage.serverURL),
       !stored.isEmpty {
      return stored
    }
#if DEBUG
    return "http://localhost:8770"
#else
    return ""
#endif
  }
}

private struct AccountInputField: View {
  let title: String
  @Binding var text: String
  var contentType: UITextContentType?
  var keyboardType: UIKeyboardType = .default
  var isSecure = false

  var body: some View {
    Group {
      if isSecure {
        SecureField(
          "",
          text: $text,
          prompt: Text(title).foregroundStyle(accountPlaceholderText)
        )
      } else {
        TextField(
          "",
          text: $text,
          prompt: Text(title).foregroundStyle(accountPlaceholderText)
        )
      }
    }
    .font(.system(size: 16, weight: .semibold))
    .foregroundStyle(accountPrimaryText)
    .textContentType(contentType)
    .keyboardType(keyboardType)
    .textInputAutocapitalization(contentType == .name ? .words : .never)
    .autocorrectionDisabled(contentType != .name)
    .padding(.horizontal, 15)
    .frame(minHeight: 52)
    .background(accountInputBackground)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(accountDivider, lineWidth: 1)
    }
  }
}

private enum AccountMode {
  case welcome
  case login
  case signup

  var title: String {
    switch self {
    case .welcome: "Welcome to Goose"
    case .login: "Welcome back"
    case .signup: "Create your account"
    }
  }

  var subtitle: String {
    switch self {
    case .welcome: "Your WHOOP data, owned by you."
    case .login: "Sign in to access your devices and health data."
    case .signup: "Claim devices and keep every upload account-scoped."
    }
  }

  var formTitle: String {
    switch self {
    case .welcome: ""
    case .login: "Account access"
    case .signup: "Your details"
    }
  }

  var formDetail: String {
    switch self {
    case .welcome: ""
    case .login: "Use the account connected to your Goose server."
    case .signup: "Your token will be stored securely in Keychain."
    }
  }
}

private struct AccountPrimaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 16, weight: .black))
      .foregroundStyle(accountPrimaryButtonText.opacity(isEnabled ? 1 : 0.58))
      .frame(maxWidth: .infinity, minHeight: 52)
      .background(
        accountAccentGreen.opacity(
          isEnabled ? (configuration.isPressed ? 0.76 : 1) : 0.30
        )
      )
      .clipShape(Capsule(style: .continuous))
  }
}

private struct AccountSecondaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 16, weight: .black))
      .foregroundStyle(accountPrimaryText.opacity(isEnabled ? 1 : 0.45))
      .frame(maxWidth: .infinity, minHeight: 52)
      .background(accountInputBackground.opacity(configuration.isPressed ? 0.65 : 1))
      .overlay {
        Capsule(style: .continuous)
          .stroke(accountDivider, lineWidth: 1)
      }
      .clipShape(Capsule(style: .continuous))
  }
}

private extension View {
  func accountField() -> some View {
    padding(.horizontal, 14)
      .padding(.vertical, 13)
      .foregroundStyle(accountPrimaryText)
      .background(accountInputBackground)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(accountDivider, lineWidth: 1)
      }
      .autocorrectionDisabled()
  }
}

private let accountAccentGreen = Color(red: 0.42, green: 0.84, blue: 0.30)
private let accountPrimaryText = Color(uiColor: .label)
private let accountSecondaryText = Color(uiColor: .secondaryLabel)
private let accountPlaceholderText = Color(uiColor: .placeholderText)
private let accountPrimaryButtonText = Color(uiColor: UIColor { traits in
  traits.userInterfaceStyle == .dark ? .black : .label
})
private let accountCardBackground = Color(uiColor: .secondarySystemGroupedBackground)
private let accountInputBackground = Color(uiColor: UIColor { traits in
  traits.userInterfaceStyle == .dark
    ? UIColor(red: 0.12, green: 0.16, blue: 0.18, alpha: 1)
    : .tertiarySystemGroupedBackground
})
private let accountIconBackground = Color(uiColor: UIColor { traits in
  traits.userInterfaceStyle == .dark
    ? UIColor(red: 0.12, green: 0.18, blue: 0.13, alpha: 1)
    : UIColor(red: 0.89, green: 0.97, blue: 0.88, alpha: 1)
})
private let accountDivider = Color(uiColor: .separator)
private let accountErrorRed = Color(uiColor: .systemRed)

struct AccountDevicesPanel: View {
  @Environment(AccountSession.self) private var session
  @State private var devices: [ClaimedDevice] = []
  @State private var metrics: [MockDeviceMetric] = []
  @State private var deviceID = "WHOOP-TEST-001"
  @State private var deviceName = ""
  @State private var heartRate = "72"
  @State private var battery = "88"
  @State private var isLoading = false
  @State private var message: String?
  @State private var pendingRemoval: ClaimedDevice?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("ACCOUNT DEVICES")
        .font(.system(size: 12, weight: .black))
        .foregroundStyle(.white.opacity(0.58))

      if devices.isEmpty {
        Text("No device claimed yet")
          .font(.headline)
          .foregroundStyle(.white)
      } else {
        ForEach(devices) { device in
          claimedDeviceCard(device)
        }
      }

      VStack(alignment: .leading, spacing: 10) {
        Text("Claim a device").font(.headline).foregroundStyle(.white)
        TextField("Device ID", text: $deviceID)
          .accountField()
          .textInputAutocapitalization(.characters)
        TextField("Device name", text: $deviceName)
          .accountField()
        Button("Claim Device") { Task { await claim() } }
          .buttonStyle(AccountPrimaryButtonStyle())
          .disabled(isLoading || deviceID.trimmingCharacters(in: .whitespaces).isEmpty)
      }

      if let first = devices.first {
        VStack(alignment: .leading, spacing: 10) {
          Text("Submit dummy data").font(.headline).foregroundStyle(.white)
          HStack {
            TextField("Heart rate", text: $heartRate).accountField().keyboardType(.numberPad)
            TextField("Battery", text: $battery).accountField().keyboardType(.decimalPad)
          }
          Button("Insert Metric for \(first.deviceID)") {
            Task { await insertMetric(for: first) }
          }
          .buttonStyle(AccountSecondaryButtonStyle())
          .disabled(isLoading)
        }
      }

      if !metrics.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Recent account data").font(.headline).foregroundStyle(.white)
          ForEach(metrics.prefix(8)) { metric in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(metric.deviceID).font(.caption.bold())
                Text(metric.recordedAt.formatted(date: .abbreviated, time: .shortened))
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Text(metricSummary(metric)).font(.caption.monospacedDigit())
            }
            .foregroundStyle(.white)
          }
        }
      }

      if let message {
        Text(message)
          .font(.caption)
          .foregroundStyle(message.hasPrefix("Error") ? .red : .green)
      }
    }
    .padding(18)
    .background(.white.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .task { await refresh() }
    .alert("Disconnect Device?", isPresented: removalAlertBinding, presenting: pendingRemoval) { device in
      Button("Cancel", role: .cancel) { pendingRemoval = nil }
      Button("Disconnect", role: .destructive) { Task { await remove(device) } }
    } message: { device in
      Text("\(device.displayName ?? device.deviceID) will be available for another account. Historical data stays with this account.")
    }
  }

  private func claimedDeviceCard(_ device: ClaimedDevice) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(device.displayName ?? device.deviceID).font(.headline)
          Text(device.deviceID).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
      }
      Button("Disconnect Device", role: .destructive) { pendingRemoval = device }
        .font(.caption.bold())
    }
    .foregroundStyle(.white)
    .padding(14)
    .background(.black.opacity(0.18))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private var removalAlertBinding: Binding<Bool> {
    Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
  }

  private func refresh() async {
    isLoading = true
    defer { isLoading = false }
    do {
      async let loadedDevices = session.fetchDevices()
      async let loadedMetrics = session.fetchMetrics()
      devices = try await loadedDevices
      metrics = try await loadedMetrics
      message = nil
    } catch {
      message = "Error: \(error.localizedDescription)"
    }
  }

  private func claim() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let trimmedID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
      let trimmedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
      try await session.claimDevice(deviceID: trimmedID, name: trimmedName.isEmpty ? trimmedID : trimmedName)
      message = "Device claimed."
      devices = try await session.fetchDevices()
    } catch {
      message = "Error: \(error.localizedDescription)"
    }
  }

  private func insertMetric(for device: ClaimedDevice) async {
    guard let heartRateValue = Int(heartRate), let batteryValue = Double(battery) else {
      message = "Error: enter a valid heart rate and battery percentage."
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      try await session.insertMetric(deviceID: device.deviceID, heartRate: heartRateValue, battery: batteryValue)
      message = "Dummy metric inserted."
      metrics = try await session.fetchMetrics()
    } catch {
      message = "Error: \(error.localizedDescription)"
    }
  }

  private func remove(_ device: ClaimedDevice) async {
    pendingRemoval = nil
    isLoading = true
    defer { isLoading = false }
    do {
      try await session.unclaimDevice(deviceID: device.deviceID)
      message = "Device disconnected."
      devices = try await session.fetchDevices()
    } catch {
      message = "Error: \(error.localizedDescription)"
    }
  }

  private func metricSummary(_ metric: MockDeviceMetric) -> String {
    let heartRateText = metric.heartRate.map { "\($0) bpm" } ?? "-- bpm"
    let batteryText = metric.battery.map { "\(Int($0.rounded()))%" } ?? "--%"
    return "\(heartRateText)  \(batteryText)"
  }
}
