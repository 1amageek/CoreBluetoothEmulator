import XCTest
@testable import CoreBluetoothEmulator
import CoreBluetooth

final class StateRestorationTests: XCTestCase {

    override func setUp() async throws {
        await EmulatorBus.shared.reset()

        // Enable state restoration
        var config = EmulatorConfiguration.instant
        config.stateRestorationEnabled = true
        await EmulatorBus.shared.configure(config)
    }

    func testCentralManagerStateRestoration() async throws {
        let restoreIdentifier = "testCentralManager"

        // Phase 1: Create central manager and connect to a peripheral
        var centralDelegate = StateRestorationCentralDelegate()
        var centralManager: EmulatedCBCentralManager? = EmulatedCBCentralManager(
            delegate: centralDelegate,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: restoreIdentifier]
        )

        var peripheralManagerDelegate = StateRestorationPeripheralManagerDelegate()
        let peripheralManager = EmulatedCBPeripheralManager(
            delegate: peripheralManagerDelegate,
            queue: nil
        )

        // Setup service
        let serviceUUID = CBUUID(string: "1234")
        let characteristicUUID = CBUUID(string: "5678")

        let characteristic = EmulatedCBMutableCharacteristic(
            type: characteristicUUID,
            properties: [.read, .write],
            value: nil,
            permissions: [.readable, .writeable]
        )

        let service = EmulatedCBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]

        peripheralManager.add(service)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Start advertising
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "Test Device",
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ])

        // Start scanning and connect
        centralManager?.scanForPeripherals(withServices: [serviceUUID], options: nil)

        try await Task.sleep(nanoseconds: 100_000_000)

        guard let discoveredPeripheral = centralDelegate.discoveredPeripherals.first else {
            XCTFail("Should discover peripheral")
            return
        }

        centralManager?.connect(discoveredPeripheral, options: nil)

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(centralDelegate.connectedPeripherals.contains(discoveredPeripheral))

        // Save state before "termination"
        try await EmulatorBus.shared.saveCentralState(
            centralIdentifier: centralManager!.identifier,
            restoreIdentifier: restoreIdentifier
        )

        let savedCentralId = centralManager!.identifier

        // Phase 2: Simulate app termination and restoration
        centralManager = nil
        centralDelegate = StateRestorationCentralDelegate()

        try await Task.sleep(nanoseconds: 100_000_000)

        // Create new central manager with same restore identifier
        centralManager = EmulatedCBCentralManager(
            delegate: centralDelegate,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: restoreIdentifier]
        )

        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify restoration
        XCTAssertTrue(centralDelegate.restorationCalled, "willRestoreState should be called")
        XCTAssertNotNil(centralDelegate.restoredPeripherals, "Should restore peripherals")
        XCTAssertEqual(centralDelegate.restoredPeripherals?.count, 1, "Should restore 1 peripheral")

        if let restoredPeripheral = centralDelegate.restoredPeripherals?.first {
            XCTAssertEqual(restoredPeripheral.identifier, discoveredPeripheral.identifier, "Should restore same peripheral")
        }
    }

    func testPeripheralManagerStateRestoration() async throws {
        let restoreIdentifier = "testPeripheralManager"

        // Phase 1: Create peripheral manager and start advertising
        var peripheralManagerDelegate = StateRestorationPeripheralManagerDelegate()
        var peripheralManager: EmulatedCBPeripheralManager? = EmulatedCBPeripheralManager(
            delegate: peripheralManagerDelegate,
            queue: nil,
            options: [CBPeripheralManagerOptionRestoreIdentifierKey: restoreIdentifier]
        )

        try await Task.sleep(nanoseconds: 100_000_000)

        let advertisementData: [String: Any] = [
            CBAdvertisementDataLocalNameKey: "Test Peripheral",
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: "ABCD")]
        ]

        peripheralManager?.startAdvertising(advertisementData)

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(peripheralManager!.isAdvertising)

        // Save state before "termination"
        try await EmulatorBus.shared.savePeripheralState(
            peripheralIdentifier: peripheralManager!.identifier,
            restoreIdentifier: restoreIdentifier
        )

        // Phase 2: Simulate app termination and restoration
        peripheralManager = nil
        peripheralManagerDelegate = StateRestorationPeripheralManagerDelegate()

        try await Task.sleep(nanoseconds: 100_000_000)

        // Create new peripheral manager with same restore identifier
        peripheralManager = EmulatedCBPeripheralManager(
            delegate: peripheralManagerDelegate,
            queue: nil,
            options: [CBPeripheralManagerOptionRestoreIdentifierKey: restoreIdentifier]
        )

        try await Task.sleep(nanoseconds: 300_000_000) // Wait for restoration + restart advertising

        // Verify restoration
        XCTAssertTrue(peripheralManagerDelegate.restorationCalled, "willRestoreState should be called")
        XCTAssertNotNil(peripheralManagerDelegate.restoredAdvertisementData, "Should restore advertisement data")

        if let restoredAdvData = peripheralManagerDelegate.restoredAdvertisementData {
            XCTAssertEqual(restoredAdvData[CBAdvertisementDataLocalNameKey] as? String, "Test Peripheral")
        }
    }

    func testStateRestorationWithoutSavedState() async throws {
        let restoreIdentifier = "nonExistentIdentifier"

        let centralDelegate = StateRestorationCentralDelegate()
        let centralManager = EmulatedCBCentralManager(
            delegate: centralDelegate,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: restoreIdentifier]
        )

        try await Task.sleep(nanoseconds: 200_000_000)

        // Should call willRestoreState with empty dictionary
        XCTAssertTrue(centralDelegate.restorationCalled, "willRestoreState should be called even without saved state")
        XCTAssertNil(centralDelegate.restoredPeripherals, "Should not restore any peripherals")
    }
}

// MARK: - Test Delegates

class StateRestorationCentralDelegate: NSObject, EmulatedCBCentralManagerDelegate {
    var discoveredPeripherals: [EmulatedCBPeripheral] = []
    var connectedPeripherals: [EmulatedCBPeripheral] = []
    var restorationCalled = false
    var restoredPeripherals: [EmulatedCBPeripheral]?
    var restoredScanServices: [CBUUID]?

    func centralManagerDidUpdateState(_ central: EmulatedCBCentralManager) {
        // State updated
    }

    func centralManager(_ central: EmulatedCBCentralManager, didDiscover peripheral: EmulatedCBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        discoveredPeripherals.append(peripheral)
    }

    func centralManager(_ central: EmulatedCBCentralManager, didConnect peripheral: EmulatedCBPeripheral) {
        connectedPeripherals.append(peripheral)
    }

    func centralManager(_ central: EmulatedCBCentralManager, willRestoreState dict: [String : Any]) {
        restorationCalled = true
        restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [EmulatedCBPeripheral]
        restoredScanServices = dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID]
    }
}

class StateRestorationPeripheralManagerDelegate: NSObject, EmulatedCBPeripheralManagerDelegate {
    var restorationCalled = false
    var restoredAdvertisementData: [String: Any]?
    var restoredServices: [EmulatedCBMutableService]?

    func peripheralManagerDidUpdateState(_ peripheral: EmulatedCBPeripheralManager) {
        // State updated
    }

    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, willRestoreState dict: [String : Any]) {
        restorationCalled = true
        restoredAdvertisementData = dict[CBPeripheralManagerRestoredStateAdvertisementDataKey] as? [String: Any]
        restoredServices = dict[CBPeripheralManagerRestoredStateServicesKey] as? [EmulatedCBMutableService]
    }
}
