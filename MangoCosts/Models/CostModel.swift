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

struct TodayData: Equatable {
    let cost: Double
    let inputTokens: Int
    let outputTokens: Int
}

// MARK: - CostModel

final class CostModel: ObservableObject {
    @Published var session: SessionData?
    @Published var total: TotalData?
    @Published var lastUpdated: Date?
    @Published var loadError: String?
    @Published var today: TodayData?

    static let notificationCheckpoints: [Double] = [0.10, 0.50, 1.00]

    private let sessionsDir: URL
    private let sessionsJsonURL: URL
    private var sessionTimer: Timer?
    private var totalTimer: Timer?
    private var todayTimer: Timer?

    // Serial queue protects sessionAccum + file handle state across polls
    private let parseQueue = DispatchQueue(label: "com.mangocosts.parse", qos: .utility)
    private var sessionFileURL: URL?
    private var sessionFileHandle: FileHandle?
    private var sessionFileOffset: UInt64 = 0
    private var sessionAccum = SessionAccumulator()

    private struct SessionAccumulator {
        var cost: Double = 0
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheReadTokens: Int = 0
        var cacheWriteTokens: Int = 0
        var lastContextTokens: Int = 0
    }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        sessionsDir = home.appendingPathComponent(".openclaw/agents/main/sessions")
        sessionsJsonURL = sessionsDir.appendingPathComponent("sessions.json")
        loadSessionData()
        loadTotalData()
        loadTodayData()
        startPolling()
    }

    // MARK: - Session loading (sessions.json metadata + JSONL token counts)

    func loadSessionData() {
        parseQueue.async { [weak self] in
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

                // Step 2: incremental JSONL parse — only read bytes added since last poll
                let jsonlURL = URL(fileURLWithPath: sessionFilePath)

                if self.sessionFileURL != jsonlURL {
                    // Session changed — close old handle, reset accumulator, start fresh
                    self.sessionFileHandle?.closeFile()
                    self.sessionFileHandle = FileHandle(forReadingAtPath: jsonlURL.path)
                    self.sessionFileOffset = 0
                    self.sessionAccum = SessionAccumulator()
                    self.sessionFileURL = jsonlURL
                }

                guard let handle = self.sessionFileHandle else {
                    throw NSError(domain: "MangoCosts", code: 3,
                                  userInfo: [NSLocalizedDescriptionKey: "Cannot open session file: \(jsonlURL.lastPathComponent)"])
                }

                handle.seek(toFileOffset: self.sessionFileOffset)
                let newData = handle.readDataToEndOfFile()
                self.sessionFileOffset = handle.offsetInFile

                if !newData.isEmpty, let newText = String(data: newData, encoding: .utf8) {
                    let lines = newText.components(separatedBy: "\n")
                        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    let decoder = JSONDecoder()

                    for line in lines {
                        guard let lineData = line.data(using: .utf8),
                              let entry = try? decoder.decode(JournalEntry.self, from: lineData)
                        else { continue }

                        if entry.type == "message", entry.message?.role == "assistant" {
                            if let usage = entry.message?.usage {
                                self.sessionAccum.inputTokens      += usage.input      ?? 0
                                self.sessionAccum.outputTokens     += usage.output     ?? 0
                                self.sessionAccum.cacheReadTokens  += usage.cacheRead  ?? 0
                                self.sessionAccum.cacheWriteTokens += usage.cacheWrite ?? 0
                                self.sessionAccum.cost             += usage.cost?.total ?? 0
                                self.sessionAccum.lastContextTokens = (usage.input ?? 0) + (usage.cacheRead ?? 0) + (usage.cacheWrite ?? 0)
                            }
                        }
                    }
                }

                let sessionData = SessionData(
                    cost: self.sessionAccum.cost,
                    inputTokens: self.sessionAccum.inputTokens,
                    outputTokens: self.sessionAccum.outputTokens,
                    cacheReadTokens: self.sessionAccum.cacheReadTokens,
                    totalTokens: self.sessionAccum.lastContextTokens,
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
                let msg = error.localizedDescription
                let debug = "[\(Date())] loadSessionData error: \(msg)\nsessionsJson: \(self.sessionsJsonURL.path)\n"
                try? debug.appendLine(to: URL(fileURLWithPath: "/tmp/mango-costs-debug.txt"))
                DispatchQueue.main.async {
                    self.loadError = msg
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

    // MARK: - Today loading (sessions started today)

    func loadTodayData() {
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
            let decoder = JSONDecoder()
            let isoFmt = ISO8601DateFormatter()
            isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            for fileURL in allFiles {
                guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
                let lines = raw.components(separatedBy: "\n")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

                var isToday = false
                var checkedSession = false

                for line in lines {
                    guard let lineData = line.data(using: .utf8),
                          let entry = try? decoder.decode(JournalEntry.self, from: lineData)
                    else { continue }

                    if !checkedSession, entry.type == "session", let ts = entry.timestamp {
                        if let date = isoFmt.date(from: ts) {
                            isToday = Calendar.current.isDateInToday(date)
                        }
                        checkedSession = true
                        if !isToday { break }
                    }

                    if isToday, entry.type == "message", entry.message?.role == "assistant" {
                        if let usage = entry.message?.usage {
                            totalInput  += usage.input  ?? 0
                            totalOutput += usage.output ?? 0
                            totalCost   += usage.cost?.total ?? 0
                        }
                    }
                }
            }

            let todayData = TodayData(cost: totalCost, inputTokens: totalInput, outputTokens: totalOutput)
            DispatchQueue.main.async { self.today = todayData }
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

        todayTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.loadTodayData()
        }
        RunLoop.main.add(todayTimer!, forMode: .common)
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

// MARK: - Debug helpers

private extension String {
    func appendLine(to url: URL) throws {
        let line = self.hasSuffix("\n") ? self : self + "\n"
        if let handle = FileHandle(forWritingAtPath: url.path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            handle.closeFile()
        } else {
            try line.write(to: url, atomically: false, encoding: .utf8)
        }
    }
}
