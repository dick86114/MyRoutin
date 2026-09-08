import Foundation
import Network
#if canImport(Darwin)
import Darwin
#endif

protocol TransferServing: Sendable {
    func start() async throws -> TransferQRCodePayload
    func stop() async
}

/// The metadata-only connection request Android sends first. The encrypted
/// transfer package is only sent afterwards via `send(package:)`.
struct TransferConnectionRequest: Codable, Sendable {
    let sessionID: UUID
    let connectionCode: String
    let macEphemeralPublicKey: Data
}

enum TransferServerError: Error, Equatable {
    case listenerFailed(String)
    case notRunning
    case alreadyStarting
    case alreadyStarted
    case sessionExpired
    case invalidRequest
    case notConnected
    case handshakeIncomplete
    case sendFailed(String)
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
            guard !isStarting else { throw TransferServerError.alreadyStarting }
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
            if !isStopped { await failStart(with: isStarting ? CancellationError() : TransferServerError.sessionExpired) }
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
        // Process complete lines one at a time. The consumed buffer is written
        // back before every await, so a receive callback that interleaves
        // during `await received(line:)` appends to (and processes) the
        // up-to-date buffer instead of being clobbered by a stale snapshot.
        while var buffer = receiveBuffers[identifier] {
            guard buffer.count <= Self.maxHandshakeBytes else {
                connection.cancel()
                pendingConnections.removeAll { $0 === connection }
                receiveBuffers.removeValue(forKey: identifier)
                return
            }
            guard let newline = buffer.firstIndex(of: 10) else { break }
            let lineData = Data(buffer[..<newline])
            buffer.removeSubrange(..<buffer.index(after: newline))
            receiveBuffers[identifier] = buffer
            await received(line: lineData, from: connection, identifier: identifier)
            guard receiveBuffers[identifier] != nil else { return }
        }
    }

    private func received(line lineData: Data, from connection: NWConnection, identifier: ObjectIdentifier) async {
        if acceptedConnection !== connection {
            await receiveConnectionRequest(lineData, from: connection, identifier: identifier)
        } else {
            await receiveHandshake(lineData, from: connection, identifier: identifier)
        }
    }

    private func receiveConnectionRequest(_ requestData: Data, from connection: NWConnection, identifier: ObjectIdentifier) async {
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
            rejectConnection(connection, identifier: identifier)
            let state = await session.state
            if state.isTerminal {
                isStopped = true
                timeoutTask?.cancel()
                timeoutTask = nil
                await closeTransport()
                resumeStart(with: TransferServerError.sessionExpired)
            }
        }
    }

    private func receiveHandshake(_ handshakeData: Data, from connection: NWConnection, identifier: ObjectIdentifier) async {
        do {
            let handshake = try JSONDecoder().decode(TransferHandshake.self, from: handshakeData)
            try await session.acceptHandshake(handshake)
        } catch {
            // A failed handshake cancels the accepted connection; the
            // disconnect handler terminates the one-shot session.
            connection.cancel()
            receiveBuffers.removeValue(forKey: identifier)
            let state = await session.state
            if state.isTerminal {
                isStopped = true
                timeoutTask?.cancel()
                timeoutTask = nil
                await closeTransport()
            }
        }
    }

    private func rejectConnection(_ connection: NWConnection, identifier: ObjectIdentifier) {
        connection.cancel()
        pendingConnections.removeAll { $0 === connection }
        receiveBuffers.removeValue(forKey: identifier)
    }

    /// Sends the transfer package to the accepted client exactly once: the
    /// whole package is JSON-serialized, AEAD-sealed with the derived session
    /// key, and only then transmitted. The session is marked `sent` after the
    /// wire write succeeds, so a second send is refused.
    func send(package: TransferPackageV1) async throws {
        guard !isStopped else { throw TransferServerError.notRunning }
        guard let connection = acceptedConnection else { throw TransferServerError.notConnected }
        guard await session.hasSessionKey else { throw TransferServerError.handshakeIncomplete }
        // Android 按 shared schema 将 exportedAt 解码为 ISO8601 字符串；
        // 默认 JSONEncoder 会把它编码成时间间隔数字。
        let plaintext = try TransferSchemaCodec.encode(package)
        // sealMessage refuses a session that already sent (replay protection)
        // or is not connected; the session error propagates to the caller.
        let message = try await session.sealMessage(plaintext)
        let line = try JSONEncoder().encode(message) + Data([10])
        do {
            try await send(line, over: connection)
        } catch {
            throw TransferServerError.sendFailed(error.localizedDescription)
        }
        try await session.markSent()
    }

    private func send(_ data: Data, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
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
        var candidates: [LANInterface] = []
        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            guard let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  (interface.pointee.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            var numericHost = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(address, socklen_t(address.pointee.sa_len), &numericHost, socklen_t(numericHost.count), nil, 0, NI_NUMERICHOST)
            if result == 0 {
                let name = String(cString: interface.pointee.ifa_name)
                candidates.append(
                    LANInterface(
                        name: name,
                        address: String(cString: numericHost),
                        isUp: interface.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                        isRunning: interface.pointee.ifa_flags & UInt32(IFF_RUNNING) != 0
                    )
                )
            }
        }
        return preferredLANHost(from: candidates)
#else
        return "127.0.0.1"
#endif
    }

    /// 手机只能直连 Mac 当前局域网内的私网地址。macOS 上存在 Wi-Fi、桥接、
    /// AWDL、VPN 和 link-local 等多个 IPv4 地址，必须避免把不可达地址写入二维码。
    static func preferredLANHost(from interfaces: [LANInterface]) -> String {
        let preferredPrefixes = ["en", "Ethernet", "Wi-Fi"]
        let ranked = interfaces.map { interface -> (LANInterface, Int) in
            let address = interface.address
            let isPrivate = address.hasPrefix("10.") ||
                address.hasPrefix("192.168.") ||
                (address.hasPrefix("172.") && isPrivateRFC1918SecondOctet(address))
            let isRoutable = isPrivate || (!address.hasPrefix("169.254.") && !address.hasPrefix("127."))
            let isPhysical = preferredPrefixes.contains { interface.name.hasPrefix($0) }

            var score = 0
            if interface.isUp { score += 40 }
            if interface.isRunning { score += 20 }
            if isPrivate { score += 30 }
            if isPhysical { score += 20 }
            if isRoutable { score += 10 } else { score -= 100 }
            if address.hasPrefix("169.254.") || address.hasPrefix("127.") { score -= 100 }
            return (interface, score)
        }
        .filter { $0.1 > 0 }
        .max { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.name > rhs.0.name
        }
        return ranked?.0.address ?? "127.0.0.1"
    }

    private static func isPrivateRFC1918SecondOctet(_ address: String) -> Bool {
        guard let second = address.split(separator: ".").dropFirst().first,
              let value = Int(second) else { return false }
        return (16...31).contains(value)
    }
}

struct LANInterface: Equatable, Sendable {
    let name: String
    let address: String
    let isUp: Bool
    let isRunning: Bool
}
