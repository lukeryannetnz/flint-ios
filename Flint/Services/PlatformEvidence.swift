import Foundation
import CryptoKit
import MetricKit

/// No document strings or arbitrary dictionaries cross the persistence boundary.
struct PlatformReport: Codable {
    enum Kind: String, Codable { case metrics, crash, hang, cpu, diskWrite }
    struct Frame: Codable {
        let binaryUUID: UUID?
        let address: UInt64?
        let offset: UInt64?
        let samples: UInt64?
        var depth: Int = 0
        var threadIndex: Int = 0
        var threadAttributed: Bool = false
    }
    let schemaVersion: Int
    let kind: Kind
    let windowStart: Date
    let windowEnd: Date
    let applicationVersion: String?
    let build: String?
    let multipleVersions: Bool
    let values: [String: Double]
    let frames: [Frame]
    let truncated: Bool
    // No originating launch/operation is guessed from receipt time.
    let correlation: String

    static func identity(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.count <= 64,
              value.allSatisfy({ "0123456789.-".contains($0) }) else { return nil }
        return value
    }

    var isSafe: Bool {
        let keys: Set<String> = ["cpuSeconds", "peakMemoryBytes", "diskWriteBytes", "foregroundSeconds",
                                 "durationSeconds", "exceptionType", "exceptionCode", "signal"]
        return schemaVersion == 1 && correlation == "unknown" && frames.count <= 1024
            && frames.allSatisfy { (0...32).contains($0.depth) && (0..<64).contains($0.threadIndex) }
            && windowStart.timeIntervalSince1970.isFinite && windowEnd.timeIntervalSince1970.isFinite
            && windowStart <= windowEnd && (applicationVersion == nil || Self.identity(applicationVersion) == applicationVersion)
            && (build == nil || Self.identity(build) == build)
            && Set(values.keys).isSubset(of: keys) && values.values.allSatisfy { $0.isFinite && $0 >= 0 }
    }

    static func stack(_ data: Data) -> (frames: [Frame], truncated: Bool) {
        guard data.count <= 1024 * 1024,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tree = root["callStackTree"] as? [String: Any],
              let stacks = tree["callStacks"] as? [[String: Any]] else { return ([], true) }
        var frames: [Frame] = []
        var truncated = stacks.count > 64
        func unsigned(_ value: Any?) -> UInt64? {
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, number.doubleValue >= 0,
                  number.stringValue.range(of: "^[0-9]+$", options: .regularExpression) != nil else { return nil }
            return UInt64(number.stringValue)
        }
        func visit(_ nodes: [[String: Any]], depth: Int, threadIndex: Int, attributed: Bool) {
            guard depth <= 32 else { truncated = true; return }
            for node in nodes {
                guard frames.count < 1024 else { truncated = true; return }
                frames.append(Frame(binaryUUID: (node["binaryUUID"] as? String).flatMap(UUID.init(uuidString:)),
                                    address: unsigned(node["address"]), offset: unsigned(node["offsetIntoBinaryTextSegment"]),
                                    samples: unsigned(node["sampleCount"]), depth: depth,
                                    threadIndex: threadIndex, threadAttributed: attributed))
                if let children = node["subFrames"] as? [[String: Any]] { visit(children, depth: depth + 1, threadIndex: threadIndex, attributed: attributed) }
            }
        }
        for (index, stack) in stacks.prefix(64).enumerated() {
            if let roots = stack["callStackRootFrames"] as? [[String: Any]] {
                visit(roots, depth: 0, threadIndex: index, attributed: (stack["threadAttributed"] as? Bool) ?? false)
            }
        }
        return (frames, truncated)
    }
}

