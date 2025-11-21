import Foundation

#if canImport(Darwin)
import Darwin

/// XPC-based transport for inter-process EmulatorBus communication (macOS/iOS)
///
/// This transport uses XPC for reliable cross-process communication.
/// It supports hub-based architecture where:
/// - Hub process: Coordinates all BLE operations (full EmulatorBus state)
/// - Client processes: Send/receive events via hub
///
/// ## Usage Example
/// ```swift
/// // Hub process
/// let hubTransport = XPCEmulatorTransport.createHub(serviceName: "com.example.emulator.hub")
/// await EmulatorBus.shared.configure(transport: .distributed(hubTransport))
///
/// // Client process
/// let clientTransport = XPCEmulatorTransport.createClient(serviceName: "com.example.emulator.hub")
/// await EmulatorBus.shared.configure(transport: .distributed(clientTransport))
/// ```
public actor XPCEmulatorTransport: EmulatorTransport {

    // MARK: - Configuration

    private let role: EmulatorProcessRole
    private let processID: UUID
    private let serviceName: String

    // MARK: - XPC State

    private var connection: NSXPCConnection?
    private let eventStream: AsyncStream<(UUID, Data)>
    private let eventContinuation: AsyncStream<(UUID, Data)>.Continuation

    // MARK: - Initialization

    private init(role: EmulatorProcessRole, serviceName: String, processID: UUID = UUID()) {
        self.role = role
        self.serviceName = serviceName
        self.processID = processID

        // Create event stream
        var continuation: AsyncStream<(UUID, Data)>.Continuation!
        let stream = AsyncStream<(UUID, Data)> { streamContinuation in
            continuation = streamContinuation
        }
        self.eventStream = stream
        self.eventContinuation = continuation
    }

    /// Create hub transport (server)
    public static func createHub(serviceName: String) -> XPCEmulatorTransport {
        return XPCEmulatorTransport(role: .hub, serviceName: serviceName)
    }

    /// Create client transport
    public static func createClient(serviceName: String, role: EmulatorProcessRole = .both) -> XPCEmulatorTransport {
        return XPCEmulatorTransport(role: role, serviceName: serviceName)
    }

    // MARK: - EmulatorTransport Protocol

    public func send(_ data: Data, to targetID: UUID) async throws {
        guard let connection = connection else {
            throw XPCTransportError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as! XPCEmulatorProtocol

            proxy.sendEvent(data, to: targetID) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: XPCTransportError.sendFailed)
                }
            }
        }
    }

    public nonisolated func receive() -> AsyncStream<(UUID, Data)> {
        return eventStream
    }

    // MARK: - Connection Management

    /// Start XPC connection
    public func start() async throws {
        if role == .hub {
            try await startHub()
        } else {
            try await startClient()
        }
    }

    /// Start as hub (server)
    private func startHub() async throws {
        // Create XPC listener for incoming connections
        let listener = NSXPCListener(machServiceName: serviceName)
        listener.delegate = XPCListenerDelegate(transport: self)
        listener.resume()
    }

    /// Start as client
    private func startClient() async throws {
        let connection = NSXPCConnection(machServiceName: serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: XPCEmulatorProtocol.self)
        connection.exportedInterface = NSXPCInterface(with: XPCEmulatorClientProtocol.self)
        connection.exportedObject = XPCClientObject(transport: self)

        connection.resume()
        self.connection = connection

        // Register with hub
        try await registerWithHub()
    }

    /// Register this client with the hub
    private func registerWithHub() async throws {
        guard let connection = connection else {
            throw XPCTransportError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            } as! XPCEmulatorProtocol

            proxy.registerClient(processID, role: role.rawValue) { success, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: XPCTransportError.registrationFailed)
                }
            }
        }
    }

    /// Stop XPC connection
    public func stop() {
        connection?.invalidate()
        connection = nil
        eventContinuation.finish()
    }

    deinit {
        connection?.invalidate()
    }

    // MARK: - Internal Event Handling

    internal func handleIncomingEvent(from sourceID: UUID, data: Data) {
        eventContinuation.yield((sourceID, data))
    }
}

// MARK: - XPC Protocols

/// XPC protocol for hub service
@objc protocol XPCEmulatorProtocol {
    func registerClient(_ clientID: UUID, role: String, reply: @escaping (Bool, Error?) -> Void)
    func sendEvent(_ data: Data, to targetID: UUID, reply: @escaping (Bool, Error?) -> Void)
}

/// XPC protocol for client callbacks
@objc protocol XPCEmulatorClientProtocol {
    func receiveEvent(from sourceID: UUID, data: Data)
}

// MARK: - XPC Implementation Objects

private class XPCListenerDelegate: NSObject, NSXPCListenerDelegate {
    weak var transport: XPCEmulatorTransport?

    init(transport: XPCEmulatorTransport) {
        self.transport = transport
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.remoteObjectInterface = NSXPCInterface(with: XPCEmulatorClientProtocol.self)
        newConnection.exportedInterface = NSXPCInterface(with: XPCEmulatorProtocol.self)
        // TODO: Create hub object for handling client connections
        newConnection.resume()
        return true
    }
}

private class XPCClientObject: NSObject, XPCEmulatorClientProtocol {
    weak var transport: XPCEmulatorTransport?

    init(transport: XPCEmulatorTransport) {
        self.transport = transport
    }

    func receiveEvent(from sourceID: UUID, data: Data) {
        Task {
            await transport?.handleIncomingEvent(from: sourceID, data: data)
        }
    }
}

// MARK: - Errors

public enum XPCTransportError: Error {
    case notConnected
    case sendFailed
    case registrationFailed
}

#endif
