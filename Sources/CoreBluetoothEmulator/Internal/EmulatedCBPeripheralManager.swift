import Foundation
import CoreBluetooth

/// Emulated CBPeripheralManager class
public class EmulatedCBPeripheralManager: NSObject, @unchecked Sendable {
    public weak var delegate: (any EmulatedCBPeripheralManagerDelegate)?
    public private(set) var state: CBManagerState = .unknown
    public private(set) var isAdvertising: Bool = false

    private let queue: DispatchQueue?
    public let identifier = UUID()
    private var services: [CBUUID: EmulatedCBMutableService] = [:]
    private var characteristics: [CBUUID: EmulatedCBMutableCharacteristic] = [:]
    private let options: [String: Any]?
    private var restoreIdentifier: String?
    private var notificationQueue: [CBUUID: Int] = [:]  // Characteristic UUID -> pending count
    private let maxNotificationQueueSize = 10  // Match CoreBluetooth's typical queue size

    // MARK: - Initialization

    public init(
        delegate: (any EmulatedCBPeripheralManagerDelegate)?,
        queue: DispatchQueue?,
        options: [String: Any]? = nil
    ) {
        self.delegate = delegate
        self.queue = queue
        self.options = options

        // Extract restore identifier if present
        if let options = options,
           let restoreId = options[CBPeripheralManagerOptionRestoreIdentifierKey] as? String {
            self.restoreIdentifier = restoreId
        }

        super.init()

        Task {
            await EmulatorBus.shared.register(peripheral: self, identifier: identifier)

            // Call state restoration delegate method if restore identifier was provided
            if let restoreId = restoreIdentifier, delegate != nil {
                do {
                    // Try to restore state from EmulatorBus
                    if let restoredState = try await EmulatorBus.shared.restoreState(
                        identifier: restoreId,
                        as: EmulatorBus.RestoredPeripheralState.self
                    ) {
                        // Build restoration dictionary
                        var restorationDict: [String: Any] = [:]

                        // Restore advertisement data
                        if !restoredState.advertisementData.isEmpty {
                            // Convert Data back to original types
                            var advData: [String: Any] = [:]
                            for (key, data) in restoredState.advertisementData {
                                // Try to decode as string first, otherwise keep as Data
                                if let string = String(data: data, encoding: .utf8), !string.isEmpty {
                                    advData[key] = string
                                } else {
                                    advData[key] = data
                                }
                            }
                            restorationDict[CBPeripheralManagerRestoredStateAdvertisementDataKey] = advData
                        }

                        // Restore services array (empty for now, as services are typically re-added by app)
                        // Note: In real CoreBluetooth, services are restored here, but apps typically
                        // re-add services in the willRestoreState callback
                        restorationDict[CBPeripheralManagerRestoredStateServicesKey] = [EmulatedCBMutableService]()

                        // Restore advertising state by restarting if was advertising
                        if restoredState.isAdvertising, !restoredState.advertisementData.isEmpty {
                            var advData: [String: Any] = [:]
                            for (key, data) in restoredState.advertisementData {
                                if let string = String(data: data, encoding: .utf8), !string.isEmpty {
                                    advData[key] = string
                                } else {
                                    advData[key] = data
                                }
                            }
                            // Will restart advertising after delegate callback
                            Task { @MainActor [weak self] in
                                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
                                self?.startAdvertising(advData)
                            }
                        }

                        // Notify delegate with restored state
                        nonisolated(unsafe) let restoreDict = restorationDict
                        notifyDelegate { delegate in
                            delegate.peripheralManager(self, willRestoreState: restoreDict)
                        }
                    } else {
                        // No saved state, notify with empty dict
                        notifyDelegate { delegate in
                            delegate.peripheralManager(self, willRestoreState: [:])
                        }
                    }
                } catch {
                    // Error restoring state, notify with empty dict
                    notifyDelegate { delegate in
                        delegate.peripheralManager(self, willRestoreState: [:])
                    }
                }
            }

            await transitionToPoweredOn()
        }
    }

    deinit {
        let id = identifier
        Task {
            await EmulatorBus.shared.unregister(peripheralIdentifier: id)
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
            delegate.peripheralManagerDidUpdateState(self)
        }
    }

