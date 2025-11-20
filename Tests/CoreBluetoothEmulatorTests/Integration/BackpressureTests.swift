import XCTest
@testable import CoreBluetoothEmulator
import CoreBluetooth

final class BackpressureTests: XCTestCase {
    var centralManager: EmulatedCBCentralManager!
    var peripheralManager: EmulatedCBPeripheralManager!
    var centralDelegate: BackpressureTestCentralDelegate!
    var peripheralManagerDelegate: BackpressureTestPeripheralManagerDelegate!

    override func setUp() async throws {
        await EmulatorBus.shared.reset()

        centralDelegate = BackpressureTestCentralDelegate()
        peripheralManagerDelegate = BackpressureTestPeripheralManagerDelegate()

        centralManager = EmulatedCBCentralManager(delegate: centralDelegate, queue: nil)
        peripheralManager = EmulatedCBPeripheralManager(delegate: peripheralManagerDelegate, queue: nil)

        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func testWriteWithoutResponseBackpressure() async throws {
        var config = EmulatorConfiguration.instant
        config.simulateBackpressure = true
        config.maxWriteWithoutResponseQueue = 3
        config.backpressureProcessingDelay = 0.3  // 300ms delay to keep items in queue
        await EmulatorBus.shared.configure(config)

        let (peripheral, characteristic) = try await setupAndConnect()

        // Initially should be able to send
        XCTAssertTrue(peripheral.canSendWriteWithoutResponse)

        // Send writes until queue is full
        for _ in 0..<3 {
            peripheral.writeValue(Data([0x01]), for: characteristic, type: .withoutResponse)
        }

        // Wait for writes to be enqueued
        try await Task.sleep(nanoseconds: 50_000_000)

        // Should not be able to send more (queue full)
        XCTAssertFalse(peripheral.canSendWriteWithoutResponse)

        // Wait for queue to drain
        try await Task.sleep(nanoseconds: 500_000_000)

        // Should be able to send again
        XCTAssertTrue(peripheral.canSendWriteWithoutResponse)

        // Verify ready callback was called
        XCTAssertGreaterThan(centralDelegate.readyCallbacks.count, 0,
                           "peripheralIsReady callback should be called when queue has space")
    }

    func testNotificationBackpressure() async throws {
        var config = EmulatorConfiguration.instant
        config.simulateBackpressure = true
        config.maxNotificationQueue = 3
        config.backpressureProcessingDelay = 0.3  // 300ms delay to keep items in queue
        await EmulatorBus.shared.configure(config)

        let (peripheral, characteristic) = try await setupAndConnect()

        // Subscribe to notifications
        peripheral.setNotifyValue(true, for: characteristic)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(characteristic.isNotifying)

        // Send notifications until queue is full
        for i in 0..<3 {
            let success = peripheralManager.updateValue(
                Data([UInt8(i)]),
                for: characteristic,
                onSubscribedCentrals: nil
            )
            XCTAssertTrue(success, "First 3 notifications should succeed")
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        // Next notification should fail (queue full)
        let canSend = await EmulatorBus.shared.canSendNotification(
            peripheralIdentifier: peripheralManager.identifier,
            characteristicUUID: characteristic.uuid
        )
        XCTAssertFalse(canSend, "Should not be able to send notification when queue is full")

        // Wait for queue to drain
        try await Task.sleep(nanoseconds: 500_000_000)

        // Should be able to send again
        let canSendAfterDrain = await EmulatorBus.shared.canSendNotification(
            peripheralIdentifier: peripheralManager.identifier,
            characteristicUUID: characteristic.uuid
        )
        XCTAssertTrue(canSendAfterDrain, "Should be able to send notification after queue drains")
    }

    // MARK: - Helper Methods

    private func setupAndConnect() async throws -> (EmulatedCBPeripheral, EmulatedCBMutableCharacteristic) {
        let service = EmulatedCBMutableService(type: CBUUID(string: "1234"), primary: true)
        let characteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "5678"),
            properties: [.write, .writeWithoutResponse, .notify],
            value: nil,
            permissions: [.writeable]
        )
        service.characteristics = [characteristic]

        peripheralManager.add(service)
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "Backpressure Test",
            CBAdvertisementDataServiceUUIDsKey: [service.uuid]
        ])

        centralManager.scanForPeripherals(withServices: nil, options: nil)
        try await Task.sleep(nanoseconds: 100_000_000)

        guard let peripheral = centralDelegate.discoveredPeripherals.first?.0 else {
            throw TestError.noPeripheralDiscovered
        }

        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)

        try await Task.sleep(nanoseconds: 100_000_000)

        peripheral.discoverServices([service.uuid])
        try await Task.sleep(nanoseconds: 100_000_000)

        guard let discoveredService = peripheral.services?.first else {
            throw TestError.noServiceDiscovered
        }

        peripheral.discoverCharacteristics([characteristic.uuid], for: discoveredService)
        try await Task.sleep(nanoseconds: 100_000_000)

        guard let discoveredCharacteristic = discoveredService.characteristics?.first else {
            throw TestError.noCharacteristicDiscovered
        }

        return (peripheral, characteristic)
    }

    enum TestError: Error {
        case noPeripheralDiscovered
        case noServiceDiscovered
        case noCharacteristicDiscovered
    }
}

// MARK: - Test Delegates

class BackpressureTestCentralDelegate: EmulatedCBCentralManagerDelegate {
    var discoveredPeripherals: [(EmulatedCBPeripheral, [String: Any], NSNumber)] = []
    var readyCallbacks: [EmulatedCBPeripheral] = []

    func centralManagerDidUpdateState(_ central: EmulatedCBCentralManager) {}

    func centralManager(
        _ central: EmulatedCBCentralManager,
        didDiscover peripheral: EmulatedCBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        discoveredPeripherals.append((peripheral, advertisementData, RSSI))
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: EmulatedCBPeripheral) {
        readyCallbacks.append(peripheral)
    }
}

class BackpressureTestPeripheralManagerDelegate: EmulatedCBPeripheralManagerDelegate {
    var readyCallbacks: [EmulatedCBPeripheralManager] = []

    func peripheralManagerDidUpdateState(_ peripheral: EmulatedCBPeripheralManager) {}

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: EmulatedCBPeripheralManager) {
        readyCallbacks.append(peripheral)
    }
}
