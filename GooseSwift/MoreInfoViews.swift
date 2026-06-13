import Foundation
import SwiftUI

struct MorePrivacyView: View {
  @ObservedObject var store: MoreDataStore
  @State private var showingDeleteConfirm = false
  @State private var dbURL: URL? = {
    let path = HealthDataStore.defaultDatabasePath()
    return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
  }()

  var body: some View {
    List {
      Section("Local Data") {
        MoreInfoRow(title: "Database", value: store.databasePath, systemImage: "externaldrive", status: store.databaseExists ? .ready : .unavailable)
        MoreInfoRow(title: "Raw Bundle", value: store.rawBundlePath, systemImage: "folder", status: store.rawBundlePath == "No bundle" ? .pending : .ready)
        MoreInfoRow(title: "Privacy Lint", value: store.privacyLintStatus, systemImage: "hand.raised", status: .pending)
        MoreInfoRow(title: "Sanitized Privacy", value: store.sanitizedPrivacyStatus, systemImage: "sparkles.rectangle.stack", status: .pending)
      }

      Section("Links") {
        Button {
          store.validateExportArtifacts()
        } label: {
          Label("Validate Export And Lint", systemImage: "checkmark.seal")
        }
        .disabled(store.rawBundlePath == "No bundle")

        if let url = dbURL {
          ShareLink(item: url) {
            Label("Export Local Database", systemImage: "square.and.arrow.up")
          }
        } else {
          MoreInfoRow(title: "Data Export", value: "Database not found", systemImage: "square.and.arrow.up", status: .unavailable)
        }

        Button(role: .destructive) {
          showingDeleteConfirm = true
        } label: {
          Label("Delete All Local Data", systemImage: "trash")
        }
        .disabled(!store.databaseExists)
      }
    }
    .gooseListBackground()
    .navigationTitle("Privacy")
    .confirmationDialog(
      String(localized: "Delete all local data?"),
      isPresented: $showingDeleteConfirm,
      titleVisibility: .visible
    ) {
      Button(String(localized: "Delete"), role: .destructive) {
        store.deleteLocalDatabase()
        dbURL = nil
      }
      Button(String(localized: "Cancel"), role: .cancel) {}
    } message: {
      Text(String(localized: "This action removes the local SQLite database and cannot be undone. Data on the server is not affected."))
    }
  }
}

struct MoreSupportView: View {
  @ObservedObject var store: MoreDataStore

  var body: some View {
    List {
      Section("Paths") {
        MoreInfoRow(title: "Support Bundle", value: store.supportBundlePath, systemImage: "folder.badge.gearshape", status: .pending)
        MoreInfoRow(title: "Log Export", value: store.logExportStatus, systemImage: "doc.text", status: .pending)
        MoreInfoRow(title: "Local File", value: store.localExportStatus, systemImage: "doc", status: store.localExportURL == nil ? .pending : .ready)
        MoreInfoRow(title: "Latest Raw Bundle", value: store.rawBundlePath, systemImage: "shippingbox", status: store.rawBundlePath == "No bundle" ? .pending : .ready)
        MoreInfoRow(title: "Latest Zip", value: store.rawZipPath, systemImage: "doc.zipper", status: store.rawZipPath == "No zip" ? .pending : .ready)
      }

      Section("Actions") {
        Button {
          store.saveLocalDataBundle()
        } label: {
          Label("Save Local Data File", systemImage: "externaldrive.badge.plus")
        }
        .disabled(store.localExportInProgress)

        if store.localExportInProgress {
          ProgressView("Saving local data file")
        }

        if let localExportURL = store.localExportURL {
          ShareLink(item: localExportURL) {
            Label("AirDrop Local Data File", systemImage: "square.and.arrow.up")
          }
        }

        if let localExportManifestURL = store.localExportManifestURL {
          ShareLink(item: localExportManifestURL) {
            Label("AirDrop Export Manifest", systemImage: "list.bullet.rectangle")
          }
        }

        MoreActionRow(title: "Create Support Bundle", detail: "Pending bundle composer bridge", systemImage: "lifepreserver", status: .unavailable, disabled: true) {}
      }
    }
    .gooseListBackground()
    .navigationTitle("Support")
  }
}

struct MoreAboutView: View {
  @Environment(GooseAppModel.self) private var model
  @ObservedObject var store: MoreDataStore

  var body: some View {
    List {
      Section("Versions") {
        MoreInfoRow(title: "App Version", value: appVersion, systemImage: "app", status: .ready)
        MoreInfoRow(title: "Rust Core", value: store.coreVersionStatus, systemImage: "shippingbox", status: store.coreVersionStatus.hasPrefix("Rust core") ? .ready : .pending)
        MoreInfoRow(title: "Schema", value: store.schemaVersion, systemImage: "number", status: store.schemaVersion == "Unknown" ? .pending : .ready)
      }

      Section("Runtime") {
        MoreInfoRow(title: "Device", value: model.ble.activeDeviceName, systemImage: "sensor.tag.radiowaves.forward", status: model.ble.connectionState == "ready" ? .ready : .pending)
        MoreInfoRow(title: "Hello", value: model.helloSummary, systemImage: "hand.wave", status: model.helloSummary.hasPrefix("GET_HELLO") ? .ready : .pending)
      }

      Section("License") {
        MoreInfoRow(title: "License", value: "GNU GPL v3", systemImage: "doc.text", status: .ready)
        MoreInfoRow(title: "Copyright", value: "© 2026 tigercraft4", systemImage: "c.circle", status: .ready)
        MoreInfoRow(title: "Source", value: "github.com/tigercraft4/goose", systemImage: "chevron.left.forwardslash.chevron.right", status: .ready)
      }

    }
    .gooseListBackground()
    .navigationTitle("About")
    .onAppear {
      store.refreshBridgeStatus(model: model)
    }
  }

  private var appVersion: String {
    let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    return "\(short) (\(build))"
  }
}

struct MoreInfoRow: View {
  let title: String
  let value: String
  let systemImage: String
  let status: MoreStatusKind

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: systemImage)
        .foregroundStyle(status.tint)
        .frame(width: 24, height: 24)

      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          Text(title)
            .font(.subheadline.weight(.semibold))
          Spacer(minLength: 8)
          MoreStatusBadge(status: status)
        }
        Text(value.isEmpty ? "Unavailable" : value)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .textSelection(.enabled)
      }
    }
    .padding(.vertical, 3)
  }
}

struct MoreActionRow: View {
  let title: String
  let detail: String
  let systemImage: String
  let status: MoreStatusKind
  let disabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: systemImage)
          .foregroundStyle(status.tint)
          .frame(width: 24, height: 24)

        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline) {
            Text(title)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.primary)
            Spacer(minLength: 8)
            MoreStatusBadge(status: status)
          }
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
      .padding(.vertical, 3)
    }
    .buttonStyle(.plain)
    .disabled(disabled)
  }
}

struct MoreCommandGroupRow: View {
  let group: MoreCommandGroup

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: group.status == .blocked ? "lock.shield" : "terminal")
        .foregroundStyle(group.status.tint)
        .frame(width: 24, height: 24)

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(group.title)
            .font(.subheadline.weight(.semibold))
          Spacer(minLength: 8)
          MoreStatusBadge(status: group.status)
        }
        Text(group.commands.joined(separator: ", "))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .padding(.vertical, 3)
  }
}

extension Date {
  func moreISO8601String() -> String {
    ISO8601DateFormatter().string(from: self)
  }
}
