import SwiftUI

/// Pastel RAG horizontal progress bar.
/// Scale: $0.00 → $2.00 = full width.
/// Threshold tick marks shown at $0.10 and $0.50.
struct CostProgressBar: View {
    let cost: Double

    // Pastel RAG palette
    private static let softGreen = Color(red: 0.659, green: 0.835, blue: 0.635)  // #A8D5A2
    private static let softAmber = Color(red: 1.000, green: 0.800, blue: 0.475)  // #FFCC79
    private static let softRed   = Color(red: 1.000, green: 0.620, blue: 0.620)  // #FF9E9E

    private static let maxCost: Double = 2.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 8)

                // Fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(barColor)
                    .frame(width: max(0, w * fillFraction), height: 8)
                    .animation(.easeInOut(duration: 0.4), value: fillFraction)

                // Threshold ticks
                tick(at: CostModel.greenThreshold, totalWidth: w)
                tick(at: CostModel.amberThreshold, totalWidth: w)
            }
        }
        .frame(height: 8)
    }

    @ViewBuilder
    private func tick(at threshold: Double, totalWidth: CGFloat) -> some View {
        let fraction = CGFloat(min(threshold / Self.maxCost, 1.0))
        Rectangle()
            .fill(Color.primary.opacity(0.25))
            .frame(width: 1.5, height: 13)
            .offset(x: totalWidth * fraction - 0.75, y: -2.5)
    }

    private var fillFraction: CGFloat {
        CGFloat(min(cost / Self.maxCost, 1.0))
    }

    private var barColor: Color {
        if cost < CostModel.greenThreshold { return Self.softGreen }
        if cost < CostModel.amberThreshold { return Self.softAmber }
        return Self.softRed
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 20) {
        CostProgressBar(cost: 0.03)
        CostProgressBar(cost: 0.25)
        CostProgressBar(cost: 0.80)
    }
    .padding()
    .frame(width: 300)
}
#endif
