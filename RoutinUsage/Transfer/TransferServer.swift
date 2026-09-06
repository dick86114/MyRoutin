import Foundation
import Network
#if canImport(Darwin)
import Darwin
#endif

protocol TransferServing: Sendable {
    func start() async throws -> TransferQRCodePayload
    func stop() async
}

/// The unencrypted, metadata-only request accepted before Task 4's encrypted
/// message protocol is added. It is deliberately not a transfer package.
struct TransferConnectionRequest: Codable, Sendable {
    let sessionID: UUID
    let connectionCode: String
    let macEphemeralPublicKey: Data
}

enum TransferServerError: Error, Equatable {
    case listenerFailed(String)
    case notRunning
    case invalidRequest
}

actor TransferServer: TransferServing {
    let session: TransferSession
    let host: String

    private let timeout: TimeInterval
    private var listener: NWListener?
    private var pendingConnections: [NWConnection] = []
    private var acceptedConnection: NWConnection?
    private var receiveBuffers: [ObjectIdentifier: Data] = [:]
    private var startContinuation: CheckedContinuation<TransferQRCodePayload, Error>?
    private var payload: TransferQRCodePayload?
    private var timeoutTask: Task<Void, Never>?
    private var isStarting = false
    private var isStopped = false

    init(
        host: String = TransferServer.defaultLANHost(),
        timeout: TimeInterval = TransferSession.defaultTimeout,
        session: TransferSession? = nil
    ) {
        self.host = host
        self.timeout = max(1, timeout)
        self.session = session ?? TransferSession(timeout: timeout)
    }

    func start() async throws -> TransferQRCodePayload {
        if let payload { return payload }
        if isStopped { throw TransferServerError.notRunning }
        if isStarting {
            return try await withCheckedThrowingContinuation { continuation in
                startContinuation = continuation
            }
        }
        isStarting = true
        try await session.beginWaitingForAndroid()

        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: .any)
        } catch {
            isStarting = false
            await session.cancel()
            throw TransferServerError.listenerFailed(String(describing: error))
        }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            Task { await self?.listenerDidUpdate(state) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.received(connection: connection) }
        }
        listener.start(queue: DispatchQueue(label: "ai.routin.transfer-server"))

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                startContinuation = continuation
            }
        }, onCancel: { [weak self] in
            Task { await self?.stop() }
        })
    }

    func stop() async {
        guard !isStopped else { return }
        isStopped = true
        timeoutTask?.cancel()
        timeoutTask = nil
        listener?.cancel()
        listener = nil
        pendingConnections.forEach { $0.cancel() }
        pendingConnections.removeAll()
        acceptedConnection?.cancel()
        acceptedConnection = nil
        receiveBuffers.removeAll()
        await session.cancel()
        if let startContinuation {
            self.startContinuation = nil
            startContinuation.resume(throwing: CancellationError())
        }
    }

    private func listenerDidUpdate(_ state: NWListener.State) async {
        switch state {
        case .ready:
            guard payload == nil, let port = listener?.port?.rawValue else { return }
            do {
                let nextPayload = try await sessionPayload(port: Int(port))
                payload = nextPayload
                isStarting = false
                scheduleTimeout()
                if let startContinuation {
                    self.startContinuation = nil
                    startContinuation.resume(returning: nextPayload)
                }
            } catch {
                isStarting = false
                listener?.cancel()
                if let startContinuation {
                    self.startContinuation = nil
                    startContinuation.resume(throwing: error)
                }
            }
        case .failed(let error):
            isStarting = false
            listener?.cancel()
            Task { await session.cancel() }
            if let startContinuation {
                self.startContinuation = nil
                startContinuation.resume(throwing: TransferServerError.listenerFailed(error.localizedDescription))
            }
        case .cancelled:
            break
        case .setup, .waiting:
            break
        @unknown default:
            break
        }
    }

    private func sessionPayload(port: Int) async throws -> TransferQRCodePayload {
        try await session.makeQRCodePayload(host: host, port: port)
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        let nanoseconds = UInt64(timeout * 1_000_000_000)
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: nanoseconds) } catch { return }
            await self?.expire()
        }
    }

    private func expire() async {
        guard !isStopped else { return }
        if await session.expireIfNeeded() {
            listener?.cancel()
            pendingConnections.forEach { $0.cancel() }
            pendingConnections.removeAll()
            acceptedConnection?.cancel()
            acceptedConnection = nil
        }
    }

    private func received(connection: NWConnection) {
        guard !isStopped, acceptedConnection == nil else {
            connection.cancel()
            return
        }
        pendingConnections.append(connection)
        let identifier = ObjectIdentifier(connection)
        receiveBuffers[identifier] = Data()
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            Task { await self?.connectionDidUpdate(connection, state: state) }
        }
        connection.start(queue: DispatchQueue(label: "ai.routin.transfer-connection"))
        receive(connection: connection)
    }

    private func receive(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak connection] data, _, isComplete, _ in
            guard let self, let connection else { return }
            Task {
                await self.received(data: data, from: connection)
                if !isComplete { await self.receiveMore(from: connection) }
            }
        }
    }

    private func receiveMore(from connection: NWConnection) {
        receive(connection: connection)
    }

    private func received(data: Data?, from connection: NWConnection) async {
        let identifier = ObjectIdentifier(connection)
        if let data { receiveBuffers[identifier, default: Data()].append(data) }
        guard let buffer = receiveBuffers[identifier], let newline = buffer.firstIndex(of: 10) else { return }
        let requestData = Data(buffer[..<newline])
        receiveBuffers.removeValue(forKey: identifier)
        do {
            let request = try JSONDecoder().decode(TransferConnectionRequest.self, from: requestData)
            try await session.acceptConnection(
                sessionID: request.sessionID,
                connectionCode: request.connectionCode,
                macEphemeralPublicKey: request.macEphemeralPublicKey
            )
            pendingConnections.removeAll { $0 === connection }
            acceptedConnection = connection
            let acknowledgement = Data(#"{"ok":true,"protocolVersion":1}"#.utf8) + Data([10])
            connection.send(content: acknowledgement, completion: .contentProcessed { _ in })
        } catch {
            connection.cancel()
            pendingConnections.removeAll { $0 === connection }
            receiveBuffers.removeValue(forKey: identifier)
        }
    }

    private func connectionDidUpdate(_ connection: NWConnection, state: NWConnection.State) async {
        switch state {
        case .failed, .cancelled:
            pendingConnections.removeAll { $0 === connection }
            receiveBuffers.removeValue(forKey: ObjectIdentifier(connection))
            if acceptedConnection === connection {
                acceptedConnection = nil
                await session.cancel()
            }
        default:
            break
        }
    }

    private static func defaultLANHost() -> String {
        #if canImport(Darwin)
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return "127.0.0.1" }
        defer { freeifaddrs(first) }
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            guard let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  (interface.pointee.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            var numericHost = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &numericHost,
                socklen_t(numericHost.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 { return String(cString: numericHost) }
        }
        #endif
        return "127.0.0.1"
    }
}
