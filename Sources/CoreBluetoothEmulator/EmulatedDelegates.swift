import Foundation
import CoreBluetooth

// MARK: - EmulatedCBCentralManagerDelegate

/// Delegate protocol for EmulatedCBCentralManager
public protocol EmulatedCBCentralManagerDelegate: AnyObject {
    /// Required: Called when the central manager's state is updated
    func centralManagerDidUpdateState(_ central: EmulatedCBCentralManager)

    /// Optional: Called when a peripheral is discovered
    func centralManager(
        _ central: EmulatedCBCentralManager,
        didDiscover peripheral: EmulatedCBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    )

    /// Optional: Called when a connection is established
    func centralManager(_ central: EmulatedCBCentralManager, didConnect peripheral: EmulatedCBPeripheral)

    /// Optional: Called when a connection fails
    func centralManager(
        _ central: EmulatedCBCentralManager,
        didFailToConnect peripheral: EmulatedCBPeripheral,
        error: Error?
    )

    /// Optional: Called when a peripheral disconnects
    func centralManager(
        _ central: EmulatedCBCentralManager,
        didDisconnectPeripheral peripheral: EmulatedCBPeripheral,
        error: Error?
    )

    /// Optional: Called when a connection event occurs
    func centralManager(
        _ central: EmulatedCBCentralManager,
        connectionEventDidOccur event: CBConnectionEvent,
        for peripheral: EmulatedCBPeripheral
    )

    /// Optional: Called when restoring state
    func centralManager(_ central: EmulatedCBCentralManager, willRestoreState dict: [String: Any])

    /// Optional: Called when ANCS authorization is updated
    func centralManager(
        _ central: EmulatedCBCentralManager,
        didUpdateANCSAuthorizationFor peripheral: EmulatedCBPeripheral
    )

    /// Optional: Called when peripheral is ready to send write without response
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: EmulatedCBPeripheral)
}

// Default implementations for optional methods
public extension EmulatedCBCentralManagerDelegate {
    func centralManager(
        _ central: EmulatedCBCentralManager,
        didDiscover peripheral: EmulatedCBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {}

    func centralManager(_ central: EmulatedCBCentralManager, didConnect peripheral: EmulatedCBPeripheral) {}

    func centralManager(
        _ central: EmulatedCBCentralManager,
        didFailToConnect peripheral: EmulatedCBPeripheral,
        error: Error?
    ) {}

    func centralManager(
        _ central: EmulatedCBCentralManager,
        didDisconnectPeripheral peripheral: EmulatedCBPeripheral,
        error: Error?
    ) {}

    func centralManager(
        _ central: EmulatedCBCentralManager,
        connectionEventDidOccur event: CBConnectionEvent,
        for peripheral: EmulatedCBPeripheral
    ) {}

    func centralManager(_ central: EmulatedCBCentralManager, willRestoreState dict: [String: Any]) {}

    func centralManager(
        _ central: EmulatedCBCentralManager,
        didUpdateANCSAuthorizationFor peripheral: EmulatedCBPeripheral
    ) {}

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: EmulatedCBPeripheral) {}
}

// MARK: - EmulatedCBPeripheralDelegate

/// Delegate protocol for EmulatedCBPeripheral
public protocol EmulatedCBPeripheralDelegate: AnyObject {
    /// Optional: Called when the peripheral's name is updated
    func peripheralDidUpdateName(_ peripheral: EmulatedCBPeripheral)

    /// Optional: Called when services are discovered
    func peripheral(_ peripheral: EmulatedCBPeripheral, didDiscoverServices error: Error?)

    /// Optional: Called when included services are discovered
    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didDiscoverIncludedServicesFor service: EmulatedCBService,
        error: Error?
    )

    /// Optional: Called when characteristics are discovered
    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didDiscoverCharacteristicsFor service: EmulatedCBService,
        error: Error?
    )

    /// Optional: Called when a characteristic's value is updated
    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didUpdateValueFor characteristic: EmulatedCBCharacteristic,
        error: Error?
    )

    /// Optional: Called when a characteristic value is written
    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didWriteValueFor characteristic: EmulatedCBCharacteristic,
        error: Error?
    )

    /// Optional: Called when a characteristic's notification state is updated
    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didUpdateNotificationStateFor characteristic: EmulatedCBCharacteristic,
        error: Error?
    )

    /// Optional: Called when descriptors are discovered
    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didDiscoverDescriptorsFor characteristic: EmulatedCBCharacteristic,
        error: Error?
    )

    /// Optional: Called when a descriptor's value is updated
    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didUpdateValueFor descriptor: EmulatedCBDescriptor,
        error: Error?
    )

    /// Optional: Called when a descriptor value is written
    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didWriteValueFor descriptor: EmulatedCBDescriptor,
        error: Error?
    )

    /// Optional: Called when RSSI is read
    func peripheral(_ peripheral: EmulatedCBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?)

    /// Optional: Called when services are modified
    func peripheral(_ peripheral: EmulatedCBPeripheral, didModifyServices invalidatedServices: [EmulatedCBService])

    /// Optional: Called when an L2CAP channel is opened
    func peripheral(_ peripheral: EmulatedCBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?)

    /// Optional: Called when ready to send write without response
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: EmulatedCBPeripheral)
}

