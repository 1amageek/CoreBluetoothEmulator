import Foundation
import CoreBluetooth

/// Emulated CBCentralManager class
public class EmulatedCBCentralManager: NSObject, @unchecked Sendable {
    public weak var delegate: (any EmulatedCBCentralManagerDelegate)?
    public private(set) var state: CBManagerState = .unknown
    public private(set) var isScanning: Bool = false

    private let queue: DispatchQueue?
    internal let identifier = UUID()
    private var discoveredPeripherals: [UUID: EmulatedCBPeripheral] = [:]
    private var peripheralDelegateQueues: [UUID: DispatchQueue?] = [:]
    private let options: [String: Any]?
    private var restoreIdentifier: String?
    private var registeredForConnectionEvents: Bool = false
    private var connectionEventMatchingOptions: [CBConnectionEventMatchingOption: Any]?

    // MARK: - Initialization

    public init(
        delegate: (any EmulatedCBCentralManagerDelegate)?,
        queue: DispatchQueue?,
        options: [String: Any]? = nil
    ) {
        self.delegate = delegate
        self.queue = queue
        self.options = options

        // Extract restore identifier if present
        if let options = options,
           let restoreId = options[CBCentralManagerOptionRestoreIdentifierKey] as? String {
            self.restoreIdentifier = restoreId
        }

        super.init()

        Task {
            await EmulatorBus.shared.register(central: self, identifier: identifier)

            // Call state restoration delegate method if restore identifier was provided
            if restoreIdentifier != nil, delegate != nil {
                // TODO: Implement actual state restoration
                // For now, just notify delegate with empty dict
                notifyDelegate { delegate in
                    delegate.centralManager(self, willRestoreState: [:])
                }
            }

            await transitionToPoweredOn()
        }
    }

    deinit {
        let id = identifier
        Task {
            await EmulatorBus.shared.unregister(centralIdentifier: id)
        }
    }

    // MARK: - State Management

