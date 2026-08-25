// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Graham Barber

import SwiftUI

struct SettingsDiffSheet: View {
  let comparison: SettingsComparison
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Compare: \(comparison.beforeLabel) → \(comparison.afterLabel)")
        .font(.system(size: 13, weight: .semibold))
        .padding(.bottom, 13)

      if comparison.differences.isEmpty {
        Text("No differences between these two.")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .padding(.bottom, 16)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            ForEach(groupedBySection, id: \.section) { group in
              VStack(alignment: .leading, spacing: 6) {
                Text(group.section)
                  .font(.system(size: 12, weight: .semibold))
                  .foregroundStyle(.secondary)
                ForEach(group.differences) { difference in
                  VStack(alignment: .leading, spacing: 2) {
                    Text(difference.fieldLabel)
                      .font(.system(size: 12, weight: .medium))
                    HStack(spacing: 6) {
                      Text(difference.before)
                        .foregroundStyle(.secondary)
                        .strikethrough()
                      Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                      Text(difference.after)
                    }
                    .font(.system(size: 12).monospaced())
                  }
                }
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 320)
        .padding(.bottom, 16)
        Text("Values shown are the stored setting values, not display labels. Passwords and secrets are never compared or shown.")
          .font(.caption).foregroundStyle(.secondary)
          .padding(.bottom, 16)
      }

      HStack {
        Spacer()
        Button("Close") { dismiss() }
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("settings-diff.close")
      }
    }
    .padding(EdgeInsets(top: 18, leading: 20, bottom: 16, trailing: 20))
    .frame(width: 480, alignment: .leading)
  }

  private var groupedBySection: [(section: String, differences: [SettingsDifference])] {
    var order: [String] = []
    var bySection: [String: [SettingsDifference]] = [:]
    for difference in comparison.differences {
      if bySection[difference.sectionLabel] == nil {
        order.append(difference.sectionLabel)
      }
      bySection[difference.sectionLabel, default: []].append(difference)
    }
    return order.map { ($0, bySection[$0] ?? []) }
  }
}
