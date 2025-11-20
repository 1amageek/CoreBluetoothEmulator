import Foundation
import CoreBluetooth

/// Central actor that manages all emulated Bluetooth devices and their interactions
public actor EmulatorBus {

    // MARK: - Singleton

    public static let shared = EmulatorBus()

    // MARK: - State

    private var centrals: [UUID: CentralRegistration] = [:]
    private var peripherals: [UUID: PeripheralRegistration] = [:]
    private var connections: [UUID: Set<UUID>] = [:]  // central UUID -> peripheral UUIDs
    private var scanningCentrals: Set<UUID> = []
    private var advertisingPeripherals: Set<UUID> = []
    private var configuration: EmulatorConfiguration = .default
    private var scanTasks: [UUID: Task<Void, Never>] = [:]
    private var connectionMTUs: [UUID: [UUID: Int]] = [:]  // central -> peripheral -> MTU
    private var writeWithoutResponseQueues: [UUID: [UUID: Int]] = [:]  // central -> peripheral -> count
    private var notificationQueues: [UUID: [CBUUID: Int]] = [:]  // peripheral -> characteristic UUID -> count
    private var connectionEventRegistrations: [UUID: [CBConnectionEventMatchingOption: Any]] = [:]  // central -> options
    private var pairedConnections: Set<ConnectionPair> = []  // paired central-peripheral pairs
    private var restorationData: [String: Data] = [:]  // restore identifier -> encoded state

    private struct ConnectionPair: Hashable {
        let centralIdentifier: UUID
        let peripheralIdentifier: UUID
    }

    // State Restoration structures
    public struct RestoredCentralState: Codable {
        public let centralIdentifier: UUID
        public let connectedPeripheralIdentifiers: [UUID]
        public let scanServices: [Data]?  // CBUUID encoded as Data
    }

    public struct RestoredPeripheralState: Codable {
        public let peripheralIdentifier: UUID
        public let isAdvertising: Bool
        public let advertisementData: [String: Data]  // Simplified for Codable
    }

    private struct CentralRegistration {
        weak var manager: EmulatedCBCentralManager?
        var scanServices: [CBUUID]?
        var scanOptions: [String: Any]?
        var discoveredPeripheralsDuringScan: Set<UUID>
        let identifier: UUID
    }

    private struct PeripheralRegistration {
        weak var manager: EmulatedCBPeripheralManager?
        var advertisementData: [String: Any]
        let identifier: UUID
    }

    private init() {}

    // MARK: - Configuration

    public func configure(_ configuration: EmulatorConfiguration) {
        self.configuration = configuration
    }

    public func getConfiguration() -> EmulatorConfiguration {
        configuration
    }

    // MARK: - Central Registration

    public func register(central: EmulatedCBCentralManager, identifier: UUID) {
        centrals[identifier] = CentralRegistration(
            manager: central,
            scanServices: nil,
            scanOptions: nil,
            discoveredPeripheralsDuringScan: [],
            identifier: identifier
        )
    }

    public func unregister(centralIdentifier: UUID) {
        // Cancel scan task if active
        scanTasks[centralIdentifier]?.cancel()
        scanTasks.removeValue(forKey: centralIdentifier)

        centrals.removeValue(forKey: centralIdentifier)
        scanningCentrals.remove(centralIdentifier)
        connections.removeValue(forKey: centralIdentifier)
        connectionMTUs.removeValue(forKey: centralIdentifier)
        writeWithoutResponseQueues.removeValue(forKey: centralIdentifier)
    }

    // MARK: - Peripheral Registration

    public func register(peripheral: EmulatedCBPeripheralManager, identifier: UUID) {
        peripherals[identifier] = PeripheralRegistration(
            manager: peripheral,
            advertisementData: [:],
            identifier: identifier
        )
    }

    public func unregister(peripheralIdentifier: UUID) {
        peripherals.removeValue(forKey: peripheralIdentifier)
        advertisingPeripherals.remove(peripheralIdentifier)
        notificationQueues.removeValue(forKey: peripheralIdentifier)

        // Remove from all central connections
        for (centralId, var connectedPeripherals) in connections {
            connectedPeripherals.remove(peripheralIdentifier)
            connections[centralId] = connectedPeripherals
        }
    }

    // MARK: - Scanning

    public func startScanning(centralIdentifier: UUID, services: [CBUUID]?, options: [String: Any]?) {
        scanningCentrals.insert(centralIdentifier)

        // Update central registration with scan parameters
        if var registration = centrals[centralIdentifier] {
            registration.scanServices = services
            registration.scanOptions = options
            registration.discoveredPeripheralsDuringScan = []
            centrals[centralIdentifier] = registration
        }

        // Start periodic discovery notifications
        let task = Task {
            await scheduleDiscoveryNotifications(for: centralIdentifier)
        }
        scanTasks[centralIdentifier] = task
    }

    public func stopScanning(centralIdentifier: UUID) {
        scanningCentrals.remove(centralIdentifier)
        scanTasks[centralIdentifier]?.cancel()
        scanTasks.removeValue(forKey: centralIdentifier)

        // Clear discovered peripherals tracking
        if var registration = centrals[centralIdentifier] {
            registration.discoveredPeripheralsDuringScan = []
            centrals[centralIdentifier] = registration
        }
    }

    private func scheduleDiscoveryNotifications(for centralIdentifier: UUID) async {
        while scanningCentrals.contains(centralIdentifier) {
            // Get scanning central
            guard var centralReg = centrals[centralIdentifier],
                  let central = centralReg.manager else {
                return
            }

            // Check if allowDuplicates is enabled
            let allowDuplicates = configuration.honorAllowDuplicatesOption &&
                (centralReg.scanOptions?[CBCentralManagerScanOptionAllowDuplicatesKey] as? Bool ?? false)

            // Find advertising peripherals that match scan criteria
            for peripheralId in advertisingPeripherals {
                guard let peripheralReg = peripherals[peripheralId],
                      let peripheralManager = peripheralReg.manager else {
                    continue
                }

                // Check service filter
                if let scanServices = centralReg.scanServices {
                    if let advertisedServices = peripheralReg.advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
                        // Must have at least one matching service
                        let hasMatch = advertisedServices.contains { scanServices.contains($0) }
                        if !hasMatch {
                            continue
                        }
                    } else {
                        // Filtering for services but peripheral doesn't advertise any
                        continue
                    }
                }

                // Check for solicited service UUIDs if enabled
                if configuration.honorSolicitedServiceUUIDs,
                   let solicitedServices = centralReg.scanOptions?[CBCentralManagerScanOptionSolicitedServiceUUIDsKey] as? [CBUUID],
                   !solicitedServices.isEmpty {
                    if let advertisedSolicitedServices = peripheralReg.advertisementData[CBAdvertisementDataSolicitedServiceUUIDsKey] as? [CBUUID] {
                        // Must have at least one matching solicited service
                        let hasMatch = advertisedSolicitedServices.contains { solicitedServices.contains($0) }
                        if !hasMatch {
                            continue
                        }
                    } else {
                        // No solicited services advertised, skip
                        continue
                    }
                }

                // Check if we should skip duplicates
                if !allowDuplicates && centralReg.discoveredPeripheralsDuringScan.contains(peripheralId) {
                    continue
                }

                // Mark as discovered if not allowing duplicates
                if !allowDuplicates {
                    centralReg.discoveredPeripheralsDuringScan.insert(peripheralId)
                    centrals[centralIdentifier] = centralReg
                }

                // Make a copy of advertisement data to avoid data races
                nonisolated(unsafe) let advData = peripheralReg.advertisementData

                // Create peripheral proxy with advertisement data
                let peripheral = await peripheralManager.createPeripheralProxy(for: central, advertisementData: advData)

                // Generate RSSI
                let rssi = generateRSSI()

                // Notify central
                await central.notifyDiscovery(
                    peripheral: peripheral,
                    advertisementData: advData,
                    rssi: NSNumber(value: rssi)
                )
            }

            // Schedule next discovery cycle
            try? await Task.sleep(nanoseconds: UInt64(configuration.scanDiscoveryInterval * 1_000_000_000))
        }
    }

    private func generateRSSI() -> Int {
        let range = configuration.rssiRange
        let base = Int.random(in: range)
        let variation = Int.random(in: -configuration.rssiVariation...configuration.rssiVariation)
        return max(range.lowerBound, min(range.upperBound, base + variation))
    }

    // MARK: - Advertising

    public func startAdvertising(peripheralIdentifier: UUID, data: [String: Any]) {
        advertisingPeripherals.insert(peripheralIdentifier)
        if var registration = peripherals[peripheralIdentifier] {
            registration.advertisementData = data
            peripherals[peripheralIdentifier] = registration
        }
    }

    public func stopAdvertising(peripheralIdentifier: UUID) {
        advertisingPeripherals.remove(peripheralIdentifier)
        if var registration = peripherals[peripheralIdentifier] {
            registration.advertisementData = [:]
            peripherals[peripheralIdentifier] = registration
        }
    }

    // MARK: - Connection Management

    public func connect(centralIdentifier: UUID, peripheralIdentifier: UUID) async throws {
        // Simulate connection delay
        if configuration.connectionDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(configuration.connectionDelay * 1_000_000_000))
        }

        // Simulate connection failure if configured
        if configuration.simulateConnectionFailure {
            if Double.random(in: 0...1) < configuration.connectionFailureRate {
                throw CBError(.connectionFailed)
            }
        }

        // Establish connection
        var connectedPeripherals = connections[centralIdentifier] ?? Set<UUID>()
        connectedPeripherals.insert(peripheralIdentifier)
        connections[centralIdentifier] = connectedPeripherals

        // Initialize MTU to default
        var centralMTUs = connectionMTUs[centralIdentifier] ?? [:]
        centralMTUs[peripheralIdentifier] = configuration.defaultMTU
        connectionMTUs[centralIdentifier] = centralMTUs

        // Fire connection event if registered and enabled
        if configuration.fireConnectionEvents,
           connectionEventRegistrations[centralIdentifier] != nil,
           let central = centrals[centralIdentifier]?.manager {
            await central.notifyConnectionEvent(
                event: .peerConnected,
                peripheralIdentifier: peripheralIdentifier
            )
        }
    }

    public func disconnect(centralIdentifier: UUID, peripheralIdentifier: UUID) async {
        // Simulate disconnection delay
        if configuration.disconnectionDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(configuration.disconnectionDelay * 1_000_000_000))
        }

        // Remove connection
        connections[centralIdentifier]?.remove(peripheralIdentifier)

        // Clean up MTU
        connectionMTUs[centralIdentifier]?.removeValue(forKey: peripheralIdentifier)

        // Clean up backpressure queues
        writeWithoutResponseQueues[centralIdentifier]?.removeValue(forKey: peripheralIdentifier)

        // Clean up pairing
        let pair = ConnectionPair(
            centralIdentifier: centralIdentifier,
            peripheralIdentifier: peripheralIdentifier
        )
        pairedConnections.remove(pair)

        // Notify peripheral manager about central disconnection
        if let peripheralReg = peripherals[peripheralIdentifier],
           let manager = peripheralReg.manager {
            await manager.notifyCentralDisconnected(centralIdentifier)
        }

        // Fire disconnection event if registered and enabled
        if configuration.fireConnectionEvents,
           connectionEventRegistrations[centralIdentifier] != nil,
           let central = centrals[centralIdentifier]?.manager {
            await central.notifyConnectionEvent(
                event: .peerDisconnected,
                peripheralIdentifier: peripheralIdentifier
            )
        }
    }

    public func isConnected(centralIdentifier: UUID, peripheralIdentifier: UUID) -> Bool {
        connections[centralIdentifier]?.contains(peripheralIdentifier) ?? false
    }

    // MARK: - Service Discovery

    public func discoverServices(
        peripheralIdentifier: UUID,
        serviceUUIDs: [CBUUID]?
    ) async throws -> [EmulatedCBService] {
        if configuration.serviceDiscoveryDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(configuration.serviceDiscoveryDelay * 1_000_000_000))
        }

        guard let peripheralReg = peripherals[peripheralIdentifier],
              let manager = peripheralReg.manager else {
            throw CBError(.unknownDevice)
        }

        return await manager.getServices(matching: serviceUUIDs)
    }

    // MARK: - Characteristic Discovery

    public func discoverCharacteristics(
        peripheralIdentifier: UUID,
        characteristicUUIDs: [CBUUID]?,
        for service: EmulatedCBService
    ) async throws -> [EmulatedCBCharacteristic] {
        if configuration.characteristicDiscoveryDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(configuration.characteristicDiscoveryDelay * 1_000_000_000))
        }

        guard let peripheralReg = peripherals[peripheralIdentifier],
              let manager = peripheralReg.manager else {
            throw CBError(.unknownDevice)
        }

        return await manager.getCharacteristics(matching: characteristicUUIDs, for: service)
    }

    // MARK: - Descriptor Discovery

    public func discoverDescriptors(
        peripheralIdentifier: UUID,
        for characteristic: EmulatedCBCharacteristic
    ) async throws -> [EmulatedCBDescriptor] {
        if configuration.descriptorDiscoveryDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(configuration.descriptorDiscoveryDelay * 1_000_000_000))
        }

        guard let peripheralReg = peripherals[peripheralIdentifier],
              let manager = peripheralReg.manager else {
            throw CBError(.unknownDevice)
        }

        return await manager.getDescriptors(for: characteristic)
    }

    // MARK: - Read Operations

    public func readValue(
        peripheralIdentifier: UUID,
        for characteristic: EmulatedCBCharacteristic,
        centralIdentifier: UUID
    ) async throws -> Data {
        // Check if connected
        guard isConnected(centralIdentifier: centralIdentifier, peripheralIdentifier: peripheralIdentifier) else {
            throw CBError(.notConnected)
        }

        // Check if pairing is required
        if requiresPairing(characteristic: characteristic) {
            if !isPaired(centralIdentifier: centralIdentifier, peripheralIdentifier: peripheralIdentifier) {
                // Attempt to pair
                try await pair(centralIdentifier: centralIdentifier, peripheralIdentifier: peripheralIdentifier)
            }
        }

        if configuration.readDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(configuration.readDelay * 1_000_000_000))
        }

        // Simulate read/write errors if configured
        if configuration.simulateReadWriteErrors {
            if Double.random(in: 0...1) < configuration.readWriteErrorRate {
                throw CBATTError(.readNotPermitted)
            }
        }

        guard let peripheralReg = peripherals[peripheralIdentifier],
              let manager = peripheralReg.manager else {
            throw CBError(.unknownDevice)
        }

        guard let central = centrals[centralIdentifier]?.manager else {
            throw CBError(.unknown)
        }

        return try await manager.handleRead(for: characteristic, from: central)
    }

    public func readValue(
        peripheralIdentifier: UUID,
        for descriptor: EmulatedCBDescriptor,
        centralIdentifier: UUID
    ) async throws -> Any {
        // Check if connected
        guard isConnected(centralIdentifier: centralIdentifier, peripheralIdentifier: peripheralIdentifier) else {
            throw CBError(.notConnected)
        }

        if configuration.readDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(configuration.readDelay * 1_000_000_000))
        }

        if configuration.simulateReadWriteErrors {
            if Double.random(in: 0...1) < configuration.readWriteErrorRate {
                throw CBATTError(.readNotPermitted)
            }
        }

        guard let peripheralReg = peripherals[peripheralIdentifier],
              let manager = peripheralReg.manager else {
            throw CBError(.unknownDevice)
        }

        guard let central = centrals[centralIdentifier]?.manager else {
            throw CBError(.unknown)
        }

        return try await manager.handleReadDescriptor(for: descriptor, from: central)
    }

    // MARK: - Write Operations

    public func writeValue(
        peripheralIdentifier: UUID,
        data: Data,
        for characteristic: EmulatedCBCharacteristic,
        type: CBCharacteristicWriteType,
        centralIdentifier: UUID
    ) async throws {
        // Check if connected
        guard isConnected(centralIdentifier: centralIdentifier, peripheralIdentifier: peripheralIdentifier) else {
            throw CBError(.notConnected)
        }

        // Check if pairing is required
        if requiresPairing(characteristic: characteristic) {
            if !isPaired(centralIdentifier: centralIdentifier, peripheralIdentifier: peripheralIdentifier) {
                // Attempt to pair
                try await pair(centralIdentifier: centralIdentifier, peripheralIdentifier: peripheralIdentifier)
            }
        }

        // Handle backpressure for write without response
        if type == .withoutResponse && configuration.simulateBackpressure {
            // Enqueue the write
            await enqueueWriteWithoutResponse(
                centralIdentifier: centralIdentifier,
                peripheralIdentifier: peripheralIdentifier
            )

            // Simulate processing delay and dequeue
            Task {
                let delay = await EmulatorBus.shared.getConfiguration().backpressureProcessingDelay
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                await dequeueWriteWithoutResponse(
                    centralIdentifier: centralIdentifier,
                    peripheralIdentifier: peripheralIdentifier
                )
            }
        }

        if type == .withResponse && configuration.writeDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(configuration.writeDelay * 1_000_000_000))
        }

        if configuration.simulateReadWriteErrors {
            if Double.random(in: 0...1) < configuration.readWriteErrorRate {
                throw CBATTError(.writeNotPermitted)
            }
        }

        guard let peripheralReg = peripherals[peripheralIdentifier],
              let manager = peripheralReg.manager else {
            throw CBError(.unknownDevice)
        }

        guard let central = centrals[centralIdentifier]?.manager else {
            throw CBError(.unknown)
        }

        try await manager.handleWrite(data: data, for: characteristic, type: type, from: central)
    }

    public func writeValue(
        peripheralIdentifier: UUID,
        data: Data,
        for descriptor: EmulatedCBDescriptor,
        centralIdentifier: UUID
    ) async throws {
        // Check if connected
        guard isConnected(centralIdentifier: centralIdentifier, peripheralIdentifier: peripheralIdentifier) else {
            throw CBError(.notConnected)
        }

        if configuration.writeDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(configuration.writeDelay * 1_000_000_000))
        }

        if configuration.simulateReadWriteErrors {
            if Double.random(in: 0...1) < configuration.readWriteErrorRate {
                throw CBATTError(.writeNotPermitted)
            }
        }

        guard let peripheralReg = peripherals[peripheralIdentifier],
              let manager = peripheralReg.manager else {
            throw CBError(.unknownDevice)
        }

        guard let central = centrals[centralIdentifier]?.manager else {
            throw CBError(.unknown)
        }

        try await manager.handleWriteDescriptor(data: data, for: descriptor, from: central)
    }

    // MARK: - Notifications

    public func setNotifyValue(
        peripheralIdentifier: UUID,
        enabled: Bool,
        for characteristic: EmulatedCBCharacteristic,
        centralIdentifier: UUID
    ) async throws {
        // Check if connected
        guard isConnected(centralIdentifier: centralIdentifier, peripheralIdentifier: peripheralIdentifier) else {
            throw CBError(.notConnected)
        }

        guard let peripheralReg = peripherals[peripheralIdentifier],
              let manager = peripheralReg.manager else {
            throw CBError(.unknownDevice)
        }

        guard let central = centrals[centralIdentifier]?.manager else {
            throw CBError(.unknown)
        }

        try await manager.handleSetNotifyValue(enabled, for: characteristic, from: central)
    }

    public func sendNotification(
        from peripheralIdentifier: UUID,
        value: Data,
        for characteristic: EmulatedCBCharacteristic,
        to centralIdentifiers: [UUID]?
    ) async -> Bool {
        // Check if characteristic is notifying
        guard characteristic.isNotifying else {
            return false
        }

        // Handle backpressure for notifications
        if configuration.simulateBackpressure {
            guard canSendNotification(
                peripheralIdentifier: peripheralIdentifier,
                characteristicUUID: characteristic.uuid
            ) else {
                return false  // Queue full
            }

            // Enqueue the notification
            await enqueueNotification(
                peripheralIdentifier: peripheralIdentifier,
                characteristicUUID: characteristic.uuid
            )

            // Simulate processing delay and dequeue
            Task {
                let delay = await EmulatorBus.shared.getConfiguration().backpressureProcessingDelay
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                await dequeueNotification(
                    peripheralIdentifier: peripheralIdentifier,
                    characteristicUUID: characteristic.uuid
                )
            }
        }

        if configuration.notificationDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(configuration.notificationDelay * 1_000_000_000))
        }

        // Find centrals to notify
        let targetCentrals: [UUID]
        if let centralIdentifiers = centralIdentifiers {
            // Use provided central identifiers
            targetCentrals = centralIdentifiers
        } else {
            // Use subscribed centrals if available (must be EmulatedCBMutableCharacteristic)
            if let mutableChar = characteristic as? EmulatedCBMutableCharacteristic,
               let subscribedCentrals = mutableChar.subscribedCentrals {
                targetCentrals = subscribedCentrals.map { $0.identifier }
            } else {
                // Fallback: Get all centrals connected to this peripheral
                targetCentrals = connections
                    .filter { $0.value.contains(peripheralIdentifier) }
                    .map { $0.key }
            }
        }

        for centralId in targetCentrals {
            guard let central = centrals[centralId]?.manager else { continue }

            await central.notifyValueUpdate(
                peripheralIdentifier: peripheralIdentifier,
                value: value,
                for: characteristic
            )
        }

        return true
    }

    // MARK: - RSSI

    public func readRSSI(peripheralIdentifier: UUID) async -> Int {
        generateRSSI()
    }

    // MARK: - MTU Management

    public func negotiateMTU(
        centralIdentifier: UUID,
        peripheralIdentifier: UUID,
        requestedMTU: Int
    ) async -> Int {
        let negotiated = min(requestedMTU, configuration.maximumMTU)
        var centralMTUs = connectionMTUs[centralIdentifier] ?? [:]
        centralMTUs[peripheralIdentifier] = negotiated
        connectionMTUs[centralIdentifier] = centralMTUs
        return negotiated
    }

    public func getMTU(
        centralIdentifier: UUID,
        peripheralIdentifier: UUID
    ) -> Int {
        return connectionMTUs[centralIdentifier]?[peripheralIdentifier] ?? configuration.defaultMTU
    }

    // MARK: - Backpressure Management

    public func canSendWriteWithoutResponse(
        centralIdentifier: UUID,
        peripheralIdentifier: UUID
    ) -> Bool {
        guard configuration.simulateBackpressure else { return true }
        let count = writeWithoutResponseQueues[centralIdentifier]?[peripheralIdentifier] ?? 0
        return count < configuration.maxWriteWithoutResponseQueue
    }

    public func enqueueWriteWithoutResponse(
        centralIdentifier: UUID,
        peripheralIdentifier: UUID
    ) async {
        guard configuration.simulateBackpressure else { return }

        var centralQueues = writeWithoutResponseQueues[centralIdentifier] ?? [:]
        let current = centralQueues[peripheralIdentifier] ?? 0
        centralQueues[peripheralIdentifier] = current + 1
        writeWithoutResponseQueues[centralIdentifier] = centralQueues
    }

    public func dequeueWriteWithoutResponse(
        centralIdentifier: UUID,
        peripheralIdentifier: UUID
    ) async {
        guard configuration.simulateBackpressure else { return }

        var centralQueues = writeWithoutResponseQueues[centralIdentifier] ?? [:]
        if let current = centralQueues[peripheralIdentifier], current > 0 {
            centralQueues[peripheralIdentifier] = current - 1
            writeWithoutResponseQueues[centralIdentifier] = centralQueues

            // Notify peripheral ready if queue has space now
            if current == configuration.maxWriteWithoutResponseQueue {
                // Queue was full, now has space - notify central
                if let central = centrals[centralIdentifier]?.manager {
                    await central.notifyPeripheralReady(peripheralIdentifier: peripheralIdentifier)
                }
            }
        }
    }

    public func canSendNotification(
        peripheralIdentifier: UUID,
        characteristicUUID: CBUUID
    ) -> Bool {
        guard configuration.simulateBackpressure else { return true }
        let count = notificationQueues[peripheralIdentifier]?[characteristicUUID] ?? 0
        return count < configuration.maxNotificationQueue
    }

    public func enqueueNotification(
        peripheralIdentifier: UUID,
        characteristicUUID: CBUUID
    ) async {
        guard configuration.simulateBackpressure else { return }

        var peripheralQueues = notificationQueues[peripheralIdentifier] ?? [:]
        let current = peripheralQueues[characteristicUUID] ?? 0
        peripheralQueues[characteristicUUID] = current + 1
        notificationQueues[peripheralIdentifier] = peripheralQueues
    }

    public func dequeueNotification(
        peripheralIdentifier: UUID,
        characteristicUUID: CBUUID
    ) async {
        guard configuration.simulateBackpressure else { return }

        var peripheralQueues = notificationQueues[peripheralIdentifier] ?? [:]
        if let current = peripheralQueues[characteristicUUID], current > 0 {
            peripheralQueues[characteristicUUID] = current - 1
            notificationQueues[peripheralIdentifier] = peripheralQueues

            // Notify peripheral manager ready if queue has space now
            if current == configuration.maxNotificationQueue {
                // Queue was full, now has space
                if let peripheral = peripherals[peripheralIdentifier]?.manager {
                    await peripheral.notifyReadyToUpdateSubscribers()
                }
            }
        }
    }

    // MARK: - Connection Events

    public func registerForConnectionEvents(
        centralIdentifier: UUID,
        options: [CBConnectionEventMatchingOption: Any]?
    ) {
        connectionEventRegistrations[centralIdentifier] = options ?? [:]
    }

    private func fireConnectionEvent(
        _ event: CBConnectionEvent,
        centralIdentifier: UUID,
        peripheralIdentifier: UUID
    ) async {
        // Only fire if central is registered for connection events
        guard connectionEventRegistrations[centralIdentifier] != nil else {
            return
        }

        // Check if event matches options (if any)
        // For now, we fire all events. In real CoreBluetooth, options can filter by service UUIDs

        if let central = centrals[centralIdentifier]?.manager {
            await central.notifyConnectionEvent(
                event: event,
                peripheralIdentifier: peripheralIdentifier
            )
        }
    }

    // MARK: - Security & Pairing

    public func requiresPairing(characteristic: EmulatedCBCharacteristic) -> Bool {
        return configuration.requirePairing &&
               (characteristic.properties.contains(.authenticatedSignedWrites) ||
                characteristic.permissions.contains(.readEncryptionRequired) ||
                characteristic.permissions.contains(.writeEncryptionRequired))
    }

    public func isPaired(
        centralIdentifier: UUID,
        peripheralIdentifier: UUID
    ) -> Bool {
        let pair = ConnectionPair(
            centralIdentifier: centralIdentifier,
            peripheralIdentifier: peripheralIdentifier
        )
        return pairedConnections.contains(pair)
    }

    public func pair(
        centralIdentifier: UUID,
        peripheralIdentifier: UUID
    ) async throws {
        guard configuration.simulatePairing else {
            // Pairing simulation disabled, automatically succeed
            let pair = ConnectionPair(
                centralIdentifier: centralIdentifier,
                peripheralIdentifier: peripheralIdentifier
            )
            pairedConnections.insert(pair)
            return
        }

        // Simulate pairing delay
        if configuration.pairingDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(configuration.pairingDelay * 1_000_000_000))
        }

        // Check if pairing should succeed
        guard configuration.pairingSucceeds else {
            throw CBATTError(.insufficientAuthentication)
        }

        // Add to paired connections
        let pair = ConnectionPair(
            centralIdentifier: centralIdentifier,
            peripheralIdentifier: peripheralIdentifier
        )
        pairedConnections.insert(pair)
    }

    // MARK: - State Restoration

    public func saveStateForRestoration<T: Codable>(
        identifier: String,
        state: T
    ) throws {
        guard configuration.stateRestorationEnabled else { return }

        let data = try JSONEncoder().encode(state)
        restorationData[identifier] = data
    }

    public func restoreState<T: Codable>(
        identifier: String,
        as type: T.Type
    ) throws -> T? {
        guard configuration.stateRestorationEnabled else { return nil }
        guard let data = restorationData[identifier] else { return nil }

        return try JSONDecoder().decode(type, from: data)
    }

    public func saveCentralState(
        centralIdentifier: UUID,
        restoreIdentifier: String
    ) async throws {
        guard configuration.stateRestorationEnabled else { return }

        // Collect central state
        let connectedPeripherals = connections[centralIdentifier] ?? []
        let scanServices = centrals[centralIdentifier]?.scanServices

        let state = RestoredCentralState(
            centralIdentifier: centralIdentifier,
            connectedPeripheralIdentifiers: Array(connectedPeripherals),
            scanServices: scanServices?.map { $0.data }
        )

        try saveStateForRestoration(identifier: restoreIdentifier, state: state)
    }

    public func savePeripheralState(
        peripheralIdentifier: UUID,
        restoreIdentifier: String
    ) async throws {
        guard configuration.stateRestorationEnabled else { return }

        // Collect peripheral state
        guard let peripheralReg = peripherals[peripheralIdentifier] else { return }

        // Convert advertisement data to Codable format
        var codableAdvData: [String: Data] = [:]
        for (key, value) in peripheralReg.advertisementData {
            if let data = value as? Data {
                codableAdvData[key] = data
            } else if let string = value as? String {
                codableAdvData[key] = string.data(using: .utf8) ?? Data()
            } else if let number = value as? NSNumber {
                codableAdvData[key] = "\(number)".data(using: .utf8) ?? Data()
            }
        }

        let state = RestoredPeripheralState(
            peripheralIdentifier: peripheralIdentifier,
            isAdvertising: advertisingPeripherals.contains(peripheralIdentifier),
            advertisementData: codableAdvData
        )

        try saveStateForRestoration(identifier: restoreIdentifier, state: state)
    }

    // MARK: - Utility

    public func getAllCentrals() -> [UUID] {
        Array(centrals.keys)
    }

    public func getAllPeripherals() -> [UUID] {
        Array(peripherals.keys)
    }

    public func getConnectedPeripherals(for centralIdentifier: UUID) -> [UUID] {
        Array(connections[centralIdentifier] ?? [])
    }

    public func reset() {
        // Cancel all scan tasks
        for task in scanTasks.values {
            task.cancel()
        }
        scanTasks.removeAll()

        centrals.removeAll()
        peripherals.removeAll()
        connections.removeAll()
        scanningCentrals.removeAll()
        advertisingPeripherals.removeAll()
        connectionMTUs.removeAll()
        writeWithoutResponseQueues.removeAll()
        notificationQueues.removeAll()
        configuration = .default
    }
}
