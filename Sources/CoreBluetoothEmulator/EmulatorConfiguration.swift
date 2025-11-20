import Foundation
import CoreBluetooth

/// Configuration for the CoreBluetooth emulator
public struct EmulatorConfiguration: Sendable {

    // MARK: - Timing Settings

    /// Delay before transitioning to .poweredOn state
    public var stateUpdateDelay: TimeInterval

    /// Interval between scan discovery notifications
    public var scanDiscoveryInterval: TimeInterval

    /// Delay for connection establishment
    public var connectionDelay: TimeInterval

    /// Delay for disconnection
    public var disconnectionDelay: TimeInterval

    /// Delay for service discovery
    public var serviceDiscoveryDelay: TimeInterval

    /// Delay for characteristic discovery
    public var characteristicDiscoveryDelay: TimeInterval

    /// Delay for descriptor discovery
    public var descriptorDiscoveryDelay: TimeInterval

    /// Delay for read operations
    public var readDelay: TimeInterval

    /// Delay for write operations
    public var writeDelay: TimeInterval

    /// Delay for notification delivery
    public var notificationDelay: TimeInterval

    // MARK: - RSSI Settings

    /// Range of RSSI values to generate
    public var rssiRange: ClosedRange<Int>

    /// Random variation in RSSI (+/- this value)
    public var rssiVariation: Int

    // MARK: - Error Simulation

    /// Whether to simulate connection failures
    public var simulateConnectionFailure: Bool

    /// Probability of connection failure (0.0 - 1.0)
    public var connectionFailureRate: Double

    /// Whether to simulate read/write errors
    public var simulateReadWriteErrors: Bool

    /// Probability of read/write errors (0.0 - 1.0)
    public var readWriteErrorRate: Double

    // MARK: - MTU Settings

    /// Default MTU size
    public var defaultMTU: Int

    /// Maximum MTU size
    public var maximumMTU: Int

    // MARK: - Backpressure Settings

    /// Maximum number of Write Without Response operations in flight
    public var maxWriteWithoutResponseQueue: Int

    /// Maximum number of notifications in flight
    public var maxNotificationQueue: Int

    /// Whether to simulate backpressure (queue full scenarios)
    public var simulateBackpressure: Bool

    /// Delay for backpressure queue processing (time to drain one item from queue)
    public var backpressureProcessingDelay: TimeInterval

    // MARK: - Security Settings

    /// Whether to require pairing for encrypted characteristics
    public var requirePairing: Bool

    /// Whether to simulate pairing process
    public var simulatePairing: Bool

    /// Delay for pairing process
    public var pairingDelay: TimeInterval

    /// Whether pairing should succeed
    public var pairingSucceeds: Bool

    // MARK: - Scan Options

    /// Honor CBCentralManagerScanOptionAllowDuplicatesKey
    public var honorAllowDuplicatesOption: Bool

    /// Honor CBCentralManagerScanOptionSolicitedServiceUUIDsKey
    public var honorSolicitedServiceUUIDs: Bool

    // MARK: - Background Mode

    /// Whether background mode is enabled
    public var backgroundModeEnabled: Bool

    /// Whether to preserve state for restoration
    public var stateRestorationEnabled: Bool

    // MARK: - L2CAP Settings

    /// Whether L2CAP channels are supported
    public var l2capSupported: Bool

    /// Default L2CAP PSM range
    public var l2capPSMRange: ClosedRange<UInt16>

    // MARK: - Connection Events

    /// Whether to fire connection events
    public var fireConnectionEvents: Bool

    /// Whether to fire ANCS authorization updates
    public var fireANCSAuthorizationUpdates: Bool

    // MARK: - Advertisement Settings

    /// Whether to auto-generate system advertisement fields (TxPowerLevel, IsConnectable)
    public var autoGenerateAdvertisementFields: Bool

    // MARK: - Presets

    /// Default configuration with realistic timing
    public static var `default`: EmulatorConfiguration {
        EmulatorConfiguration(
            stateUpdateDelay: 0.1,
            scanDiscoveryInterval: 0.5,
            connectionDelay: 0.2,
            disconnectionDelay: 0.1,
            serviceDiscoveryDelay: 0.15,
            characteristicDiscoveryDelay: 0.15,
            descriptorDiscoveryDelay: 0.15,
            readDelay: 0.05,
            writeDelay: 0.05,
            notificationDelay: 0.05,
            rssiRange: -80...(-40),
            rssiVariation: 5,
            simulateConnectionFailure: false,
            connectionFailureRate: 0.0,
            simulateReadWriteErrors: false,
            readWriteErrorRate: 0.0,
            defaultMTU: 185,
            maximumMTU: 512,
            maxWriteWithoutResponseQueue: 20,
            maxNotificationQueue: 20,
            simulateBackpressure: false,
            backpressureProcessingDelay: 0.1,
            requirePairing: false,
            simulatePairing: false,
            pairingDelay: 0.5,
            pairingSucceeds: true,
            honorAllowDuplicatesOption: true,
            honorSolicitedServiceUUIDs: true,
            backgroundModeEnabled: false,
            stateRestorationEnabled: false,
            l2capSupported: false,
            l2capPSMRange: 0x0080...0x00FF,
            fireConnectionEvents: false,
            fireANCSAuthorizationUpdates: false,
            autoGenerateAdvertisementFields: true
        )
    }

