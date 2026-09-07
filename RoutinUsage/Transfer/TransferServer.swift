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
    case alreadyStarting
    case sessionExpired
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
    private static let maxHandshakeBytes = 64 * 1024

    init(
        host: String = TransferServer.defaultLANHost(),
        timeout: TimeInterval = TransferSession.defaultTimeout,
        session: TransferSession? = nil
    ) {
        self.host = host
        self.timeout = max(0.001, timeout)
        self.session = session ?? TransferSession(timeout: timeout)
    }

    func start() async throws -> TransferQRCodePayload {
        guard !isStopped else {
            let expired = await session.expireIfNeeded()
            let state = await session.state
            if expired || state.isTerminal {
                throw TransferServerError.sessionExpired
            }
            throw TransferServerError.notRunning
        }
        if let payload {
            let expired = await session.expireIfNeeded()
            let state = await session.state
            if expired || state.isTerminal {
                isStopped = true
                await closeTransport()
                throw TransferServerError.sessionExpired
            }
            do {
                try payload.validate()
            } catch TransferQRCodePayloadError.expired {
                isStopped = true
                await closeTransport()
                await session.cancel()
                throw TransferServerError.sessionExpired
            } catch {
                throw error
            }
            return payload
        }
        guard !isStarting else { throw TransferServerError.alreadyStarting }

        isStarting = true
        do {
            try await session.beginWaitingForAndroid()
            let listener = try NWListener(using: .tcp, on: .any)
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
        } catch {
            await failStart(with: error)
            throw error
        }
    }

    func stop() async {
        guard !isStopped else { return }
        isStopped = true
        await closeTransport()
        await session.cancel()
        resumeStart(with: CancellationError())
    }

    private func listenerDidUpdate(_ state: NWListener.State) async {
        switch state {
        case .ready:
            guard payload == nil, let port = listener?.port?.rawValue else { return }
            do {
                let nextPayload = try await session.makeQRCodePayload(host: host, port: Int(port))
                try nextPayload.validate()
                payload = nextPayload
                isStarting = false
                scheduleTimeout()
                resumeStart(returning: nextPayload)
            } catch {
                await failStart(with: error)
            }
        case .failed(let error):
            await failStart(with: TransferServerError.listenerFailed(error.localizedDescription))
        case .cancelled:
            if isStarting { await failStart(with: CancellationError()) }
        case .setup, .waiting:
            break
        @unknown default:
            break
        }
    }

    private func failStart(with error: Error) async {
        guard !isStopped || isStarting else { return }
        isStopped = true
        isStarting = false
        timeoutTask?.cancel()
        timeoutTask = nil
        await closeTransport()
        await session.cancel()
        resumeStart(with: error)
    }

    private func resumeStart(returning payload: TransferQRCodePayload) {
        guard let continuation = startContinuation else { return }
        startContinuation = nil
        continuation.resume(returning: payload)
    }

    private func resumeStart(with error: Error) {
        guard let continuation = startContinuation else { return }
        startContinuation = nil
        continuation.resume(throwing: error)
    }

    private func closeTransport() async {
        listener?.cancel()
        listener = nil
        pendingConnections.forEach { $0.cancel() }
        pendingConnections.removeAll()
        acceptedConnection?.cancel()
        acceptedConnection = nil
        receiveBuffers.removeAll()
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
            isStopped = true
            timeoutTask?.cancel()
            timeoutTask = nil
            await closeTransport()
            resumeStart(with: TransferServerError.sessionExpired)
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
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxHandshakeBytes) { [weak self, weak connection] data, _, isComplete, _ in
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
        guard let buffer = receiveBuffers[identifier] else { return }
        guard buffer.count <= Self.maxHandshakeBytes else {
            connection.cancel()
            pendingConnections.removeAll { $0 === connection }
            receiveBuffers.removeValue(forKey: identifier)
            return
        }
        guard let newline = buffer.firstIndex(of: 10) else { return }
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
                isStopped = true
                await closeTransport()
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
            let result = getnameinfo(address, socklen_t(address.pointee.sa_len), &numericHost, socklen_t(numericHost.count), nil, 0, NI_NUMERICHOST)
            if result == 0 { return String(cString: numericHost) }
        }
        #endif
        return "127.0.0.1"
    }
}