// Default implementations for optional methods
public extension EmulatedCBPeripheralDelegate {
    func peripheralDidUpdateName(_ peripheral: EmulatedCBPeripheral) {}
    func peripheral(_ peripheral: EmulatedCBPeripheral, didDiscoverServices error: Error?) {}
    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didDiscoverIncludedServicesFor service: EmulatedCBService,
        error: Error?
    ) {}
    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didDiscoverCharacteristicsFor service: EmulatedCBService,
        error: Error?
    ) {}
    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didUpdateValueFor characteristic: EmulatedCBCharacteristic,
        error: Error?
    ) {}
    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didWriteValueFor characteristic: EmulatedCBCharacteristic,
        error: Error?
    ) {}
    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didUpdateNotificationStateFor characteristic: EmulatedCBCharacteristic,
        error: Error?
    ) {}
    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didDiscoverDescriptorsFor characteristic: EmulatedCBCharacteristic,
        error: Error?
    ) {}
    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didUpdateValueFor descriptor: EmulatedCBDescriptor,
        error: Error?
    ) {}
    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didWriteValueFor descriptor: EmulatedCBDescriptor,
        error: Error?
    ) {}
    func peripheral(_ peripheral: EmulatedCBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {}
    func peripheral(_ peripheral: EmulatedCBPeripheral, didModifyServices invalidatedServices: [EmulatedCBService]) {}
    func peripheral(_ peripheral: EmulatedCBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {}
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: EmulatedCBPeripheral) {}
}

// MARK: - EmulatedCBPeripheralManagerDelegate

/// Delegate protocol for EmulatedCBPeripheralManager
public protocol EmulatedCBPeripheralManagerDelegate: AnyObject {
    /// Required: Called when the peripheral manager's state is updated
    func peripheralManagerDidUpdateState(_ peripheral: EmulatedCBPeripheralManager)

    /// Optional: Called when advertising starts
    func peripheralManagerDidStartAdvertising(_ peripheral: EmulatedCBPeripheralManager, error: Error?)

    /// Optional: Called when a service is added
    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, didAdd service: EmulatedCBService, error: Error?)

    /// Optional: Called when a central subscribes to a characteristic
    func peripheralManager(
        _ peripheral: EmulatedCBPeripheralManager,
        central: EmulatedCBCentral,
        didSubscribeTo characteristic: EmulatedCBCharacteristic
    )

    /// Optional: Called when a central unsubscribes from a characteristic
    func peripheralManager(
        _ peripheral: EmulatedCBPeripheralManager,
        central: EmulatedCBCentral,
        didUnsubscribeFrom characteristic: EmulatedCBCharacteristic
    )

    /// Optional: Called when a read request is received
    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, didReceiveRead request: EmulatedCBATTRequest)

    /// Optional: Called when write requests are received
    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, didReceiveWrite requests: [EmulatedCBATTRequest])

    /// Optional: Called when ready to update subscribers
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: EmulatedCBPeripheralManager)

    /// Optional: Called when an L2CAP channel is published
    func peripheralManager(
        _ peripheral: EmulatedCBPeripheralManager,
        didPublishL2CAPChannel PSM: CBL2CAPPSM,
        error: Error?
    )

    /// Optional: Called when an L2CAP channel is unpublished
    func peripheralManager(
        _ peripheral: EmulatedCBPeripheralManager,
        didUnpublishL2CAPChannel PSM: CBL2CAPPSM,
        error: Error?
    )

    /// Optional: Called when an L2CAP channel is opened
    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, didOpen channel: CBL2CAPChannel?, error: Error?)

    /// Optional: Called when restoring state
    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, willRestoreState dict: [String: Any])
}

// Default implementations for optional methods
public extension EmulatedCBPeripheralManagerDelegate {
    func peripheralManagerDidStartAdvertising(_ peripheral: EmulatedCBPeripheralManager, error: Error?) {}
    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, didAdd service: EmulatedCBService, error: Error?) {}
    func peripheralManager(
        _ peripheral: EmulatedCBPeripheralManager,
        central: EmulatedCBCentral,
        didSubscribeTo characteristic: EmulatedCBCharacteristic
    ) {}
    func peripheralManager(
        _ peripheral: EmulatedCBPeripheralManager,
        central: EmulatedCBCentral,
        didUnsubscribeFrom characteristic: EmulatedCBCharacteristic
    ) {}
    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, didReceiveRead request: EmulatedCBATTRequest) {}
    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, didReceiveWrite requests: [EmulatedCBATTRequest]) {}
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: EmulatedCBPeripheralManager) {}
    func peripheralManager(
        _ peripheral: EmulatedCBPeripheralManager,
        didPublishL2CAPChannel PSM: CBL2CAPPSM,
        error: Error?
    ) {}
    func peripheralManager(
        _ peripheral: EmulatedCBPeripheralManager,
        didUnpublishL2CAPChannel PSM: CBL2CAPPSM,
        error: Error?
    ) {}
    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, didOpen channel: CBL2CAPChannel?, error: Error?) {}
    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, willRestoreState dict: [String: Any]) {}
}
