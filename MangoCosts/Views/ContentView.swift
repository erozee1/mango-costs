import SwiftUI

struct ContentView: View {
    @ObservedObject var costModel: CostModel

    var body: some View {
        ZStack {
            VisualEffectView()
                .ignoresSafeArea()
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 12) {
                headerRow
                if let data = costModel.costData {
                    costRow(data: data)
                    CostProgressBar(cost: data.sessionCost)
                    tokenRow(data: data)
                } else {
                    emptyState
                }
            }
            .padding(16)
        }
        .frame(width: 320, height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Subviews

    private var headerRow: some View {
        HStack(alignment: .center) {
            Text("🥭 Mango Costs")
                .font(.system(.headline, design: .rounded).weight(.semibold))
            Spacer()
            if let updated = costModel.lastUpdated {
                Text(updated, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func costRow(data: CostData) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("$\(String(format: "%.3f", data.sessionCost))")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(ragColor)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: data.sessionCost)

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Label(costModel.sessionDuration, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(data.model)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func tokenRow(data: CostData) -> some View {
        HStack(spacing: 0) {
            TokenStat(label: "Input",  value: data.inputTokens)
            Spacer()
            Divider().frame(height: 28)
            Spacer()
            TokenStat(label: "Output", value: data.outputTokens)
            Spacer()
            Divider().frame(height: 28)
            Spacer()
            TokenStat(label: "Total",  value: data.inputTokens + data.outputTokens)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: costModel.loadError == nil ? "arrow.clockwise" : "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(costModel.loadError == nil ? "Loading…" : "No data found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if costModel.loadError != nil {
                Text("Run: mango-costs update --cost 0.00")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: Helpers

    private var ragColor: Color {
        switch costModel.ragStatus {
        case .green: return Color(hex: "34C759")   // system green
        case .amber: return Color(hex: "FF9500")   // mango orange
        case .red:   return Color(hex: "FF3B30")   // system red
        }
    }
}

// MARK: - TokenStat

struct TokenStat: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(spacing: 2) {
            Text(formatted)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var formatted: String {
        value >= 1_000 ? String(format: "%.1fK", Double(value) / 1_000) : "\(value)"
    }
}

// MARK: - VisualEffectView (NSVisualEffectView bridge)

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Color hex init

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var n: UInt64 = 0
        Scanner(string: h).scanHexInt64(&n)
        let r = Double((n >> 16) & 0xFF) / 255
        let g = Double((n >>  8) & 0xFF) / 255
        let b = Double( n        & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b)
    }
}
