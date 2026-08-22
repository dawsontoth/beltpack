import Foundation
import Network
import OSLog

/// A deliberately small HTTP/1.1 server, built on Network.framework so there is
/// no dependency to keep current.
///
/// It handles exactly what the control plane needs: one request per connection,
/// `Content-Length` bodies, no chunked encoding, no keep-alive, no TLS. That is
/// adequate for a handful of operators on a private VLAN behind Caddy, and
/// nothing like a general-purpose web server. Do not expose it to the internet.
public final class HTTPServer: @unchecked Sendable {
    public struct Request: Sendable {
        public let method: String
        public let path: String
        public let query: [String: String]
        public let headers: [String: String]
        public let body: Data

        public func header(_ name: String) -> String? {
            headers[name.lowercased()]
        }

        public func json<T: Decodable>(_ type: T.Type) -> T? {
            try? JSONDecoder().decode(type, from: body)
        }
    }

    public struct Response: Sendable {
        public var status: Int
        public var headers: [String: String]
        public var body: Data

        public init(status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
            self.status = status
            self.headers = headers
            self.body = body
        }

        public static func json(_ object: some Encodable, status: Int = 200) -> Response {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = (try? encoder.encode(object)) ?? Data()
            return Response(status: status, headers: ["content-type": "application/json"], body: data)
        }

        public static func text(_ string: String, status: Int = 200, type: String = "text/plain; charset=utf-8") -> Response {
            Response(status: status, headers: ["content-type": type], body: Data(string.utf8))
        }

        public static let notFound = Response.text("not found", status: 404)
    }

    public typealias Handler = @Sendable (Request) async -> Response

    private let port: NWEndpoint.Port
    /// Set once before `start()`. Not a constructor argument because the
    /// handler usually needs a reference back to whatever owns the server.
    public var onRequest: Handler?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "org.beltpack.http")
    private let log = Logger(subsystem: "org.beltpack", category: "http")

    public init(port: UInt16) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    public func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
        log.notice("control server listening on \(self.port.rawValue, privacy: .public)")
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            if error != nil || (isComplete && chunk == nil) {
                connection.cancel()
                return
            }

            var buffer = buffer
            if let chunk { buffer.append(chunk) }

            // Keep reading until headers are complete and the declared body has
            // arrived; a request can span several reads.
            guard let headerEnd = Self.rangeOfHeaderTerminator(in: buffer) else {
                self.receive(connection, buffer: buffer)
                return
            }

            let headerData = buffer[buffer.startIndex ..< headerEnd.lowerBound]
            guard let request = Self.parseHead(headerData) else {
                self.send(.text("bad request", status: 400), on: connection)
                return
            }

            let expected = Int(request.headers["content-length"] ?? "0") ?? 0
            let bodyStart = headerEnd.upperBound
            let available = buffer.count - buffer.distance(from: buffer.startIndex, to: bodyStart)
            if available < expected {
                self.receive(connection, buffer: buffer)
                return
            }

            let body = Data(buffer[bodyStart...].prefix(expected))
            let full = Request(
                method: request.method,
                path: request.path,
                query: request.query,
                headers: request.headers,
                body: body,
            )

            Task {
                let response = await self.onRequest?(full) ?? .notFound
                self.send(response, on: connection)
            }
        }
    }

    private static func rangeOfHeaderTerminator(in data: Data) -> Range<Data.Index>? {
        data.range(of: Data("\r\n\r\n".utf8)) ?? data.range(of: Data("\n\n".utf8))
    }

    private static func parseHead(_ data: Data) -> Request? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.split(whereSeparator: \.isNewline)
        guard let requestLine = lines.first else { return nil }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0]).uppercased()
        let target = String(parts[1])

        var path = target
        var query: [String: String] = [:]
        if let mark = target.firstIndex(of: "?") {
            path = String(target[target.startIndex ..< mark])
            let items = URLComponents(string: target)?.queryItems ?? []
            for item in items { query[item.name] = item.value ?? "" }
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex ..< colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        return Request(method: method, path: path, query: query, headers: headers, body: Data())
    }

    private func send(_ response: Response, on connection: NWConnection) {
        var head = "HTTP/1.1 \(response.status) \(Self.reason(response.status))\r\n"
        var headers = response.headers
        headers["content-length"] = String(response.body.count)
        headers["connection"] = "close"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"

        var out = Data(head.utf8)
        out.append(response.body)
        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 500: "Internal Server Error"
        default: "OK"
        }
    }
}
