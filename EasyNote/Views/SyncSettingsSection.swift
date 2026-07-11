import SwiftUI

struct SyncSettingsSection: View {
    let report: CloudKitPreflightReport

    var body: some View {
        Section {
            HStack {
                Label("同步状态", systemImage: statusIcon)
                    .foregroundColor(statusColor)

                Spacer()

                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(report.summary)
                .font(.caption)
                .foregroundColor(.secondary)

            Text("容器：\(report.containerIdentifier)")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(report.checks) { check in
                VStack(alignment: .leading, spacing: 4) {
                    Label(check.title, systemImage: iconName(for: check.severity))
                        .foregroundColor(color(for: check.severity))

                    Text(check.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if check.severity != .passed {
                        Text(check.remediation)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("iCloud 同步预检")
        } footer: {
            Text("当前仅展示真实同步启用前置条件，不会开启 CloudKit 或改变本地 SwiftData 存储。")
        }
    }

    private var statusText: String {
        switch report.overallSeverity {
        case .passed:
            return "通过"
        case .warning:
            return "需注意"
        case .blocked:
            return "未就绪"
        }
    }

    private var statusIcon: String {
        iconName(for: report.overallSeverity)
    }

    private var statusColor: Color {
        color(for: report.overallSeverity)
    }

    private func iconName(for severity: CloudKitPreflightSeverity) -> String {
        switch severity {
        case .passed:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .blocked:
            return "xmark.octagon.fill"
        }
    }

    private func color(for severity: CloudKitPreflightSeverity) -> Color {
        switch severity {
        case .passed:
            return .green
        case .warning:
            return .orange
        case .blocked:
            return .red
        }
    }
}