    private func transitionToPoweredOn() async {
        let config = await EmulatorBus.shared.getConfiguration()

        if config.stateUpdateDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(config.stateUpdateDelay * 1_000_000_000))
        }

        state = .poweredOn

        notifyDelegate { delegate in
            delegate.centralManagerDidUpdateState(self)
        }
    }

    // MARK: - Scanning

    public func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]? = nil) {
        guard state == .poweredOn else { return }

        isScanning = true

        Task {
            await EmulatorBus.shared.startScanning(
                centralIdentifier: identifier,
                services: serviceUUIDs,
                options: options
            )
        }
    }

    public func stopScan() {
        guard isScanning else { return }

        isScanning = false

        Task {
            await EmulatorBus.shared.stopScanning(centralIdentifier: identifier)
        }
    }

    // MARK: - Connection Management

    public func connect(_ peripheral: EmulatedCBPeripheral, options: [String: Any]? = nil) {
        guard state == .poweredOn else { return }

        // Store peripheral
        discoveredPeripherals[peripheral.identifier] = peripheral

        Task {
            do {
                try await EmulatorBus.shared.connect(
                    centralIdentifier: identifier,
                    peripheralIdentifier: peripheral.peripheralManagerIdentifier
                )

                peripheral.setState(.connected)

                // Update peripheral's MTU after connection
                let mtu = await EmulatorBus.shared.getMTU(
                    centralIdentifier: identifier,
                    peripheralIdentifier: peripheral.peripheralManagerIdentifier
                )
                peripheral.updateMTU(mtu)

                notifyDelegate { delegate in
                    delegate.centralManager(self, didConnect: peripheral)
                }
            } catch {
                notifyDelegate { delegate in
                    delegate.centralManager(self, didFailToConnect: peripheral, error: error)
                }
            }
        }
    }

    public func cancelPeripheralConnection(_ peripheral: EmulatedCBPeripheral) {
        Task {
            await EmulatorBus.shared.disconnect(
                centralIdentifier: identifier,
                peripheralIdentifier: peripheral.peripheralManagerIdentifier
            )

            peripheral.setState(.disconnected)

            notifyDelegate { delegate in
                delegate.centralManager(self, didDisconnectPeripheral: peripheral, error: nil)
            }
        }
    }

    // MARK: - Peripheral Retrieval

    public func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [EmulatedCBPeripheral] {
        identifiers.compactMap { discoveredPeripherals[$0] }
    }

    public func retrieveConnectedPeripherals(withServices serviceUUIDs: [CBUUID]) -> [EmulatedCBPeripheral] {
        // Return connected peripherals filtered by services
        return discoveredPeripherals.values.filter { peripheral in
            guard peripheral.state == .connected else { return false }

            // Filter by service UUIDs if specified
            guard let services = peripheral.services, !services.isEmpty else {
                return false
            }

            // Check if any of the requested services are present
            return services.contains { service in
                serviceUUIDs.contains(service.uuid)
            }
        }
    }

    // MARK: - Feature Support

    public class func supports(_ features: Feature) -> Bool {
        // For now, we support all features
        return true
    }

    public struct Feature: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let extendedScanAndConnect = Feature(rawValue: 1 << 0)
    }

    // MARK: - Connection Events (iOS 13+)

    @available(iOS 13.0, *)
    public func registerForConnectionEvents(options: [CBConnectionEventMatchingOption: Any]? = nil) {
        registeredForConnectionEvents = true
        connectionEventMatchingOptions = options

        Task<Void, Never> {
            await EmulatorBus.shared.registerForConnectionEvents(
                centralIdentifier: identifier,
                options: options
            )
        }
    }

    // MARK: - Internal Methods (called by EmulatorBus)

    @available(iOS 13.0, *)
    internal func notifyConnectionEvent(
        event: CBConnectionEvent,
        peripheralIdentifier: UUID
    ) async {
        guard registeredForConnectionEvents else { return }

        // Find the peripheral
        guard let peripheral = discoveredPeripherals.values.first(where: {
            $0.peripheralManagerIdentifier == peripheralIdentifier
        }) else {
            return
        }

        notifyDelegate { delegate in
            delegate.centralManager(self, connectionEventDidOccur: event, for: peripheral)
        }
    }

    internal func notifyDiscovery(
        peripheral: EmulatedCBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) async {
        // Store peripheral
        discoveredPeripherals[peripheral.identifier] = peripheral

        // Copy advertisement data to avoid Sendable issues
        nonisolated(unsafe) let advData = advertisementData
        let rssiValue = rssi

        notifyDelegate { delegate in
            delegate.centralManager(
                self,
                didDiscover: peripheral,
                advertisementData: advData,
                rssi: rssiValue
            )
        }
    }

    internal func notifyValueUpdate(peripheralIdentifier: UUID, value: Data, for characteristic: EmulatedCBCharacteristic) async {
        // Find the peripheral by its identifier
        guard let peripheral = discoveredPeripherals.values.first(where: {
            $0.peripheralManagerIdentifier == peripheralIdentifier
        }) else {
            return
        }

        peripheral.handleValueUpdate(value: value, for: characteristic)
    }

    internal func notifyPeripheralReady(peripheralIdentifier: UUID) async {
        // Find the peripheral
        guard let peripheral = discoveredPeripherals.values.first(where: {
            $0.peripheralManagerIdentifier == peripheralIdentifier
        }) else {
            return
        }

        // Update canSendWriteWithoutResponse
        peripheral.canSendWriteWithoutResponse = true

        // Notify delegate
        notifyDelegate { delegate in
            delegate.peripheralIsReady(toSendWriteWithoutResponse: peripheral)
        }
    }

    // MARK: - Delegate Notification Helper

    private func notifyDelegate(_ block: @escaping @Sendable (any EmulatedCBCentralManagerDelegate) -> Void) {
        if let queue = queue {
            queue.async { [weak self] in
                guard let self = self, let delegate = self.delegate else { return }
                block(delegate)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let delegate = self.delegate else { return }
                block(delegate)
            }
        }
    }
}
