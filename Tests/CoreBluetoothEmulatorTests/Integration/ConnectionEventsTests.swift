import XCTest
@testable import CoreBluetoothEmulator
import CoreBluetooth

@available(iOS 13.0, macOS 10.15, *)
final class ConnectionEventsTests: XCTestCase {
    var centralManager: EmulatedCBCentralManager!
    var peripheralManager: EmulatedCBPeripheralManager!
    var centralDelegate: ConnectionEventsTestCentralDelegate!
    var peripheralManagerDelegate: ConnectionEventsTestPeripheralManagerDelegate!

    override func setUp() async throws {
        await EmulatorBus.shared.reset()

        // Enable connection events
        var config = EmulatorConfiguration.instant
        config.fireConnectionEvents = true
        await EmulatorBus.shared.configure(config)

        centralDelegate = ConnectionEventsTestCentralDelegate()
        peripheralManagerDelegate = ConnectionEventsTestPeripheralManagerDelegate()

        centralManager = EmulatedCBCentralManager(delegate: centralDelegate, queue: nil)
        peripheralManager = EmulatedCBPeripheralManager(delegate: peripheralManagerDelegate, queue: nil)

        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func testPeerConnectedEvent() async throws {
        // Register for connection events
        centralManager.registerForConnectionEvents(options: nil)

        let serviceUUID = CBUUID(string: "EE00")
        let characteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "EE01"),
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        let service = EmulatedCBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager.add(service)

        try await Task.sleep(nanoseconds: 100_000_000)

        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "Event Test Device",
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ])

        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)

        try await Task.sleep(nanoseconds: 100_000_000)

        guard let peripheral = centralDelegate.discoveredPeripherals.first else {
            XCTFail("Should discover peripheral")
            return
        }

        // Connect - should trigger peerConnected event
        centralManager.connect(peripheral, options: nil)

        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify connection event was fired
        XCTAssertTrue(centralDelegate.connectionEvents.count > 0, "Should receive connection event")
        XCTAssertEqual(centralDelegate.connectionEvents.first?.event, .peerConnected, "Should be peerConnected event")
    }

    func testPeerDisconnectedEvent() async throws {
        // Register for connection events
        centralManager.registerForConnectionEvents(options: nil)

        let serviceUUID = CBUUID(string: "FF00")
        let characteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "FF01"),
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        let service = EmulatedCBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager.add(service)

        try await Task.sleep(nanoseconds: 100_000_000)

        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "Disconnect Event Device",
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ])

        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)

        try await Task.sleep(nanoseconds: 100_000_000)

        guard let peripheral = centralDelegate.discoveredPeripherals.first else {
            XCTFail("Should discover peripheral")
            return
        }

        centralManager.connect(peripheral, options: nil)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Clear previous events
        centralDelegate.connectionEvents.removeAll()

        // Disconnect - should trigger peerDisconnected event
        centralManager.cancelPeripheralConnection(peripheral)

        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify disconnection event was fired
        XCTAssertTrue(centralDelegate.connectionEvents.count > 0, "Should receive disconnection event")
        XCTAssertEqual(centralDelegate.connectionEvents.first?.event, .peerDisconnected, "Should be peerDisconnected event")
    }

    func testConnectionEventsNotFiredWhenDisabled() async throws {
        // Disable connection events
        var config = EmulatorConfiguration.instant
        config.fireConnectionEvents = false
        await EmulatorBus.shared.configure(config)

        // Register for connection events (but they're disabled)
        centralManager.registerForConnectionEvents(options: nil)

        let serviceUUID = CBUUID(string: "DD00")
        let characteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "DD01"),
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        let service = EmulatedCBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager.add(service)

        try await Task.sleep(nanoseconds: 100_000_000)

        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "No Events Device",
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ])

        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)

        try await Task.sleep(nanoseconds: 100_000_000)

        guard let peripheral = centralDelegate.discoveredPeripherals.first else {
            XCTFail("Should discover peripheral")
            return
        }

        centralManager.connect(peripheral, options: nil)

        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify NO connection events were fired
        XCTAssertEqual(centralDelegate.connectionEvents.count, 0, "Should not receive connection events when disabled")
    }
}

// MARK: - Test Delegate

@available(iOS 13.0, macOS 10.15, *)
class ConnectionEventsTestCentralDelegate: NSObject, EmulatedCBCentralManagerDelegate {
    var discoveredPeripherals: [EmulatedCBPeripheral] = []
    var connectionEvents: [(event: CBConnectionEvent, peripheral: EmulatedCBPeripheral)] = []

    func centralManagerDidUpdateState(_ central: EmulatedCBCentralManager) {}

    func centralManager(_ central: EmulatedCBCentralManager, didDiscover peripheral: EmulatedCBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        discoveredPeripherals.append(peripheral)
    }

    func centralManager(_ central: EmulatedCBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: EmulatedCBPeripheral) {
        connectionEvents.append((event: event, peripheral: peripheral))
    }
}

class ConnectionEventsTestPeripheralManagerDelegate: NSObject, EmulatedCBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: EmulatedCBPeripheralManager) {}
}
