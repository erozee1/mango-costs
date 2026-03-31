import Foundation
import Combine

// MARK: - sessions.json Parsing

private struct LiveSession: Decodable {
    let sessionId: String?
    let startedAt: Double?          // unix ms
    let model: String?
    let contextTokens: Int?
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
    let cacheRead: Int?
    let cacheWrite: Int?
    let cost: JournalCost?

    enum CodingKeys: String, CodingKey {
        case input, output, cost
        case cacheRead
        case cache_read
        case cacheWrite
        case cache_write
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        input     = try c.decodeIfPresent(Int.self, forKey: .input)
        output    = try c.decodeIfPresent(Int.self, forKey: .output)
        cost      = try c.decodeIfPresent(JournalCost.self, forKey: .cost)
        cacheRead  = try c.decodeIfPresent(Int.self, forKey: .cacheRead)
                  ?? c.decodeIfPresent(Int.self, forKey: .cache_read)
        cacheWrite = try c.decodeIfPresent(Int.self, forKey: .cacheWrite)
                  ?? c.decodeIfPresent(Int.self, forKey: .cache_write)
    }
}

private struct JournalCost: Decodable {
    let total: Double?
}

// MARK: - Data Models

struct SessionData: Equatable {
    let cost: Double
    let inputTokens: Int        // fresh input only (not cache)
    let outputTokens: Int
    let cacheReadTokens: Int    // cache read tokens
    let totalTokens: Int        // input + output + cacheRead + cacheWrite
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

    // MARK: - Session loading (sessions.json metadata + JSONL token counts)

    func loadSessionData() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                // Step 1: read sessions.json for metadata
                let raw = try Data(contentsOf: self.sessionsJsonURL)
                let dict = try JSONDecoder().decode([String: LiveSession].self, from: raw)

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

                let model = live.model ?? "claude-sonnet-4-6"
                let contextTokens = live.contextTokens ?? 200_000

                guard let sessionFilePath = live.sessionFile else {
                    throw NSError(domain: "MangoCosts", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "No sessionFile in sessions.json"])
                }

                // Step 2: parse JSONL for accurate token/cost data
                let jsonlURL = URL(fileURLWithPath: sessionFilePath)
                let jsonlRaw = try String(contentsOf: jsonlURL, encoding: .utf8)
                let lines = jsonlRaw.components(separatedBy: "\n")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

                var totalCost: Double = 0
                var inputTokens: Int = 0
                var outputTokens: Int = 0
                var cacheReadTokens: Int = 0
                var cacheWriteTokens: Int = 0
                let decoder = JSONDecoder()

                for line in lines {
                    guard let lineData = line.data(using: .utf8),
                          let entry = try? decoder.decode(JournalEntry.self, from: lineData)
                    else { continue }

                    if entry.type == "message", entry.message?.role == "assistant" {
                        if let usage = entry.message?.usage {
                            inputTokens     += usage.input      ?? 0
                            outputTokens    += usage.output     ?? 0
                            cacheReadTokens += usage.cacheRead  ?? 0
                            cacheWriteTokens += usage.cacheWrite ?? 0
                            totalCost       += usage.cost?.total ?? 0
                        }
                    }
                }

                let totalTokens = inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens

                let sessionData = SessionData(
                    cost: totalCost,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    cacheReadTokens: cacheReadTokens,
                    totalTokens: totalTokens,
                    model: model,
                    startedAt: startedAt,
                    contextTokens: contextTokens
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
                            totalInput  += usage.input  ?? 0
                            totalOutput += usage.output ?? 0
                            totalCost   += usage.cost?.total ?? 0
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
