import XCTest
@testable import CoreBluetoothEmulator
import CoreBluetooth

final class AdvertisementAutoGenerationTests: XCTestCase {
    var centralManager: EmulatedCBCentralManager!
    var peripheralManager: EmulatedCBPeripheralManager!
    var centralDelegate: AdvertisementTestCentralDelegate!
    var peripheralManagerDelegate: AdvertisementTestPeripheralManagerDelegate!

    override func setUp() async throws {
        await EmulatorBus.shared.reset()

        // Enable auto-generation by default
        var config = EmulatorConfiguration.instant
        config.autoGenerateAdvertisementFields = true
        await EmulatorBus.shared.configure(config)

        centralDelegate = AdvertisementTestCentralDelegate()
        peripheralManagerDelegate = AdvertisementTestPeripheralManagerDelegate()

        centralManager = EmulatedCBCentralManager(delegate: centralDelegate, queue: nil)
        peripheralManager = EmulatedCBPeripheralManager(delegate: peripheralManagerDelegate, queue: nil)

        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func testTxPowerLevelAutoGeneration() async throws {
        let serviceUUID = CBUUID(string: "1234")

        // Setup service
        let characteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "5678"),
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        let service = EmulatedCBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager.add(service)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Start advertising WITHOUT TxPowerLevel
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "Test Device",
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ])

        // Start scanning
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)

        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify TxPowerLevel was auto-generated
        XCTAssertTrue(centralDelegate.discoveredAdvertisements.count > 0, "Should discover peripheral")

        if let advData = centralDelegate.discoveredAdvertisements.first {
            XCTAssertNotNil(advData[CBAdvertisementDataTxPowerLevelKey], "TxPowerLevel should be auto-generated")

            if let txPower = advData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber {
                let txPowerValue = txPower.intValue
                XCTAssertTrue(txPowerValue >= -12 && txPowerValue <= -4,
                             "TxPower should be in realistic range (-12 to -4 dBm), got \(txPowerValue)")
            }
        }
    }

    func testIsConnectableAutoGeneration() async throws {
        let serviceUUID = CBUUID(string: "AAAA")

        // Setup service
        let characteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "BBBB"),
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        let service = EmulatedCBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager.add(service)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Start advertising WITHOUT IsConnectable
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "Connectable Device",
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ])

        // Start scanning
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)

        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify IsConnectable was auto-generated
        XCTAssertTrue(centralDelegate.discoveredAdvertisements.count > 0, "Should discover peripheral")

        if let advData = centralDelegate.discoveredAdvertisements.first {
            XCTAssertNotNil(advData[CBAdvertisementDataIsConnectable], "IsConnectable should be auto-generated")

            if let isConnectable = advData[CBAdvertisementDataIsConnectable] as? NSNumber {
                XCTAssertTrue(isConnectable.boolValue, "IsConnectable should default to true")
            }
        }
    }

    func testManualValuesNotOverridden() async throws {
        let serviceUUID = CBUUID(string: "1111")

        // Setup service
        let characteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "2222"),
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        let service = EmulatedCBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager.add(service)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Start advertising WITH manual values
        let manualTxPower = -20
        let manualIsConnectable = false

        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "Manual Values",
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataTxPowerLevelKey: NSNumber(value: manualTxPower),
            CBAdvertisementDataIsConnectable: NSNumber(value: manualIsConnectable)
        ])

        // Start scanning
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)

        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify manual values were NOT overridden
        XCTAssertTrue(centralDelegate.discoveredAdvertisements.count > 0, "Should discover peripheral")

        if let advData = centralDelegate.discoveredAdvertisements.first {
            if let txPower = advData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber {
                XCTAssertEqual(txPower.intValue, manualTxPower,
                              "Manual TxPower should not be overridden")
            }

            if let isConnectable = advData[CBAdvertisementDataIsConnectable] as? NSNumber {
                XCTAssertEqual(isConnectable.boolValue, manualIsConnectable,
                              "Manual IsConnectable should not be overridden")
            }
        }
    }

    func testAutoGenerationDisabled() async throws {
        // Disable auto-generation
        var config = EmulatorConfiguration.instant
        config.autoGenerateAdvertisementFields = false
        await EmulatorBus.shared.configure(config)

        let serviceUUID = CBUUID(string: "3333")

        // Setup service
        let characteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "4444"),
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        let service = EmulatedCBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager.add(service)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Start advertising without TxPowerLevel or IsConnectable
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "No Auto Generation",
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ])

        // Start scanning
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)

        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify fields were NOT auto-generated
        XCTAssertTrue(centralDelegate.discoveredAdvertisements.count > 0, "Should discover peripheral")

        if let advData = centralDelegate.discoveredAdvertisements.first {
            XCTAssertNil(advData[CBAdvertisementDataTxPowerLevelKey],
                        "TxPowerLevel should NOT be auto-generated when disabled")
            XCTAssertNil(advData[CBAdvertisementDataIsConnectable],
                        "IsConnectable should NOT be auto-generated when disabled")
        }
    }

    func testAllAdvertisementFieldsPassthrough() async throws {
        let serviceUUID = CBUUID(string: "5555")
        let manufacturerData = Data([0x01, 0x02, 0x03, 0x04])
        let serviceData = [CBUUID(string: "6666"): Data([0xAA, 0xBB])]

        // Setup service
        let characteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "7777"),
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        let service = EmulatedCBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager.add(service)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Start advertising with multiple fields
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "Full Advertisement",
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataManufacturerDataKey: manufacturerData,
            CBAdvertisementDataServiceDataKey: serviceData
        ])

        // Start scanning
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)

        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify all fields are passed through
        XCTAssertTrue(centralDelegate.discoveredAdvertisements.count > 0, "Should discover peripheral")

        if let advData = centralDelegate.discoveredAdvertisements.first {
            XCTAssertEqual(advData[CBAdvertisementDataLocalNameKey] as? String, "Full Advertisement")
            XCTAssertNotNil(advData[CBAdvertisementDataServiceUUIDsKey])
            XCTAssertEqual(advData[CBAdvertisementDataManufacturerDataKey] as? Data, manufacturerData)
            XCTAssertNotNil(advData[CBAdvertisementDataServiceDataKey])

            // Verify auto-generated fields are also present
            XCTAssertNotNil(advData[CBAdvertisementDataTxPowerLevelKey], "TxPowerLevel should be auto-generated")
            XCTAssertNotNil(advData[CBAdvertisementDataIsConnectable], "IsConnectable should be auto-generated")
        }
    }
}

// MARK: - Test Delegate

class AdvertisementTestCentralDelegate: NSObject, EmulatedCBCentralManagerDelegate {
    var discoveredPeripherals: [EmulatedCBPeripheral] = []
    var discoveredAdvertisements: [[String: Any]] = []

    func centralManagerDidUpdateState(_ central: EmulatedCBCentralManager) {
        // State updated
    }

    func centralManager(_ central: EmulatedCBCentralManager, didDiscover peripheral: EmulatedCBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        discoveredPeripherals.append(peripheral)
        discoveredAdvertisements.append(advertisementData)
    }
}

class AdvertisementTestPeripheralManagerDelegate: NSObject, EmulatedCBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: EmulatedCBPeripheralManager) {
        // State updated
    }
}
