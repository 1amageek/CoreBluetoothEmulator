import Foundation

/// In-memory transport for testing cross-process scenarios within a single process
///
/// This transport simulates cross-process communication using shared in-memory state.
/// Perfect for testing distributed emulator scenarios without actual process separation.
///
/// ## Architecture
/// - Hub: Central coordinator with AsyncChannel for routing
/// - Clients: Connect to hub via shared instance
///
/// ## Usage Example
/// ```swift
/// // Create shared hub
/// let hub = InMemoryEmulatorTransport.Hub()
///
/// // Process A (Peripheral)
/// let peripheralTransport = InMemoryEmulatorTransport(
///     hub: hub,
///     processID: peripheralID,
///     role: .peripheral
/// )
/// await EmulatorBus.shared.configure(transport: .distributed(peripheralTransport))
///
/// // Process B (Central) - different EmulatorBus instance
/// let centralTransport = InMemoryEmulatorTransport(
///     hub: hub,
///     processID: centralID,
///     role: .central
/// )
/// await EmulatorBus.shared.configure(transport: .distributed(centralTransport))
/// ```
public actor InMemoryEmulatorTransport: EmulatorTransport {

    // MARK: - Hub

    /// Central hub for routing events between processes
    public actor Hub {
        private var clients: [UUID: Client] = [:]

        public init() {}

        /// Register a client
        func register(client: Client) {
            clients[client.processID] = client
        }

        /// Unregister a client
        func unregister(processID: UUID) {
            clients.removeValue(forKey: processID)
        }

        /// Route event from source to target
        func route(from sourceID: UUID, to targetID: UUID, data: Data) async throws {
            guard let targetClient = clients[targetID] else {
                throw InMemoryTransportError.clientNotFound(targetID)
            }

            await targetClient.receive(from: sourceID, data: data)
        }

        /// Broadcast event to all clients except sender
        func broadcast(from sourceID: UUID, data: Data) async {
            for (clientID, client) in clients where clientID != sourceID {
                await client.receive(from: sourceID, data: data)
            }
        }

        /// Get all registered client IDs
        func clientIDs() -> [UUID] {
            return Array(clients.keys)
        }
    }

    // MARK: - Client

    /// Client representation in hub
    public actor Client {
        let processID: UUID
        let role: EmulatorProcessRole
        private let eventContinuation: AsyncStream<(UUID, Data)>.Continuation

        init(processID: UUID, role: EmulatorProcessRole, continuation: AsyncStream<(UUID, Data)>.Continuation) {
            self.processID = processID
            self.role = role
            self.eventContinuation = continuation
        }

        func receive(from sourceID: UUID, data: Data) {
            eventContinuation.yield((sourceID, data))
        }

        func finish() {
            eventContinuation.finish()
        }
    }

    // MARK: - Transport State

    private let hub: Hub
    private let processID: UUID
    private let role: EmulatorProcessRole
    private var client: Client?

    private let eventStream: AsyncStream<(UUID, Data)>
    private let eventContinuation: AsyncStream<(UUID, Data)>.Continuation

    // MARK: - Initialization

    private var isRegistered = false

    public init(hub: Hub, processID: UUID = UUID(), role: EmulatorProcessRole = .both) {
        self.hub = hub
        self.processID = processID
        self.role = role

        // Create event stream
        var continuation: AsyncStream<(UUID, Data)>.Continuation!
        let stream = AsyncStream<(UUID, Data)> { streamContinuation in
            continuation = streamContinuation
        }
        self.eventStream = stream
        self.eventContinuation = continuation
    }

    /// Ensure the transport is registered with the hub
    private func ensureRegistered() async {
        guard !isRegistered else { return }

        let client = Client(
            processID: processID,
            role: role,
            continuation: eventContinuation
        )
        self.client = client
        await hub.register(client: client)
        isRegistered = true
    }

    /// Start the transport and register with hub
    /// Call this before using send() or receive() to ensure registration is complete
    public func start() async {
        await ensureRegistered()
    }

    // MARK: - EmulatorTransport Protocol

    public func send(_ data: Data, to targetID: UUID) async throws {
        await ensureRegistered()
        try await hub.route(from: processID, to: targetID, data: data)
    }

    public nonisolated func receive() -> AsyncStream<(UUID, Data)> {
        return eventStream
    }

    // MARK: - Cleanup

    public func cleanup() async {
        await hub.unregister(processID: processID)
        await client?.finish()
    }
}

// MARK: - Errors

public enum InMemoryTransportError: Error {
    case clientNotFound(UUID)
    case broadcastFailed
}

// MARK: - Testing Helpers

extension InMemoryEmulatorTransport {

    /// Create a pair of transports for testing (peripheral + central)
    public static func createTestPair() -> (peripheral: InMemoryEmulatorTransport, central: InMemoryEmulatorTransport, hub: Hub) {
        let hub = Hub()

        let peripheralID = UUID()
        let centralID = UUID()

        let peripheral = InMemoryEmulatorTransport(
            hub: hub,
            processID: peripheralID,
            role: .peripheral
        )

        let central = InMemoryEmulatorTransport(
            hub: hub,
            processID: centralID,
            role: .central
        )

        return (peripheral, central, hub)
    }
}
