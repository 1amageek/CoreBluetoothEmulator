import XCTest
@testable import CoreBluetoothEmulator
import CoreBluetooth

final class MTUManagementTests: XCTestCase {
    var centralManager: EmulatedCBCentralManager!
    var peripheralManager: EmulatedCBPeripheralManager!
    var centralDelegate: MTUTestCentralDelegate!
    var peripheralManagerDelegate: MTUTestPeripheralManagerDelegate!

    override func setUp() async throws {
        await EmulatorBus.shared.reset()

        centralDelegate = MTUTestCentralDelegate()
        peripheralManagerDelegate = MTUTestPeripheralManagerDelegate()

        centralManager = EmulatedCBCentralManager(delegate: centralDelegate, queue: nil)
        peripheralManager = EmulatedCBPeripheralManager(delegate: peripheralManagerDelegate, queue: nil)

        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func testDefaultMTU() async throws {
        var config = EmulatorConfiguration.instant
        config.defaultMTU = 185
        await EmulatorBus.shared.configure(config)

        // Setup and connect
        let (peripheral, _) = try await setupAndConnect()

        // Check maximum write length
        let maxLength = peripheral.maximumWriteValueLength(for: .withResponse)
        XCTAssertEqual(maxLength, 185 - 3, "Maximum write length should be MTU - 3 (ATT header)")
    }

    func testCustomMTU() async throws {
        var config = EmulatorConfiguration.instant
        config.defaultMTU = 512
        await EmulatorBus.shared.configure(config)

        let (peripheral, _) = try await setupAndConnect()

        let maxLength = peripheral.maximumWriteValueLength(for: .withResponse)
        XCTAssertEqual(maxLength, 512 - 3, "Maximum write length should be custom MTU - 3")
    }

    func testMTUNegotiation() async throws {
        await EmulatorBus.shared.configure(.instant)

        let (peripheral, _) = try await setupAndConnect()

        // Get current MTU
        let initialMTU = await EmulatorBus.shared.getMTU(
            centralIdentifier: centralManager.identifier,
            peripheralIdentifier: peripheral.peripheralManagerIdentifier
        )
        XCTAssertEqual(initialMTU, 185, "Initial MTU should be default")

        // Negotiate higher MTU
        let negotiatedMTU = await EmulatorBus.shared.negotiateMTU(
            centralIdentifier: centralManager.identifier,
            peripheralIdentifier: peripheral.peripheralManagerIdentifier,
            requestedMTU: 256
        )
        XCTAssertEqual(negotiatedMTU, 256, "Should negotiate to requested MTU")

        // Verify it was updated
        let updatedMTU = await EmulatorBus.shared.getMTU(
            centralIdentifier: centralManager.identifier,
            peripheralIdentifier: peripheral.peripheralManagerIdentifier
        )
        XCTAssertEqual(updatedMTU, 256, "MTU should be updated")
    }

    func testMTUMaximum() async throws {
        var config = EmulatorConfiguration.instant
        config.maximumMTU = 512
        await EmulatorBus.shared.configure(config)

        let (peripheral, _) = try await setupAndConnect()

        // Try to negotiate beyond maximum
        let negotiatedMTU = await EmulatorBus.shared.negotiateMTU(
            centralIdentifier: centralManager.identifier,
            peripheralIdentifier: peripheral.peripheralManagerIdentifier,
            requestedMTU: 1024
        )
        XCTAssertEqual(negotiatedMTU, 512, "Should cap at maximum MTU")
    }

    // MARK: - Helper Methods

    private func setupAndConnect() async throws -> (EmulatedCBPeripheral, EmulatedCBMutableService) {
        let service = EmulatedCBMutableService(type: CBUUID(string: "1234"), primary: true)
        peripheralManager.add(service)
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "MTU Test",
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

        XCTAssertEqual(peripheral.state, .connected)

        return (peripheral, service)
    }
}

enum TestError: Error {
    case noPeripheralDiscovered
}

// MARK: - Test Delegates

class MTUTestCentralDelegate: EmulatedCBCentralManagerDelegate {
    var discoveredPeripherals: [(EmulatedCBPeripheral, [String: Any], NSNumber)] = []

    func centralManagerDidUpdateState(_ central: EmulatedCBCentralManager) {}

    func centralManager(
        _ central: EmulatedCBCentralManager,
        didDiscover peripheral: EmulatedCBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        discoveredPeripherals.append((peripheral, advertisementData, RSSI))
    }
}

class MTUTestPeripheralManagerDelegate: EmulatedCBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: EmulatedCBPeripheralManager) {}
}
