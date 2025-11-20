import Foundation
import CoreBluetooth

/// Emulated CBPeripheral class (Central's view of a remote peripheral)
public class EmulatedCBPeripheral: NSObject, @unchecked Sendable {
    public let identifier: UUID
    public var name: String?
    public weak var delegate: (any EmulatedCBPeripheralDelegate)?
    public private(set) var state: CBPeripheralState = .disconnected
    public private(set) var services: [EmulatedCBService]?
    public var canSendWriteWithoutResponse: Bool = true

    /// The current MTU (Maximum Transmission Unit) for this peripheral connection
    /// Available on iOS 15.0+, macOS 12.0+, tvOS 15.0+, watchOS 8.0+
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    public var mtu: Int {
        return currentMTU
    }

    private let queue: DispatchQueue?
    internal let peripheralManagerIdentifier: UUID
    internal let centralManagerIdentifier: UUID
    private var currentMTU: Int = 185  // Default ATT MTU

    internal init(
        identifier: UUID,
        name: String?,
        peripheralManagerIdentifier: UUID,
        centralManagerIdentifier: UUID,
        queue: DispatchQueue?
    ) {
        self.identifier = identifier
        self.name = name
        self.peripheralManagerIdentifier = peripheralManagerIdentifier
        self.centralManagerIdentifier = centralManagerIdentifier
        self.queue = queue
        super.init()
    }

    // MARK: - State Management

    internal func setState(_ state: CBPeripheralState) {
        self.state = state
    }

    internal func setServices(_ services: [EmulatedCBService]) {
        self.services = services
        for service in services {
            service.peripheral = self
        }
    }

    internal func updateMTU(_ mtu: Int) {
        self.currentMTU = mtu
    }

    // MARK: - Service Discovery

    public func discoverServices(_ serviceUUIDs: [CBUUID]?) {
        nonisolated(unsafe) let uuids = serviceUUIDs
        Task {
            do {
                let services = try await EmulatorBus.shared.discoverServices(
                    peripheralIdentifier: peripheralManagerIdentifier,
                    serviceUUIDs: uuids
                )

                setServices(services)

                notifyDelegate { delegate in
                    delegate.peripheral(self, didDiscoverServices: nil)
                }
            } catch {
                notifyDelegate { delegate in
                    delegate.peripheral(self, didDiscoverServices: error)
                }
            }
        }
    }

    public func discoverIncludedServices(_ includedServiceUUIDs: [CBUUID]?, for service: EmulatedCBService) {
        nonisolated(unsafe) let uuids = includedServiceUUIDs
        Task {
            do {
                let config = await EmulatorBus.shared.getConfiguration()

                // Simulate discovery delay
                if config.serviceDiscoveryDelay > 0 {
                    try await Task.sleep(nanoseconds: UInt64(config.serviceDiscoveryDelay * 1_000_000_000))
                }

                // Get included services from the service
                // If specific UUIDs are requested, filter by them
                let allIncludedServices = service.includedServices ?? []
                let filteredServices: [EmulatedCBService]

                if let uuids = uuids, !uuids.isEmpty {
                    filteredServices = allIncludedServices.filter { includedService in
                        uuids.contains(includedService.uuid)
                    }
                } else {
                    filteredServices = allIncludedServices
                }

                // Set the included services
                service.setIncludedServices(filteredServices)

                notifyDelegate { delegate in
                    delegate.peripheral(self, didDiscoverIncludedServicesFor: service, error: nil)
                }
            } catch {
                notifyDelegate { delegate in
                    delegate.peripheral(self, didDiscoverIncludedServicesFor: service, error: error)
                }
            }
        }
    }

    // MARK: - Characteristic Discovery

