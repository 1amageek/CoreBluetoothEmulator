import Foundation

/// Protocol for transporting emulator events across process boundaries
///
/// Implementations of this protocol enable CoreBluetoothEmulator to work
/// in distributed testing scenarios where central and peripheral managers
/// run in separate processes.
///
/// ## Built-in Implementations
/// - In-process: Default mode, no transport needed (singleton EmulatorBus)
/// - XPC: See XPCEmulatorTransport for macOS/iOS inter-process communication
/// - Unix Socket: See UnixSocketEmulatorTransport for cross-platform support
///
/// ## Usage Example
/// ```swift
/// // Process A (Peripheral)
/// let transport = XPCEmulatorTransport(role: .peripheral, hubEndpoint: endpoint)
/// await EmulatorBus.shared.configure(transport: .distributed(transport))
///
/// // Process B (Central)
/// let transport = XPCEmulatorTransport(role: .central, hubEndpoint: endpoint)
/// await EmulatorBus.shared.configure(transport: .distributed(transport))
/// ```
public protocol EmulatorTransport: Sendable {

    /// Send event data to a target process
    /// - Parameters:
    ///   - data: Serialized EmulatorInternalEvent
    ///   - targetID: Target process identifier (UUID)
    /// - Throws: Transport errors (connection failure, serialization, etc.)
    func send(_ data: Data, to targetID: UUID) async throws

    /// Receive stream of events from other processes
    /// - Returns: AsyncStream of (UUID, Data) tuples (sourceID, eventData)
    /// - Note: Stream should remain open until transport is deallocated
    func receive() -> AsyncStream<(UUID, Data)>
}

/// Role of this process in the distributed emulator
public enum EmulatorProcessRole: String, Codable, Sendable {
    case hub        // Coordinator process (holds full state)
    case central    // Acts as central manager only
    case peripheral // Acts as peripheral manager only
    case both       // Acts as both (default for in-process)
}

/// Configuration for distributed emulator transport
public struct EmulatorTransportConfiguration: Sendable {
    /// Role of this process
    public let role: EmulatorProcessRole

    /// Process identifier (auto-generated if nil)
    public let processID: UUID

    /// Hub endpoint (only for non-hub roles)
    public let hubEndpoint: String?

    public init(
        role: EmulatorProcessRole,
        processID: UUID = UUID(),
        hubEndpoint: String? = nil
    ) {
        self.role = role
        self.processID = processID
        self.hubEndpoint = hubEndpoint
    }
}
