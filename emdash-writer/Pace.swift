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
        lock.lock()
        samples.append(sample)
        if samples.count > 200 {
            samples.removeFirst(samples.count - 200)
        }
        lock.unlock()
        let noisy = sample.name == "restyle" || sample.name == "layout"
        let write = !noisy || sample.milliseconds >= 1
        guard write else { return }
        let line = String(format: "%.2fms\t%@\t%@\n", sample.milliseconds, sample.name, sample.detail)
        fileQueue.async {
            guard let url = logURL() else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try? handle.write(contentsOf: data)
                }
                if let size = try? handle.seekToEnd(), size > 1_000_000 {
                    try? handle.truncate(atOffset: 0)
                }
            } else if let data = line.data(using: .utf8) {
                try? data.write(to: url)
            }
        }
    }

    private static func logURL() -> URL? {
        guard let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return nil }
        let directory = logs.appendingPathComponent("Logs/EmDashWriter", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("pace.log")
    }
}
