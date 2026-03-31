import Foundation
import Combine

// MARK: - sessions.json Parsing

private struct SessionsFile: Decodable {
    let sessions: [String: LiveSession]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        sessions = try container.decode([String: LiveSession].self)
    }
}

private struct LiveSession: Decodable {
    let sessionId: String?
    let startedAt: Double?          // unix ms
    let model: String?
    let contextTokens: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheRead: Int?
    let cacheWrite: Int?
    let estimatedCostUsd: Double?
    let totalTokens: Int?
    let sessionFile: String?
}

// MARK: - JSONL Parsing

private struct JournalEntry: Decodable {
    let type: String?
    let timestamp: String?
    let message: JournalMessage?
}

private struct JournalMessage: Decodable {
    let role: String?
    let usage: JournalUsage?
}

private struct JournalUsage: Decodable {
    let input: Int?
    let output: Int?
    let cost: JournalCost?
}

private struct JournalCost: Decodable {
    let total: Double?
}

// MARK: - Data Models

struct SessionData: Equatable {
    let cost: Double
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
    let model: String
    let startedAt: Date
    let contextTokens: Int
}

struct TotalData: Equatable {
    let cost: Double
    let inputTokens: Int
    let outputTokens: Int
    let oldestSessionDate: Date?
}

// MARK: - CostModel

final class CostModel: ObservableObject {
    @Published var session: SessionData?
    @Published var total: TotalData?
    @Published var lastUpdated: Date?
    @Published var loadError: String?

    static let notificationCheckpoints: [Double] = [0.10, 0.50, 1.00]

    private let sessionsDir: URL
    private let sessionsJsonURL: URL
    private var sessionTimer: Timer?
    private var totalTimer: Timer?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        sessionsDir = home.appendingPathComponent(".openclaw/agents/main/sessions")
        sessionsJsonURL = sessionsDir.appendingPathComponent("sessions.json")
        loadSessionData()
        loadTotalData()
        startPolling()
    }

    // MARK: - Session loading (from sessions.json)

    func loadSessionData() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                let raw = try Data(contentsOf: self.sessionsJsonURL)
                let decoder = JSONDecoder()
                let dict = try decoder.decode([String: LiveSession].self, from: raw)

                guard let live = dict["agent:main:main"] else {
                    throw NSError(domain: "MangoCosts", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Key 'agent:main:main' not found in sessions.json"])
                }

                let startedAt: Date
                if let ms = live.startedAt {
                    startedAt = Date(timeIntervalSince1970: ms / 1000.0)
                } else {
                    startedAt = Date()
                }

                let sessionData = SessionData(
                    cost: live.estimatedCostUsd ?? 0,
                    inputTokens: live.inputTokens ?? 0,
                    outputTokens: live.outputTokens ?? 0,
                    totalTokens: live.totalTokens ?? 0,
                    model: live.model ?? "claude-sonnet-4-6",
                    startedAt: startedAt,
                    contextTokens: live.contextTokens ?? 200_000
                )

                DispatchQueue.main.async {
                    let prev = self.session?.cost
                    self.session = sessionData
                    self.lastUpdated = Date()
                    self.loadError = nil
                    if let prev {
                        NotificationManager.shared.checkThresholds(oldCost: prev, newCost: sessionData.cost)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.loadError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Total loading (scan all JSONL files)

    func loadTotalData() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }

            var allFiles: [URL] = []
            let fm = FileManager.default

            if let contents = try? fm.contentsOfDirectory(at: self.sessionsDir, includingPropertiesForKeys: nil) {
                for url in contents {
                    let name = url.lastPathComponent
                    if name.hasSuffix(".jsonl") || name.contains(".jsonl.reset.") {
                        allFiles.append(url)
                    }
                }
            }

            var totalCost: Double = 0
            var totalInput: Int = 0
            var totalOutput: Int = 0
            var oldestDate: Date? = nil
            let decoder = JSONDecoder()

            for fileURL in allFiles {
                guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                let lines = raw.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                var foundSession = false

                for line in lines {
                    guard let lineData = line.data(using: .utf8),
                          let entry = try? decoder.decode(JournalEntry.self, from: lineData)
                    else { continue }

                    if !foundSession, entry.type == "session", let ts = entry.timestamp {
                        let fmt = ISO8601DateFormatter()
                        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        if let date = fmt.date(from: ts) {
                            if oldestDate == nil || date < oldestDate! {
                                oldestDate = date
                            }
                        }
                        foundSession = true
                    }

                    if entry.type == "message", entry.message?.role == "assistant" {
                        if let usage = entry.message?.usage {
                            totalInput += usage.input ?? 0
                            totalOutput += usage.output ?? 0
                            totalCost += usage.cost?.total ?? 0
                        }
                    }
                }
            }

            let totalData = TotalData(
                cost: totalCost,
                inputTokens: totalInput,
                outputTokens: totalOutput,
                oldestSessionDate: oldestDate
            )

            DispatchQueue.main.async {
                self.total = totalData
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.loadSessionData()
        }
        RunLoop.main.add(sessionTimer!, forMode: .common)

        totalTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.loadTotalData()
        }
        RunLoop.main.add(totalTimer!, forMode: .common)
    }

    // MARK: - Computed helpers

    var sessionDuration: String {
        guard let startDate = session?.startedAt else { return "—" }
        let elapsed = Int(Date().timeIntervalSince(startDate))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
