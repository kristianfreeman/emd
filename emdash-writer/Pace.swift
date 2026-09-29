import Foundation
import os

/// Timings for Instruments (signposts) and a short log at `~/Library/Logs/EmDashWriter/pace.log`.
enum Pace {
    struct Sample: Equatable, Sendable {
        var name: String
        var milliseconds: Double
        var detail: String
    }

    struct Span: @unchecked Sendable {
        fileprivate var name: StaticString
        fileprivate var label: String
        fileprivate var state: OSSignpostIntervalState
        fileprivate var started: CFAbsoluteTime
    }

    private static let log = OSLog(subsystem: "com.kristianfreeman.emdash-writer", category: "pace")
    private static let poster = OSSignposter(logHandle: log)
    private static let lock = NSLock()
    private static var samples: [Sample] = []
    private static let fileQueue = DispatchQueue(label: "com.kristianfreeman.emdash-writer.pace", qos: .utility)

    static func begin(_ name: StaticString) -> Span {
        Span(name: name, label: "\(name)", state: poster.beginInterval(name), started: CFAbsoluteTimeGetCurrent())
    }

    static func end(_ span: Span, detail: String = "") {
        let milliseconds = (CFAbsoluteTimeGetCurrent() - span.started) * 1000
        poster.endInterval(span.name, span.state)
        record(Sample(name: span.label, milliseconds: milliseconds, detail: detail))
    }

    static func reset() {
        lock.lock()
        samples.removeAll()
        lock.unlock()
    }

    static func snapshot() -> [Sample] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    private static func record(_ sample: Sample) {
        remember(sample)
        guard shouldWrite(sample) else { return }
        let line = String(format: "%.2fms\t%@\t%@\n", sample.milliseconds, sample.name, sample.detail)
        fileQueue.async {
            write(line)
        }
    }

    private static func remember(_ sample: Sample) {
        lock.lock()
        samples.append(sample)
        trim()
        lock.unlock()
    }

    private static func trim() {
        guard samples.count > 200 else { return }
        samples.removeFirst(samples.count - 200)
    }

    /// The file log is for development. Outside Debug it is off unless `defaults write … paceLog -bool YES`.
    private static let writesLog: Bool = {
        #if DEBUG
            return true
        #else
            return UserDefaults.standard.bool(forKey: "paceLog")
        #endif
    }()

    private static func shouldWrite(_ sample: Sample) -> Bool {
        guard writesLog else { return false }
        let noisy = sample.name == "restyle" || sample.name == "layout"
        return !noisy || sample.milliseconds >= 1
    }

    private static func write(_ line: String) {
        guard let url = logURL() else { return }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            create(line, at: url)
            return
        }
        append(line, to: handle)
    }

    private static func append(_ line: String, to handle: FileHandle) {
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        write(line, to: handle)
        truncateIfHuge(handle)
    }

    private static func write(_ line: String, to handle: FileHandle) {
        guard let data = line.data(using: .utf8) else { return }
        try? handle.write(contentsOf: data)
    }

    private static func truncateIfHuge(_ handle: FileHandle) {
        guard let size = try? handle.seekToEnd(), size > 1_000_000 else { return }
        try? handle.truncate(atOffset: 0)
    }

    private static func create(_ line: String, at url: URL) {
        guard let data = line.data(using: .utf8) else { return }
        try? data.write(to: url)
    }

    private static func logURL() -> URL? {
        guard let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return nil }
        let directory = logs.appendingPathComponent("Logs/EmDashWriter", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("pace.log")
    }
}