    public func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: EmulatedCBService) {
        nonisolated(unsafe) let uuids = characteristicUUIDs
        Task {
            do {
                let characteristics = try await EmulatorBus.shared.discoverCharacteristics(
                    peripheralIdentifier: peripheralManagerIdentifier,
                    characteristicUUIDs: uuids,
                    for: service
                )

                service.setCharacteristics(characteristics)

                notifyDelegate { delegate in
                    delegate.peripheral(self, didDiscoverCharacteristicsFor: service, error: nil)
                }
            } catch {
                notifyDelegate { delegate in
                    delegate.peripheral(self, didDiscoverCharacteristicsFor: service, error: error)
                }
            }
        }
    }

    // MARK: - Descriptor Discovery

    public func discoverDescriptors(for characteristic: EmulatedCBCharacteristic) {
        Task {
            do {
                let descriptors = try await EmulatorBus.shared.discoverDescriptors(
                    peripheralIdentifier: peripheralManagerIdentifier,
                    for: characteristic
                )

                characteristic.setDescriptors(descriptors)

                notifyDelegate { delegate in
                    delegate.peripheral(self, didDiscoverDescriptorsFor: characteristic, error: nil)
                }
            } catch {
                notifyDelegate { delegate in
                    delegate.peripheral(self, didDiscoverDescriptorsFor: characteristic, error: error)
                }
            }
        }
    }

    // MARK: - Read Operations

    public func readValue(for characteristic: EmulatedCBCharacteristic) {
        Task {
            do {
                let value = try await EmulatorBus.shared.readValue(
                    peripheralIdentifier: peripheralManagerIdentifier,
                    for: characteristic,
                    centralIdentifier: centralManagerIdentifier
                )

                characteristic.setValue(value)

                notifyDelegate { delegate in
                    delegate.peripheral(self, didUpdateValueFor: characteristic, error: nil)
                }
            } catch {
                notifyDelegate { delegate in
                    delegate.peripheral(self, didUpdateValueFor: characteristic, error: error)
                }
            }
        }
    }

    public func readValue(for descriptor: EmulatedCBDescriptor) {
        Task {
            do {
                let value = try await EmulatorBus.shared.readValue(
                    peripheralIdentifier: peripheralManagerIdentifier,
                    for: descriptor,
                    centralIdentifier: centralManagerIdentifier
                )

                descriptor.setValue(value)

                notifyDelegate { delegate in
                    delegate.peripheral(self, didUpdateValueFor: descriptor, error: nil)
                }
            } catch {
                notifyDelegate { delegate in
                    delegate.peripheral(self, didUpdateValueFor: descriptor, error: error)
                }
            }
        }
    }

    // MARK: - Write Operations

    public func writeValue(_ data: Data, for characteristic: EmulatedCBCharacteristic, type: CBCharacteristicWriteType) {
        Task {
            do {
                // For write without response, update canSend status before writing
                if type == .withoutResponse {
                    canSendWriteWithoutResponse = await EmulatorBus.shared.canSendWriteWithoutResponse(
                        centralIdentifier: centralManagerIdentifier,
                        peripheralIdentifier: peripheralManagerIdentifier
                    )
                }

                try await EmulatorBus.shared.writeValue(
                    peripheralIdentifier: peripheralManagerIdentifier,
                    data: data,
                    for: characteristic,
                    type: type,
                    centralIdentifier: centralManagerIdentifier
                )

                // For write without response, update status after writing
                if type == .withoutResponse {
                    canSendWriteWithoutResponse = await EmulatorBus.shared.canSendWriteWithoutResponse(
                        centralIdentifier: centralManagerIdentifier,
                        peripheralIdentifier: peripheralManagerIdentifier
                    )
                }

                if type == .withResponse {
                    notifyDelegate { delegate in
                        delegate.peripheral(self, didWriteValueFor: characteristic, error: nil)
                    }
                }
            } catch {
                if type == .withResponse {
                    notifyDelegate { delegate in
                        delegate.peripheral(self, didWriteValueFor: characteristic, error: error)
                    }
                }
            }
        }
    }

    public func writeValue(_ data: Data, for descriptor: EmulatedCBDescriptor) {
        Task {
            do {
                try await EmulatorBus.shared.writeValue(
                    peripheralIdentifier: peripheralManagerIdentifier,
                    data: data,
                    for: descriptor,
                    centralIdentifier: centralManagerIdentifier
                )

                notifyDelegate { delegate in
                    delegate.peripheral(self, didWriteValueFor: descriptor, error: nil)
                }
            } catch {
                notifyDelegate { delegate in
                    delegate.peripheral(self, didWriteValueFor: descriptor, error: error)
                }
            }
        }
    }

    // MARK: - Notifications

    public func setNotifyValue(_ enabled: Bool, for characteristic: EmulatedCBCharacteristic) {
        Task {
            do {
                try await EmulatorBus.shared.setNotifyValue(
                    peripheralIdentifier: peripheralManagerIdentifier,
                    enabled: enabled,
                    for: characteristic,
                    centralIdentifier: centralManagerIdentifier
                )

                characteristic.setNotifying(enabled)

                notifyDelegate { delegate in
                    delegate.peripheral(self, didUpdateNotificationStateFor: characteristic, error: nil)
                }
            } catch {
                notifyDelegate { delegate in
                    delegate.peripheral(self, didUpdateNotificationStateFor: characteristic, error: error)
                }
            }
        }
    }

    internal func handleValueUpdate(value: Data, for characteristic: EmulatedCBCharacteristic) {
        characteristic.setValue(value)

        notifyDelegate { delegate in
            delegate.peripheral(self, didUpdateValueFor: characteristic, error: nil)
        }
    }

    // MARK: - RSSI

    public func readRSSI() {
        Task {
            let rssi = await EmulatorBus.shared.readRSSI(peripheralIdentifier: peripheralManagerIdentifier)

            notifyDelegate { delegate in
                delegate.peripheral(self, didReadRSSI: NSNumber(value: rssi), error: nil)
            }
        }
    }

    // MARK: - L2CAP Channels

    @available(iOS 11.0, macOS 10.13, tvOS 11.0, watchOS 4.0, *)
    public func openL2CAPChannel(_ psm: CBL2CAPPSM) {
        guard state == .connected else { return }

        Task {
            do {
                let channel = try await EmulatorBus.shared.openL2CAPChannel(
                    centralIdentifier: centralManagerIdentifier,
                    peripheralIdentifier: peripheralManagerIdentifier,
                    psm: psm
                )

                notifyDelegate { delegate in
                    delegate.peripheral(self, didOpen: channel, error: nil)
                }
            } catch {
                notifyDelegate { delegate in
                    delegate.peripheral(self, didOpen: nil, error: error)
                }
            }
        }
    }

    // MARK: - Maximum Write Length

    public func maximumWriteValueLength(for type: CBCharacteristicWriteType) -> Int {
        // Real CoreBluetooth returns MTU - ATT header size
        // ATT header is 3 bytes for write operations
        // For writeWithoutResponse, the overhead is 3 bytes
        // For writeWithResponse, the overhead is also 3 bytes
        return currentMTU - 3
    }

    // MARK: - Delegate Notification Helper

    private func notifyDelegate(_ block: @escaping @Sendable (any EmulatedCBPeripheralDelegate) -> Void) {
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
