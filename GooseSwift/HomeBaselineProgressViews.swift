import SwiftUI

// MARK: - HomeBaselineProgressCard
//
// Post-onboarding warm-up progress. The strap needs hours-to-days of captured
// packets before each score family is computable (HRV/RHR baselines seed after
// 4 nights and mature at 7 — see Rust/core/src/baselines.rs). Until every
// family is score-ready this card explains what is still collecting instead of
// leaving empty dials unexplained; it disappears once all families are ready.

struct HomeBaselineProgressCard: View {
  let progress: BaselineProgressModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: "hourglass.circle.fill")
          .font(.title3)
          .foregroundStyle(.blue)
        Text("Building your baseline")
          .font(.headline)
        Spacer()
        if progress.hasReport {
          Text("\(progress.readyFamilies) of \(progress.totalFamilies) ready")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
      }

      if progress.hasReport {
        ProgressView(value: progress.fractionReady)
          .tint(.blue)

        VStack(alignment: .leading, spacing: 8) {
          ForEach(progress.families) { family in
            HStack(spacing: 8) {
              Image(systemName: family.ready ? "checkmark.circle.fill" : "hourglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(family.ready ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .frame(width: 16)
              Text(family.title)
                .font(.subheadline)
              Spacer()
              if family.ready {
                Text("Ready")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.green)
              } else {
                Text(verbatim: "\(family.readyInputs)/\(family.requiredInputs)")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      } else {
        HStack(spacing: 10) {
          ProgressView()
          Text("Analysing collected data…")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      Text("Wear your strap day and night — most metrics appear after your first night. HRV and resting heart rate baselines mature over 4–7 nights.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface(tint: .blue)
  }
}