    /// Instant configuration with no delays (for testing)
    public static var instant: EmulatorConfiguration {
        EmulatorConfiguration(
            stateUpdateDelay: 0.0,
            scanDiscoveryInterval: 0.01,
            connectionDelay: 0.0,
            disconnectionDelay: 0.0,
            serviceDiscoveryDelay: 0.0,
            characteristicDiscoveryDelay: 0.0,
            descriptorDiscoveryDelay: 0.0,
            readDelay: 0.0,
            writeDelay: 0.0,
            notificationDelay: 0.0,
            rssiRange: -60...(-50),
            rssiVariation: 2,
            simulateConnectionFailure: false,
            connectionFailureRate: 0.0,
            simulateReadWriteErrors: false,
            readWriteErrorRate: 0.0,
            defaultMTU: 185,
            maximumMTU: 512,
            maxWriteWithoutResponseQueue: 20,
            maxNotificationQueue: 20,
            simulateBackpressure: false,
            backpressureProcessingDelay: 0.0,
            requirePairing: false,
            simulatePairing: false,
            pairingDelay: 0.0,
            pairingSucceeds: true,
            honorAllowDuplicatesOption: true,
            honorSolicitedServiceUUIDs: true,
            backgroundModeEnabled: false,
            stateRestorationEnabled: false,
            l2capSupported: false,
            l2capPSMRange: 0x0080...0x00FF,
            fireConnectionEvents: false,
            fireANCSAuthorizationUpdates: false,
            autoGenerateAdvertisementFields: true
        )
    }

    /// Slow configuration (simulates poor connection)
    public static var slow: EmulatorConfiguration {
        EmulatorConfiguration(
            stateUpdateDelay: 0.5,
            scanDiscoveryInterval: 2.0,
            connectionDelay: 1.0,
            disconnectionDelay: 0.5,
            serviceDiscoveryDelay: 0.5,
            characteristicDiscoveryDelay: 0.5,
            descriptorDiscoveryDelay: 0.5,
            readDelay: 0.2,
            writeDelay: 0.2,
            notificationDelay: 0.2,
            rssiRange: -90...(-70),
            rssiVariation: 10,
            simulateConnectionFailure: false,
            connectionFailureRate: 0.0,
            simulateReadWriteErrors: false,
            readWriteErrorRate: 0.0,
            defaultMTU: 23,
            maximumMTU: 185,
            maxWriteWithoutResponseQueue: 5,
            maxNotificationQueue: 5,
            simulateBackpressure: true,
            backpressureProcessingDelay: 0.3,
            requirePairing: false,
            simulatePairing: false,
            pairingDelay: 1.0,
            pairingSucceeds: true,
            honorAllowDuplicatesOption: true,
            honorSolicitedServiceUUIDs: true,
            backgroundModeEnabled: false,
            stateRestorationEnabled: false,
            l2capSupported: false,
            l2capPSMRange: 0x0080...0x00FF,
            fireConnectionEvents: false,
            fireANCSAuthorizationUpdates: false,
            autoGenerateAdvertisementFields: true
        )
    }

    /// Unreliable configuration (simulates errors)
    public static var unreliable: EmulatorConfiguration {
        EmulatorConfiguration(
            stateUpdateDelay: 0.1,
            scanDiscoveryInterval: 0.5,
            connectionDelay: 0.2,
            disconnectionDelay: 0.1,
            serviceDiscoveryDelay: 0.15,
            characteristicDiscoveryDelay: 0.15,
            descriptorDiscoveryDelay: 0.15,
            readDelay: 0.05,
            writeDelay: 0.05,
            notificationDelay: 0.05,
            rssiRange: -90...(-40),
            rssiVariation: 15,
            simulateConnectionFailure: true,
            connectionFailureRate: 0.2,
            simulateReadWriteErrors: true,
            readWriteErrorRate: 0.1,
            defaultMTU: 185,
            maximumMTU: 512,
            maxWriteWithoutResponseQueue: 10,
            maxNotificationQueue: 10,
            simulateBackpressure: true,
            backpressureProcessingDelay: 0.2,
            requirePairing: false,
            simulatePairing: true,
            pairingDelay: 0.5,
            pairingSucceeds: false,
            honorAllowDuplicatesOption: true,
            honorSolicitedServiceUUIDs: true,
            backgroundModeEnabled: false,
            stateRestorationEnabled: false,
            l2capSupported: false,
            l2capPSMRange: 0x0080...0x00FF,
            fireConnectionEvents: false,
            fireANCSAuthorizationUpdates: false,
            autoGenerateAdvertisementFields: true
        )
    }

