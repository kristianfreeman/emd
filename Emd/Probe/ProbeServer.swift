#if DEBUG
    import Foundation
    import Network

    /// A control channel for Debug builds: HTTP on 127.0.0.1, a random port, and a random token.
    /// `probe.json` in Application Support says where it is. `scripts/probe` is the client.
    /// Release builds do not contain this file.
    @MainActor
    final class ProbeServer {
        static let shared = ProbeServer()

        private var listener: NWListener?
        private let token = UUID().uuidString
        private let queue = DispatchQueue(label: "Probe.server")
        private var routes: ProbeRoutes?

        func start(model: AppModel) {
            guard listener == nil else { return }
            routes = ProbeRoutes(model: model)
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
            guard let listener = try? NWListener(using: parameters) else { return }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard case .ready = state else { return }
                Task { @MainActor in self?.announce() }
            }
            listener.start(queue: queue)
            self.listener = listener
        }

        /// Writes where the probe listens, readable by this user only.
        private func announce() {
            guard let port = listener?.port?.rawValue, let url = Self.announcement else { return }
            let info: JSONValue = .object([
                "port": .number(Double(port)), "token": .string(token),
                "pid": .number(Double(ProcessInfo.processInfo.processIdentifier)),
            ])
            guard let data = try? info.data() else { return }
            FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
        }

        static var announcement: URL? {
            let support = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return support?.appending(path: "\(AppIdentity.folder)/probe.json")
        }

        private func accept(_ connection: NWConnection) {
            connection.start(queue: queue)
            receive(on: connection, buffer: Data())
        }

        private nonisolated func receive(on connection: NWConnection, buffer: Data) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) {
                [weak self] chunk, _, done, error in
                var data = buffer
                data.append(chunk ?? Data())
                if let request = ProbeRequest(data) {
                    Task { @MainActor in await self?.answer(request, on: connection) }
                } else if done || error != nil {
                    connection.cancel()
                } else {
                    self?.receive(on: connection, buffer: data)
                }
            }
        }

        private func answer(_ request: ProbeRequest, on connection: NWConnection) async {
            let response: ProbeResponse
            if request.headers["x-probe-token"] != token {
                response = .json(.object(["error": .string("Missing or wrong X-Probe-Token.")]), status: 401)
            } else {
                response = await routes?.handle(request) ?? .json(.object([:]), status: 503)
            }
            connection.send(content: response.encoded(), completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    /// One HTTP request, once all of it has arrived.
    struct ProbeRequest {
        var method: String
        var path: String
        var query: [String: String]
        var headers: [String: String]
        var body: JSONValue

        init?(_ data: Data) {
            guard let split = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
            let head = String(decoding: data[..<split.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            let parts = (head.first ?? "").split(separator: " ")
            guard parts.count >= 2 else { return nil }
            headers = Self.headers(head.dropFirst())
            let bodyData = data[split.upperBound...]
            guard bodyData.count >= Int(headers["content-length"] ?? "0") ?? 0 else { return nil }
            method = String(parts[0])
            let components = URLComponents(string: String(parts[1]))
            path = components?.path ?? "/"
            query = Dictionary(
                (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
            body = (try? JSONDecoding.value(from: Data(bodyData))) ?? .object([:])
        }

        private static func headers(_ lines: ArraySlice<String>) -> [String: String] {
            let pairs = lines.compactMap { line -> (String, String)? in
                guard let colon = line.firstIndex(of: ":") else { return nil }
                return (
                    line[..<colon].lowercased(), line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                )
            }
            return Dictionary(pairs) { $1 }
        }
    }

    struct ProbeResponse {
        var status: Int
        var type: String
        var body: Data

        static func json(_ value: JSONValue, status: Int = 200) -> ProbeResponse {
            ProbeResponse(status: status, type: "application/json", body: (try? value.data()) ?? Data("{}".utf8))
        }

        static func png(_ data: Data) -> ProbeResponse {
            ProbeResponse(status: 200, type: "image/png", body: data)
        }

        func encoded() -> Data {
            let head =
                "HTTP/1.1 \(status) OK\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            return Data(head.utf8) + body
        }
    }
#endif
