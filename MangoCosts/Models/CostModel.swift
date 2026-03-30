import Foundation
import Combine

// MARK: - JSONL Parsing

private struct SessionEntry: Decodable {
    let type: String?
    let timestamp: String?
    let message: SessionMessage?
}

private struct SessionMessage: Decodable {
    let role: String?
    let model: String?
    let usage: SessionUsage?
}

private struct SessionUsage: Decodable {
    let input: Int?
    let output: Int?
    let cost: SessionCost?
}

private struct SessionCost: Decodable {
    let total: Double?
}

// MARK: - Data Model

struct CostData: Equatable {
    let sessionCost: Double
    let inputTokens: Int
    let outputTokens: Int
    let model: String
    let sessionStart: String
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

    // JSONL session file path
    static let sessionFilePath = "/.openclaw/agents/main/sessions/d2afa572-efd6-4ca4-9c6e-42ddb9051b8c.jsonl"

    private var timer: Timer?
    private let sessionURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        sessionURL = home.appendingPathComponent(Self.sessionFilePath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        loadData()
        startPolling()
    }

    func loadData() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                let raw = try String(contentsOf: self.sessionURL, encoding: .utf8)
                let lines = raw.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

                var totalCost: Double = 0
                var totalInput: Int = 0
                var totalOutput: Int = 0
                var model: String = "claude-sonnet-4-6"
                var sessionStart: String = ""
                var foundModel = false

                let decoder = JSONDecoder()

                for line in lines {
                    guard let lineData = line.data(using: .utf8),
                          let entry = try? decoder.decode(SessionEntry.self, from: lineData),
                          entry.type == "message",
                          entry.message?.role == "assistant"
                    else { continue }

                    if let ts = entry.timestamp, sessionStart.isEmpty {
                        sessionStart = ts
                    }

                    if !foundModel, let m = entry.message?.model {
                        model = m
                        foundModel = true
                    }

                    if let usage = entry.message?.usage {
                        totalInput += usage.input ?? 0
                        totalOutput += usage.output ?? 0
                        totalCost += usage.cost?.total ?? 0
                    }
                }

                guard !sessionStart.isEmpty else {
                    throw NSError(domain: "MangoCosts", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "No assistant messages found in session file"])
                }

                let decoded = CostData(
                    sessionCost: totalCost,
                    inputTokens: totalInput,
                    outputTokens: totalOutput,
                    model: model,
                    sessionStart: sessionStart
                )

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
