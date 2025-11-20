import XCTest
@testable import CoreBluetoothEmulator
import CoreBluetooth

@available(iOS 13.1, macOS 10.15, *)
final class ANCSAuthorizationTests: XCTestCase {
    var centralManager: EmulatedCBCentralManager!
    var peripheralManager: EmulatedCBPeripheralManager!
    var centralDelegate: ANCSTestCentralDelegate!
    var peripheralManagerDelegate: ANCSTestPeripheralManagerDelegate!

    override func setUp() async throws {
        await EmulatorBus.shared.reset()

        // Enable ANCS authorization updates
        var config = EmulatorConfiguration.instant
        config.fireANCSAuthorizationUpdates = true
        await EmulatorBus.shared.configure(config)

        centralDelegate = ANCSTestCentralDelegate()
        peripheralManagerDelegate = ANCSTestPeripheralManagerDelegate()

        centralManager = EmulatedCBCentralManager(delegate: centralDelegate, queue: nil)
        peripheralManager = EmulatedCBPeripheralManager(delegate: peripheralManagerDelegate, queue: nil)

        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func testANCSAuthorizationUpdate() async throws {
        let serviceUUID = CBUUID(string: "1400")
        let characteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "1401"),
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        let service = EmulatedCBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager.add(service)

        try await Task.sleep(nanoseconds: 100_000_000)

        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "ANCS Test Device",
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

        // Update ANCS authorization status
        await EmulatorBus.shared.updateANCSAuthorization(
            for: centralManager.identifier,
            status: .authorized
        )

        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify peripheral manager was notified
        XCTAssertTrue(peripheralManagerDelegate.ancsAuthorizationUpdates.count > 0, "Should receive ANCS authorization update")
    }

    func testANCSAuthorizationUpdateWithMultipleCentrals() async throws {
        let serviceUUID = CBUUID(string: "1500")
        let characteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "1501"),
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        let service = EmulatedCBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager.add(service)

        try await Task.sleep(nanoseconds: 100_000_000)

        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "Multi ANCS Device",
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ])

        // Create two centrals
        let centralDelegate2 = ANCSTestCentralDelegate()
        let centralManager2 = EmulatedCBCentralManager(delegate: centralDelegate2, queue: nil)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Both centrals scan and connect
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
        centralManager2.scanForPeripherals(withServices: [serviceUUID], options: nil)

        try await Task.sleep(nanoseconds: 100_000_000)

        guard let peripheral1 = centralDelegate.discoveredPeripherals.first,
              let peripheral2 = centralDelegate2.discoveredPeripherals.first else {
            XCTFail("Should discover peripheral on both centrals")
            return
        }

        centralManager.connect(peripheral1, options: nil)
        centralManager2.connect(peripheral2, options: nil)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Update ANCS authorization for first central
        await EmulatorBus.shared.updateANCSAuthorization(
            for: centralManager.identifier,
            status: .authorized
        )

        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify peripheral manager received update
        XCTAssertTrue(peripheralManagerDelegate.ancsAuthorizationUpdates.count > 0, "Should receive ANCS update for first central")

        let firstUpdateCount = peripheralManagerDelegate.ancsAuthorizationUpdates.count

        // Update ANCS authorization for second central
        await EmulatorBus.shared.updateANCSAuthorization(
            for: centralManager2.identifier,
            status: .denied
        )

        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify peripheral manager received second update
        XCTAssertTrue(peripheralManagerDelegate.ancsAuthorizationUpdates.count > firstUpdateCount, "Should receive ANCS update for second central")
    }

    func testANCSAuthorizationNotFiredWhenDisabled() async throws {
        // Disable ANCS authorization updates
        var config = EmulatorConfiguration.instant
        config.fireANCSAuthorizationUpdates = false
        await EmulatorBus.shared.configure(config)

        let serviceUUID = CBUUID(string: "1600")
        let characteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "1601"),
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        let service = EmulatedCBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager.add(service)

        try await Task.sleep(nanoseconds: 100_000_000)

        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "No ANCS Device",
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

        // Update ANCS authorization (should not fire)
        await EmulatorBus.shared.updateANCSAuthorization(
            for: centralManager.identifier,
            status: .authorized
        )

        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify NO updates were received
        XCTAssertEqual(peripheralManagerDelegate.ancsAuthorizationUpdates.count, 0, "Should not receive ANCS updates when disabled")
    }

    func testGetANCSAuthorizationStatus() async throws {
        // Set ANCS authorization
        await EmulatorBus.shared.updateANCSAuthorization(
            for: centralManager.identifier,
            status: .authorized
        )

        // Get ANCS authorization
        let status = await EmulatorBus.shared.getANCSAuthorization(for: centralManager.identifier)

        // Verify status matches
        XCTAssertEqual(status, .authorized, "Should return authorized status")
    }

    func testANCSAuthorizationDefaultStatus() async throws {
        // Get ANCS authorization for central that hasn't been set
        let status = await EmulatorBus.shared.getANCSAuthorization(for: UUID())

        // Verify default status
        XCTAssertEqual(status, .notDetermined, "Should return notDetermined as default")
    }
}

// MARK: - Test Delegates

@available(iOS 13.1, macOS 10.15, *)
class ANCSTestCentralDelegate: NSObject, EmulatedCBCentralManagerDelegate {
    var discoveredPeripherals: [EmulatedCBPeripheral] = []

    func centralManagerDidUpdateState(_ central: EmulatedCBCentralManager) {}

    func centralManager(_ central: EmulatedCBCentralManager, didDiscover peripheral: EmulatedCBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        discoveredPeripherals.append(peripheral)
    }

    func centralManager(_ central: EmulatedCBCentralManager, didConnect peripheral: EmulatedCBPeripheral) {}
}

@available(iOS 13.1, macOS 10.15, *)
class ANCSTestPeripheralManagerDelegate: NSObject, EmulatedCBPeripheralManagerDelegate {
    var ancsAuthorizationUpdates: [EmulatedCBCentral] = []

    func peripheralManagerDidUpdateState(_ peripheral: EmulatedCBPeripheralManager) {}

    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, didUpdateANCSAuthorizationFor central: EmulatedCBCentral) {
        ancsAuthorizationUpdates.append(central)
    }
}
