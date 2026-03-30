import Foundation
import Combine

// MARK: - Data Model

struct CostData: Codable, Equatable {
    let sessionCost: Double
    let inputTokens: Int
    let outputTokens: Int
    let model: String
    let sessionStart: String

    enum CodingKeys: String, CodingKey {
        case sessionCost   = "session_cost"
        case inputTokens   = "input_tokens"
        case outputTokens  = "output_tokens"
        case model
        case sessionStart  = "session_start"
    }
}

// MARK: - RAG Status

enum RAGStatus {
    case green, amber, red
}

// MARK: - CostModel

final class CostModel: ObservableObject {
    @Published var costData: CostData?
    @Published var lastUpdated: Date?
    @Published var loadError: String?

    // RAG thresholds (configurable constants)
    static let greenThreshold: Double = 0.10
    static let amberThreshold: Double = 0.50

    // Notification checkpoints
    static let notificationCheckpoints: [Double] = [0.10, 0.50, 1.00]

    private var timer: Timer?
    private let costsURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        costsURL = home.appendingPathComponent(".openclaw/costs.json")
        loadData()
        startPolling()
    }

    func loadData() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                let data = try Data(contentsOf: self.costsURL)
                let decoded = try JSONDecoder().decode(CostData.self, from: data)
                DispatchQueue.main.async {
                    let prev = self.costData?.sessionCost
                    self.costData = decoded
                    self.lastUpdated = Date()
                    self.loadError = nil
                    if let prev {
                        NotificationManager.shared.checkThresholds(oldCost: prev, newCost: decoded.sessionCost)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.loadError = error.localizedDescription
                }
            }
        }
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.loadData()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    // MARK: Computed helpers

    var ragStatus: RAGStatus {
        guard let cost = costData?.sessionCost else { return .green }
        if cost < Self.greenThreshold { return .green }
        if cost < Self.amberThreshold { return .amber }
        return .red
    }

    var sessionDuration: String {
        guard let startStr = costData?.sessionStart,
              let startDate = ISO8601DateFormatter().date(from: startStr) else { return "—" }
        let elapsed = Int(Date().timeIntervalSince(startDate))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
