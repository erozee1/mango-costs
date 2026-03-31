import SwiftUI

/// Compact summary shown in a right-click context menu popover (future use).
/// Currently the menu bar icon directly toggles the floating panel via AppDelegate.
/// This view is reserved for an optional popover extension.
struct MenuBarView: View {
    @ObservedObject var costModel: CostModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("🥭 Mango Costs")
                    .font(.headline)
                Spacer()
            }

            Divider()

            if let data = costModel.session {
                HStack {
                    Text("Cost")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("$\(String(format: "%.4f", data.cost))")
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                HStack {
                    Text("Model")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(data.model)
                        .font(.caption)
                        .lineLimit(1)
                }
                HStack {
                    Text("Duration")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(costModel.sessionDuration)
                        .monospacedDigit()
                }
            } else {
                Text("No data — waiting for session")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(12)
        .frame(width: 260)
    }
}
