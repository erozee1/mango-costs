import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    @ObservedObject var costModel: CostModel

    @State private var selectedTab: Tab = .session

    enum Tab { case session, total }

    var body: some View {
        ZStack {
            VisualEffectView()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                tabPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                Group {
                    switch selectedTab {
                    case .session:
                        if let data = costModel.session {
                            sessionContent(data: data)
                        } else {
                            errorState
                        }
                    case .total:
                        if let data = costModel.total {
                            totalContent(data: data)
                        } else {
                            loadingState
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.top, 28)
        }
        .ignoresSafeArea()
    }

    // MARK: Tab Picker

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            Text("Session").tag(Tab.session)
            Text("Total").tag(Tab.total)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: Session Tab

    @ViewBuilder
    private func sessionContent(data: SessionData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            costNumberSection(cost: data.cost)
                .padding(.top, 8)

            HStack(spacing: 14) {
                TokenStat(direction: .up,    value: data.inputTokens,     label: "in")
                TokenStat(direction: .down,  value: data.outputTokens,    label: "out")
                if data.cacheReadTokens > 0 {
                    TokenStat(direction: .cache, value: data.cacheReadTokens, label: "cache")
                }
                Spacer()
            }
            .padding(.top, 6)

            ContextWindowBar(totalTokens: data.totalTokens, maxTokens: data.contextTokens)
                .padding(.top, 10)

            Text("Session: \(costModel.sessionDuration)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
        .padding(.horizontal, 16)
    }

    // MARK: Total Tab

    @ViewBuilder
    private func totalContent(data: TotalData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            costNumberSection(cost: data.cost)
                .padding(.top, 8)

            tokenRow(input: data.inputTokens, output: data.outputTokens)
                .padding(.top, 6)

            if let oldest = data.oldestSessionDate {
                Text("Since \(oldest, format: .dateTime.month(.abbreviated).day())")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Shared sub-views

    private func costNumberSection(cost: Double) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("$\(String(format: "%.3f", cost))")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: cost)

            Spacer()
        }
    }

    private func tokenRow(input: Int, output: Int) -> some View {
        HStack(spacing: 14) {
            TokenStat(direction: .up,   value: input,  label: "in")
            TokenStat(direction: .down, value: output, label: "out")
            Spacer()
        }
    }

    // MARK: Error / loading states

    private var errorState: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(costModel.loadError ?? "No active session")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Button("Retry") {
                costModel.loadSessionData()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.blue)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
    }

    private var loadingState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.clockwise")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Loading…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

}

// MARK: - TokenStat

enum TokenDirection { case up, down, cache }

struct TokenStat: View {
    let direction: TokenDirection
    let value: Int
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: direction == .up ? "arrow.up" : direction == .cache ? "arrow.clockwise" : "arrow.down")
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
    let maxTokens: Int

    private static let softGreen = Color(red: 0.659, green: 0.835, blue: 0.635)
    private static let softAmber = Color(red: 1.000, green: 0.800, blue: 0.475)
    private static let softRed   = Color(red: 1.000, green: 0.620, blue: 0.620)

    private var fraction: Double {
        guard maxTokens > 0 else { return 0 }
        return min(Double(totalTokens) / Double(maxTokens), 1.0)
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
        let max  = fmt.string(from: NSNumber(value: maxTokens)) ?? "\(maxTokens)"
        return "\(used) / \(max) tokens"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
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

            Text(countText)
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - VisualEffectView

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