    // MARK: - Service Management

    public func add(_ service: EmulatedCBMutableService) {
        services[service.uuid] = service

        // Index all characteristics
        if let characteristics = service.characteristics as? [EmulatedCBMutableCharacteristic] {
            for characteristic in characteristics {
                self.characteristics[characteristic.uuid] = characteristic
            }
        }

        notifyDelegate { delegate in
            delegate.peripheralManager(self, didAdd: service, error: nil)
        }
    }

    public func remove(_ service: EmulatedCBMutableService) {
        services.removeValue(forKey: service.uuid)

        // Remove characteristics
        if let characteristics = service.characteristics as? [EmulatedCBMutableCharacteristic] {
            for characteristic in characteristics {
                self.characteristics.removeValue(forKey: characteristic.uuid)
            }
        }
    }

    public func removeAllServices() {
        services.removeAll()
        characteristics.removeAll()
    }

    // MARK: - Advertising

    public func startAdvertising(_ advertisementData: [String: Any]?) {
        guard state == .poweredOn else { return }

        isAdvertising = true

        // Make a copy to avoid data races
        nonisolated(unsafe) let advData = advertisementData ?? [:]

        Task {
            await EmulatorBus.shared.startAdvertising(
                peripheralIdentifier: identifier,
                data: advData
            )

            notifyDelegate { delegate in
                delegate.peripheralManagerDidStartAdvertising(self, error: nil)
            }
        }
    }

    public func stopAdvertising() {
        guard isAdvertising else { return }

        isAdvertising = false

        Task {
            await EmulatorBus.shared.stopAdvertising(peripheralIdentifier: identifier)
        }
    }

    // MARK: - Value Updates

    @discardableResult
    public func updateValue(
        _ value: Data,
        for characteristic: EmulatedCBMutableCharacteristic,
        onSubscribedCentrals centrals: [EmulatedCBCentral]?
    ) -> Bool {
        // Check if queue is full
        let currentQueueSize = notificationQueue[characteristic.uuid] ?? 0
        if currentQueueSize >= maxNotificationQueueSize {
            return false  // Queue full, cannot send
        }

        // Update the characteristic value
        characteristic.setValue(value)

        // Enqueue notification
        notificationQueue[characteristic.uuid] = currentQueueSize + 1

        // Send notification asynchronously
        Task {
            let centralIds = centrals?.map { $0.identifier } ?? characteristic.subscribedCentrals?.map { $0.identifier }
            let success = await EmulatorBus.shared.sendNotification(
                from: identifier,
                value: value,
                for: characteristic,
                to: centralIds
            )

            // Dequeue after sending
            Task { @MainActor in
                let count = self.notificationQueue[characteristic.uuid] ?? 0
                if count > 0 {
                    self.notificationQueue[characteristic.uuid] = count - 1
                }

                // Notify delegate that queue has space again
                if count == self.maxNotificationQueueSize && success {
                    self.notifyDelegate { delegate in
                        delegate.peripheralManagerIsReady(toUpdateSubscribers: self)
                    }
                }
            }
        }

        // Return true if successfully queued
        return true
    }

    // MARK: - Request Handling

    public func respond(to request: EmulatedCBATTRequest, withResult result: CBATTError.Code) {
        // In a real implementation, this would send the response back to the central
        // For now, we just acknowledge it
    }

    // MARK: - Connection Latency

    public func setDesiredConnectionLatency(_ latency: CBPeripheralManagerConnectionLatency, for central: EmulatedCBCentral) {
        // Not implemented for emulator
    }

    // MARK: - L2CAP Channels

    @available(iOS 11.0, macOS 10.13, tvOS 11.0, watchOS 4.0, *)
    public func publishL2CAPChannel(withEncryption encryptionRequired: Bool) {
        guard state == .poweredOn else { return }

        Task {
            do {
                let psm = try await EmulatorBus.shared.publishL2CAPChannel(
                    peripheralIdentifier: identifier,
                    encryptionRequired: encryptionRequired
                )

                notifyDelegate { delegate in
                    delegate.peripheralManager(self, didPublishL2CAPChannel: psm, error: nil)
                }
            } catch {
                notifyDelegate { delegate in
                    delegate.peripheralManager(self, didPublishL2CAPChannel: 0, error: error)
                }
            }
        }
    }