    // MARK: - Initializer

    public init(
        stateUpdateDelay: TimeInterval = 0.1,
        scanDiscoveryInterval: TimeInterval = 0.5,
        connectionDelay: TimeInterval = 0.2,
        disconnectionDelay: TimeInterval = 0.1,
        serviceDiscoveryDelay: TimeInterval = 0.15,
        characteristicDiscoveryDelay: TimeInterval = 0.15,
        descriptorDiscoveryDelay: TimeInterval = 0.15,
        readDelay: TimeInterval = 0.05,
        writeDelay: TimeInterval = 0.05,
        notificationDelay: TimeInterval = 0.05,
        rssiRange: ClosedRange<Int> = -80...(-40),
        rssiVariation: Int = 5,
        simulateConnectionFailure: Bool = false,
        connectionFailureRate: Double = 0.0,
        simulateReadWriteErrors: Bool = false,
        readWriteErrorRate: Double = 0.0,
        defaultMTU: Int = 185,
        maximumMTU: Int = 512,
        maxWriteWithoutResponseQueue: Int = 20,
        maxNotificationQueue: Int = 20,
        simulateBackpressure: Bool = false,
        backpressureProcessingDelay: TimeInterval = 0.1,
        requirePairing: Bool = false,
        simulatePairing: Bool = false,
        pairingDelay: TimeInterval = 0.5,
        pairingSucceeds: Bool = true,
        honorAllowDuplicatesOption: Bool = true,
        honorSolicitedServiceUUIDs: Bool = true,
        backgroundModeEnabled: Bool = false,
        stateRestorationEnabled: Bool = false,
        l2capSupported: Bool = false,
        l2capPSMRange: ClosedRange<UInt16> = 0x0080...0x00FF,
        fireConnectionEvents: Bool = false,
        fireANCSAuthorizationUpdates: Bool = false,
        autoGenerateAdvertisementFields: Bool = true
    ) {
        self.stateUpdateDelay = stateUpdateDelay
        self.scanDiscoveryInterval = scanDiscoveryInterval
        self.connectionDelay = connectionDelay
        self.disconnectionDelay = disconnectionDelay
        self.serviceDiscoveryDelay = serviceDiscoveryDelay
        self.characteristicDiscoveryDelay = characteristicDiscoveryDelay
        self.descriptorDiscoveryDelay = descriptorDiscoveryDelay
        self.readDelay = readDelay
        self.writeDelay = writeDelay
        self.notificationDelay = notificationDelay
        self.rssiRange = rssiRange
        self.rssiVariation = rssiVariation
        self.simulateConnectionFailure = simulateConnectionFailure
        self.connectionFailureRate = connectionFailureRate
        self.simulateReadWriteErrors = simulateReadWriteErrors
        self.readWriteErrorRate = readWriteErrorRate
        self.defaultMTU = defaultMTU
        self.maximumMTU = maximumMTU
        self.maxWriteWithoutResponseQueue = maxWriteWithoutResponseQueue
        self.maxNotificationQueue = maxNotificationQueue
        self.simulateBackpressure = simulateBackpressure
        self.backpressureProcessingDelay = backpressureProcessingDelay
        self.requirePairing = requirePairing
        self.simulatePairing = simulatePairing
        self.pairingDelay = pairingDelay
        self.pairingSucceeds = pairingSucceeds
        self.honorAllowDuplicatesOption = honorAllowDuplicatesOption
        self.honorSolicitedServiceUUIDs = honorSolicitedServiceUUIDs
        self.backgroundModeEnabled = backgroundModeEnabled
        self.stateRestorationEnabled = stateRestorationEnabled
        self.l2capSupported = l2capSupported
        self.l2capPSMRange = l2capPSMRange
        self.fireConnectionEvents = fireConnectionEvents
        self.fireANCSAuthorizationUpdates = fireANCSAuthorizationUpdates
        self.autoGenerateAdvertisementFields = autoGenerateAdvertisementFields
    }
}
