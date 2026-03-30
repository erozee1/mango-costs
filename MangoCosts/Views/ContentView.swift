import SwiftUI

// MARK: - Constants

private let kMaxContextTokens = 200_000

// MARK: - ContentView

struct ContentView: View {
    @ObservedObject var costModel: CostModel
    var onClose: (() -> Void)?

    var body: some View {
        ZStack {
            VisualEffectView()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBand

                Divider()
                    .opacity(0.4)

                if let data = costModel.costData {
                    bodyContent(data: data)
                } else {
                    emptyState
                }
            }
        }
        .frame(width: 320, height: 236)
        .ignoresSafeArea()
    }

    // MARK: Header band — custom chrome, no system traffic lights

    private var headerBand: some View {
        HStack(alignment: .center, spacing: 8) {
            // Close button (red circle)
            Button(action: { onClose?() }) {
                Circle()
                    .fill(Color(hex: "FF5F57"))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.5))
                    )
            }
            .buttonStyle(.plain)
            .padding(.leading, 12)

            // Big mango emoji
            Text("🥭")
                .font(.system(size: 22))

            Text("Mango Costs")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))

            Spacer()

            if let data = costModel.costData {
                Text(shortModelName(data.model))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.trailing, 12)
            }
        }
        .frame(height: 40)
    }

    // MARK: Body

    @ViewBuilder
    private func bodyContent(data: CostData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cost — centre-stage
            costSection(data: data)
                .padding(.top, 10)

            // Token stats
            tokenRow(data: data)
                .padding(.top, 8)

            // Context window bar
            ContextWindowBar(totalTokens: data.inputTokens + data.outputTokens)
                .padding(.top, 12)

            // Session start — muted bottom line
            sessionLine
                .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func costSection(data: CostData) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(ragColor)
                .frame(width: 10, height: 10)

            Text("$\(String(format: "%.3f", data.sessionCost))")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: data.sessionCost)

            Spacer()
        }
    }

    private func tokenRow(data: CostData) -> some View {
        HStack(spacing: 14) {
            TokenStat(direction: .up,   value: data.inputTokens,  label: "in")
            TokenStat(direction: .down, value: data.outputTokens, label: "out")
            Spacer()
        }
    }

    private var sessionLine: some View {
        Text("Session: \(costModel.sessionDuration)")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
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
        .padding(.vertical, 20)
    }

    // MARK: Helpers

    private var ragColor: Color {
        switch costModel.ragStatus {
        case .green: return Color(hex: "34C759")
        case .amber: return Color(hex: "FF9500")
        case .red:   return Color(hex: "FF3B30")
        }
    }

    /// Shorten e.g. "claude-sonnet-4-6-20251022" → "sonnet-4-6"
    private func shortModelName(_ full: String) -> String {
        let s = full.lowercased()
        for prefix in ["claude-", "anthropic/claude-"] {
            if s.hasPrefix(prefix) {
                return String(full.dropFirst(prefix.count))
            }
        }
        return full
    }
}

// MARK: - TokenStat

enum TokenDirection { case up, down }

struct TokenStat: View {
    let direction: TokenDirection
    let value: Int
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: direction == .up ? "arrow.up" : "arrow.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(direction == .up ? Color(hex: "FF9500") : Color.secondary)

            Text(formatted)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var formatted: String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000     { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }
}

// MARK: - ContextWindowBar

struct ContextWindowBar: View {
    let totalTokens: Int

    private static let softGreen = Color(red: 0.659, green: 0.835, blue: 0.635)  // #A8D5A2
    private static let softAmber = Color(red: 1.000, green: 0.800, blue: 0.475)  // #FFCC79
    private static let softRed   = Color(red: 1.000, green: 0.620, blue: 0.620)  // #FF9E9E

    private var fraction: Double {
        min(Double(totalTokens) / Double(kMaxContextTokens), 1.0)
    }

    private var barColor: Color {
        if fraction < 0.60 { return Self.softGreen }
        if fraction < 0.85 { return Self.softAmber }
        return Self.softRed
    }

    private var percentText: String { "\(Int(fraction * 100))%" }

    private var countText: String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        let used = fmt.string(from: NSNumber(value: totalTokens)) ?? "\(totalTokens)"
        let max  = fmt.string(from: NSNumber(value: kMaxContextTokens)) ?? "\(kMaxContextTokens)"
        return "\(used) / \(max) tokens"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Label row
            HStack {
                Text("Context Window")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(percentText)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            // Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 7)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor)
                        .frame(width: max(0, geo.size.width * CGFloat(fraction)), height: 7)
                        .animation(.easeInOut(duration: 0.4), value: fraction)
                }
            }
            .frame(height: 7)

            // Exact count
            Text(countText)
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
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