    @available(iOS 11.0, macOS 10.13, tvOS 11.0, watchOS 4.0, *)
    public func unpublishL2CAPChannel(_ psm: CBL2CAPPSM) {
        Task {
            await EmulatorBus.shared.unpublishL2CAPChannel(
                peripheralIdentifier: identifier,
                psm: psm
            )

            notifyDelegate { delegate in
                delegate.peripheralManager(self, didUnpublishL2CAPChannel: psm, error: nil)
            }
        }
    }

    @available(iOS 11.0, macOS 10.13, tvOS 11.0, watchOS 4.0, *)
    internal func notifyL2CAPChannelOpened(_ channel: EmulatedCBL2CAPChannel) async {
        let centralProxy = EmulatedCBCentral(identifier: channel.peer.identifier)

        notifyDelegate { delegate in
            delegate.peripheralManager(self, didOpen: channel, error: nil)
        }
    }

    // MARK: - Authorization

    public class func authorizationStatus() -> CBPeripheralManagerAuthorizationStatus {
        return .authorized
    }

    @available(iOS 13.1, *)
    internal func notifyANCSAuthorizationUpdate(for centralIdentifier: UUID) async {
        let status = await EmulatorBus.shared.getANCSAuthorization(for: centralIdentifier)
        let centralProxy = EmulatedCBCentral(identifier: centralIdentifier)

        notifyDelegate { delegate in
            delegate.peripheralManager(self, didUpdateANCSAuthorizationFor: centralProxy)
        }
    }

    // MARK: - Internal Methods (called by EmulatorBus)

    internal func getServices(matching serviceUUIDs: [CBUUID]?) -> [EmulatedCBService] {
        let allServices = Array(services.values)

        guard let serviceUUIDs = serviceUUIDs else {
            return allServices
        }

        return allServices.filter { service in
            serviceUUIDs.contains(service.uuid)
        }
    }

    internal func getCharacteristics(
        matching characteristicUUIDs: [CBUUID]?,
        for service: EmulatedCBService
    ) -> [EmulatedCBCharacteristic] {
        guard let allCharacteristics = service.characteristics else {
            return []
        }

        guard let characteristicUUIDs = characteristicUUIDs else {
            return allCharacteristics
        }

        return allCharacteristics.filter { characteristic in
            characteristicUUIDs.contains(characteristic.uuid)
        }
    }

    internal func getDescriptors(for characteristic: EmulatedCBCharacteristic) -> [EmulatedCBDescriptor] {
        characteristic.descriptors ?? []
    }

    internal func handleRead(
        for characteristic: EmulatedCBCharacteristic,
        from central: EmulatedCBCentralManager
    ) async throws -> Data {
        // Check permissions
        guard characteristic.permissions.contains(.readable) else {
            throw CBATTError(.readNotPermitted)
        }

        // Create ATT request
        let centralProxy = EmulatedCBCentral(identifier: central.identifier)
        let request = EmulatedCBATTRequest(
            central: centralProxy,
            characteristic: characteristic,
            offset: 0
        )

        // Notify delegate
        notifyDelegate { delegate in
            delegate.peripheralManager(self, didReceiveRead: request)
        }

        // Return current value
        return characteristic.value ?? Data()
    }

    internal func handleWrite(
        data: Data,
        for characteristic: EmulatedCBCharacteristic,
        type: CBCharacteristicWriteType,
        from central: EmulatedCBCentralManager
    ) async throws {
        // Check permissions
        guard characteristic.permissions.contains(.writeable) else {
            throw CBATTError(.writeNotPermitted)
        }

        // Create ATT request
        let centralProxy = EmulatedCBCentral(identifier: central.identifier)
        let request = EmulatedCBATTRequest(
            central: centralProxy,
            characteristic: characteristic,
            offset: 0
        )
        request.value = data

        // Notify delegate
        notifyDelegate { delegate in
            delegate.peripheralManager(self, didReceiveWrite: [request])
        }

        // Update value
        characteristic.setValue(data)
    }