/// Lives for the process. Callbacks admit only eight deliveries; conversion runs on the local writer.
final class PlatformEvidence: NSObject, MXMetricManagerSubscriber {
    static let shared = PlatformEvidence()
    private let log: DebugLog
    init(log: DebugLog = .shared) { self.log = log; super.init() }
    func start() { MXMetricManager.shared.add(self) }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            log.ingestPlatform {
                var values: [String: Double] = [:]
                values["cpuSeconds"] = payload.cpuMetrics?.cumulativeCPUTime.converted(to: .seconds).value
                values["peakMemoryBytes"] = payload.memoryMetrics?.peakMemoryUsage.converted(to: .bytes).value
                values["diskWriteBytes"] = payload.diskIOMetrics?.cumulativeLogicalWrites.converted(to: .bytes).value
                values["foregroundSeconds"] = payload.applicationTimeMetrics?.cumulativeForegroundTime.converted(to: .seconds).value
                return [PlatformReport(schemaVersion: 1, kind: .metrics, windowStart: payload.timeStampBegin,
                    windowEnd: payload.timeStampEnd, applicationVersion: PlatformReport.identity(payload.latestApplicationVersion),
                    build: PlatformReport.identity(payload.metaData?.applicationBuildVersion),
                    multipleVersions: payload.includesMultipleApplicationVersions,
                    values: values.filter { $0.value.isFinite && $0.value >= 0 }, frames: [], truncated: false, correlation: "unknown")]
            }
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            log.ingestPlatform {
                var reports: [PlatformReport] = []
                func add(_ diagnostic: MXDiagnostic, kind: PlatformReport.Kind, stack: MXCallStackTree,
                         values: [String: Double]) {
                    let sanitized = PlatformReport.stack(stack.jsonRepresentation())
                    reports.append(PlatformReport(schemaVersion: 1, kind: kind, windowStart: payload.timeStampBegin,
                        windowEnd: payload.timeStampEnd, applicationVersion: PlatformReport.identity(diagnostic.applicationVersion),
                        build: PlatformReport.identity(diagnostic.metaData.applicationBuildVersion), multipleVersions: false,
                        values: values.filter { $0.value.isFinite && $0.value >= 0 }, frames: sanitized.frames,
                        truncated: sanitized.truncated, correlation: "unknown"))
                }
                for item in (payload.crashDiagnostics ?? []).prefix(32) {
                    var values: [String: Double] = [:]
                    values["exceptionType"] = item.exceptionType?.doubleValue
                    values["exceptionCode"] = item.exceptionCode?.doubleValue
                    values["signal"] = item.signal?.doubleValue
                    add(item, kind: .crash, stack: item.callStackTree, values: values)
                }
                for item in (payload.hangDiagnostics ?? []).prefix(32) {
                    add(item, kind: .hang, stack: item.callStackTree,
                        values: ["durationSeconds": item.hangDuration.converted(to: .seconds).value])
                }
                for item in (payload.cpuExceptionDiagnostics ?? []).prefix(32) {
                    add(item, kind: .cpu, stack: item.callStackTree,
                        values: ["cpuSeconds": item.totalCPUTime.converted(to: .seconds).value,
                                 "durationSeconds": item.totalSampledTime.converted(to: .seconds).value])
                }
                for item in (payload.diskWriteExceptionDiagnostics ?? []).prefix(32) {
                    add(item, kind: .diskWrite, stack: item.callStackTree,
                        values: ["diskWriteBytes": item.totalWritesCaused.converted(to: .bytes).value])
                }
                return reports
            }
        }
    }
}

struct SavedPlatformReport: Codable {
    let receivedAt: Date
    let report: PlatformReport
}

extension DebugLogStore {
    func appendPlatform(_ report: PlatformReport, receivedAt: Date = Date()) throws {
        guard report.isSafe, report.windowEnd <= receivedAt.addingTimeInterval(300),
              receivedAt.timeIntervalSince(report.windowEnd) < Self.ageLimit else { return }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let canonical = try encoder.encode(report)
        let digest = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        let url = directory.appendingPathComponent(digest + ".report")
        if FileManager.default.fileExists(atPath: url.path) { return }
        let data = try encoder.encode(SavedPlatformReport(receivedAt: receivedAt, report: report))
        guard data.count <= Self.segmentLimit else { throw CocoaError(.fileWriteOutOfSpace) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var folder = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        try prune(reserving: data.count)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

extension DebugLogStore {
    func platformSnapshot(now: Date = Date()) throws -> Data {
        try prune(now: now)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        var reports: [SavedPlatformReport] = []
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        for file in files where file.pathExtension == "report" {
            guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= Self.segmentLimit,
                  let data = try? Data(contentsOf: file),
                  let saved = try? decoder.decode(SavedPlatformReport.self, from: data), saved.report.isSafe,
                  now.timeIntervalSince(saved.report.windowEnd) < Self.ageLimit else { continue }
            reports.append(saved)
        }
        return try encoder.encode(reports.sorted { $0.report.windowStart < $1.report.windowStart })
    }
}
