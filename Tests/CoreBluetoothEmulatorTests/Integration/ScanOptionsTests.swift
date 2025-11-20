import XCTest
@testable import CoreBluetoothEmulator
import CoreBluetooth

final class ScanOptionsTests: XCTestCase {
    var centralManager: EmulatedCBCentralManager!
    var peripheralManager: EmulatedCBPeripheralManager!
    var centralDelegate: TestCentralDelegate!
    var peripheralManagerDelegate: TestPeripheralManagerDelegate!

    override func setUp() async throws {
        await EmulatorBus.shared.reset()

        centralDelegate = TestCentralDelegate()
        peripheralManagerDelegate = TestPeripheralManagerDelegate()

        centralManager = EmulatedCBCentralManager(delegate: centralDelegate, queue: nil)
        peripheralManager = EmulatedCBPeripheralManager(delegate: peripheralManagerDelegate, queue: nil)

        // Wait for powered on
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func testAllowDuplicatesOption() async throws {
        // Configure emulator to honor AllowDuplicates
        var config = EmulatorConfiguration.instant
        config.honorAllowDuplicatesOption = true
        config.scanDiscoveryInterval = 0.01  // Fast scan cycles
        await EmulatorBus.shared.configure(config)

        // Setup peripheral
        let service = EmulatedCBMutableService(type: CBUUID(string: "1234"), primary: true)
        peripheralManager.add(service)
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "Test Device",
            CBAdvertisementDataServiceUUIDsKey: [service.uuid]
        ])

        // Start scanning WITH AllowDuplicates
        centralDelegate.discoveredPeripherals.removeAll()
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        // Wait for multiple discoveries
        try await Task.sleep(nanoseconds: 200_000_000)

        // Should receive multiple discoveries for the same peripheral
        XCTAssertGreaterThan(centralDelegate.discoveredPeripherals.count, 1,
                           "Should receive multiple discoveries with AllowDuplicates=true")

        centralManager.stopScan()

        // Wait for scan to fully stop
        try await Task.sleep(nanoseconds: 50_000_000)

        // Start scanning WITHOUT AllowDuplicates
        centralDelegate.discoveredPeripherals.removeAll()
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        try await Task.sleep(nanoseconds: 200_000_000)

        // Should receive only one discovery
        XCTAssertEqual(centralDelegate.discoveredPeripherals.count, 1,
                      "Should receive only one discovery with AllowDuplicates=false")
    }

    func testSolicitedServiceUUIDs() async throws {
        var config = EmulatorConfiguration.instant
        config.honorSolicitedServiceUUIDs = true
        await EmulatorBus.shared.configure(config)

        let serviceUUID = CBUUID(string: "1234")
        let solicitedUUID = CBUUID(string: "5678")

        let service = EmulatedCBMutableService(type: serviceUUID, primary: true)
        peripheralManager.add(service)

        // Advertise with solicited service UUID
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "Test Device",
            CBAdvertisementDataServiceUUIDsKey: [service.uuid],
            CBAdvertisementDataSolicitedServiceUUIDsKey: [solicitedUUID]
        ])

        // Scan for solicited services
        centralDelegate.discoveredPeripherals.removeAll()
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionSolicitedServiceUUIDsKey: [solicitedUUID]]
        )

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(centralDelegate.discoveredPeripherals.count, 1,
                      "Should discover peripheral advertising solicited service")

        centralManager.stopScan()

        // Scan for different solicited service
        let differentUUID = CBUUID(string: "ABCD")
        centralDelegate.discoveredPeripherals.removeAll()
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionSolicitedServiceUUIDsKey: [differentUUID]]
        )

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(centralDelegate.discoveredPeripherals.count, 0,
                      "Should not discover peripheral when solicited service doesn't match")
    }
}

// MARK: - Test Delegates

class TestCentralDelegate: EmulatedCBCentralManagerDelegate {
    var discoveredPeripherals: [(EmulatedCBPeripheral, [String: Any], NSNumber)] = []
    var connectedPeripherals: [EmulatedCBPeripheral] = []
    var disconnectedPeripherals: [EmulatedCBPeripheral] = []

    func centralManagerDidUpdateState(_ central: EmulatedCBCentralManager) {}

    func centralManager(
        _ central: EmulatedCBCentralManager,
        didDiscover peripheral: EmulatedCBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        discoveredPeripherals.append((peripheral, advertisementData, RSSI))
    }

    func centralManager(_ central: EmulatedCBCentralManager, didConnect peripheral: EmulatedCBPeripheral) {
        connectedPeripherals.append(peripheral)
    }

    func centralManager(
        _ central: EmulatedCBCentralManager,
        didDisconnectPeripheral peripheral: EmulatedCBPeripheral,
        error: Error?
    ) {
        disconnectedPeripherals.append(peripheral)
    }
}

class TestPeripheralManagerDelegate: EmulatedCBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: EmulatedCBPeripheralManager) {}
}