    internal func handleReadDescriptor(
        for descriptor: EmulatedCBDescriptor,
        from central: EmulatedCBCentralManager
    ) async throws -> Any {
        // Check permissions
        guard descriptor.permissions.contains(.readable) else {
            throw CBATTError(.readNotPermitted)
        }

        return descriptor.value ?? Data()
    }

    internal func handleWriteDescriptor(
        data: Data,
        for descriptor: EmulatedCBDescriptor,
        from central: EmulatedCBCentralManager
    ) async throws {
        // Check permissions
        guard descriptor.permissions.contains(.writeable) else {
            throw CBATTError(.writeNotPermitted)
        }

        descriptor.setValue(data)
    }

    internal func handleSetNotifyValue(
        _ enabled: Bool,
        for characteristic: EmulatedCBCharacteristic,
        from central: EmulatedCBCentralManager
    ) async throws {
        // Check if characteristic is mutable
        guard let mutableCharacteristic = characteristic as? EmulatedCBMutableCharacteristic else {
            throw CBATTError(.requestNotSupported)
        }

        // Check if characteristic supports notifications or indications
        let supportsNotify = characteristic.properties.contains(.notify)
        let supportsIndicate = characteristic.properties.contains(.indicate)

        guard supportsNotify || supportsIndicate else {
            throw CBATTError(.requestNotSupported)
        }

        // Check if peripheral is advertising (connected state)
        guard state == .poweredOn else {
            throw CBATTError(.unlikelyError)
        }

        let centralProxy = EmulatedCBCentral(identifier: central.identifier)

        if enabled {
            mutableCharacteristic.addSubscribedCentral(centralProxy)

            notifyDelegate { delegate in
                delegate.peripheralManager(
                    self,
                    central: centralProxy,
                    didSubscribeTo: characteristic
                )
            }
        } else {
            mutableCharacteristic.removeSubscribedCentral(centralProxy)

            notifyDelegate { delegate in
                delegate.peripheralManager(
                    self,
                    central: centralProxy,
                    didUnsubscribeFrom: characteristic
                )
            }
        }

        characteristic.setNotifying(enabled)
    }

    internal func notifyCentralDisconnected(_ centralIdentifier: UUID) async {
        // Find all subscribed characteristics for this central
        for service in services.values {
            guard let characteristics = service.characteristics as? [EmulatedCBMutableCharacteristic] else {
                continue
            }

            for characteristic in characteristics {
                guard let subscribers = characteristic.subscribedCentrals else {
                    continue
                }

                // Find the central in subscribers
                if let central = subscribers.first(where: { $0.identifier == centralIdentifier }) {
                    // Remove subscription
                    characteristic.removeSubscribedCentral(central)

                    // Update notifying state if no more subscribers
                    if characteristic.subscribedCentrals?.isEmpty ?? true {
                        characteristic.setNotifying(false)
                    }

                    // Notify delegate
                    notifyDelegate { delegate in
                        delegate.peripheralManager(
                            self,
                            central: central,
                            didUnsubscribeFrom: characteristic
                        )
                    }
                }
            }
        }
    }

    internal func createPeripheralProxy(for central: EmulatedCBCentralManager, advertisementData: [String: Any]) -> EmulatedCBPeripheral {
        // Extract name from advertisement data
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String

        return EmulatedCBPeripheral(
            identifier: identifier,  // Use peripheralManager's identifier for consistency
            name: name,
            peripheralManagerIdentifier: identifier,
            centralManagerIdentifier: central.identifier,
            queue: queue
        )
    }

    internal func notifyReadyToUpdateSubscribers() async {
        // Notify delegate that peripheral is ready to send more updates
        notifyDelegate { delegate in
            delegate.peripheralManagerIsReady(toUpdateSubscribers: self)
        }
    }

    // MARK: - Delegate Notification Helper

    private func notifyDelegate(_ block: @escaping @Sendable (any EmulatedCBPeripheralManagerDelegate) -> Void) {
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
