import XCTest
@testable import CoreBluetoothEmulator
import CoreBluetooth

@available(iOS 11.0, macOS 10.13, tvOS 11.0, watchOS 4.0, *)
final class L2CAPChannelTests: XCTestCase {
    var centralManager: EmulatedCBCentralManager!
    var peripheralManager: EmulatedCBPeripheralManager!
    var centralDelegate: L2CAPTestCentralDelegate!
    var peripheralManagerDelegate: L2CAPTestPeripheralManagerDelegate!

    override func setUp() async throws {
        await EmulatorBus.shared.reset()

        // Enable L2CAP support
        var config = EmulatorConfiguration.instant
        config.l2capSupported = true
        await EmulatorBus.shared.configure(config)

        centralDelegate = L2CAPTestCentralDelegate()
        peripheralManagerDelegate = L2CAPTestPeripheralManagerDelegate()

        centralManager = EmulatedCBCentralManager(delegate: centralDelegate, queue: nil)
        peripheralManager = EmulatedCBPeripheralManager(delegate: peripheralManagerDelegate, queue: nil)

        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func testPublishL2CAPChannel() async throws {
        // Peripheral publishes L2CAP channel
        peripheralManager.publishL2CAPChannel(withEncryption: false)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Verify PSM was assigned
        XCTAssertTrue(peripheralManagerDelegate.publishedPSMs.count > 0, "Should publish L2CAP channel")
        XCTAssertTrue(peripheralManagerDelegate.publishedPSMs.first! > 0, "PSM should be greater than 0")
    }

    func testOpenL2CAPChannel() async throws {
        let serviceUUID = CBUUID(string: "1100")
        let characteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "1101"),
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        let service = EmulatedCBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager.add(service)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Publish L2CAP channel
        peripheralManager.publishL2CAPChannel(withEncryption: false)

        try await Task.sleep(nanoseconds: 100_000_000)

        guard let psm = peripheralManagerDelegate.publishedPSMs.first else {
            XCTFail("Should publish L2CAP channel")
            return
        }

        // Start advertising
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "L2CAP Device",
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ])

        // Scan and connect
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)

        try await Task.sleep(nanoseconds: 100_000_000)

        guard let peripheral = centralDelegate.discoveredPeripherals.first else {
            XCTFail("Should discover peripheral")
            return
        }

        peripheral.delegate = centralDelegate

        centralManager.connect(peripheral, options: nil)

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(centralDelegate.connectedPeripherals.contains(peripheral))

        // Open L2CAP channel
        peripheral.openL2CAPChannel(psm)

        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify channel was opened on both sides
        XCTAssertTrue(centralDelegate.openedChannels.count > 0, "Central should receive opened channel")
        XCTAssertTrue(peripheralManagerDelegate.openedChannels.count > 0, "Peripheral should receive opened channel")

        // Verify PSM matches
        XCTAssertEqual(centralDelegate.openedChannels.first?.psm, psm, "PSM should match on central")
        XCTAssertEqual(peripheralManagerDelegate.openedChannels.first?.psm, psm, "PSM should match on peripheral")
    }

    func testOpenL2CAPChannelWithEncryption() async throws {
        let serviceUUID = CBUUID(string: "1200")
        let characteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "1201"),
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        let service = EmulatedCBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager.add(service)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Enable pairing
        var config = EmulatorConfiguration.instant
        config.l2capSupported = true
        config.simulatePairing = true
        config.pairingSucceeds = true
        await EmulatorBus.shared.configure(config)

        // Publish L2CAP channel with encryption
        peripheralManager.publishL2CAPChannel(withEncryption: true)

        try await Task.sleep(nanoseconds: 100_000_000)

        guard let psm = peripheralManagerDelegate.publishedPSMs.first else {
            XCTFail("Should publish L2CAP channel")
            return
        }

        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "Secure L2CAP Device",
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ])

        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)

        try await Task.sleep(nanoseconds: 100_000_000)

        guard let peripheral = centralDelegate.discoveredPeripherals.first else {
            XCTFail("Should discover peripheral")
            return
        }

        peripheral.delegate = centralDelegate

        centralManager.connect(peripheral, options: nil)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Open encrypted L2CAP channel - should trigger pairing
        peripheral.openL2CAPChannel(psm)

        try await Task.sleep(nanoseconds: 300_000_000)

        // Verify channel was opened after pairing
        XCTAssertTrue(centralDelegate.openedChannels.count > 0, "Should open channel after pairing")
    }

    func testUnpublishL2CAPChannel() async throws {
        // Publish channel
        peripheralManager.publishL2CAPChannel(withEncryption: false)

        try await Task.sleep(nanoseconds: 100_000_000)

        guard let psm = peripheralManagerDelegate.publishedPSMs.first else {
            XCTFail("Should publish L2CAP channel")
            return
        }

        // Unpublish channel
        peripheralManager.unpublishL2CAPChannel(psm)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Verify unpublish was called
        XCTAssertTrue(peripheralManagerDelegate.unpublishedPSMs.contains(psm), "Should unpublish channel")
    }

    func testOpenL2CAPChannelFailsWhenNotPublished() async throws {
        let serviceUUID = CBUUID(string: "1300")
        let characteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "1301"),
            properties: [.read],
            value: nil,
            permissions: [.readable]
        )

        let service = EmulatedCBMutableService(type: serviceUUID, primary: true)
        service.characteristics = [characteristic]
        peripheralManager.add(service)

        try await Task.sleep(nanoseconds: 100_000_000)

        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "No L2CAP Device",
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
        ])

        centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)

        try await Task.sleep(nanoseconds: 100_000_000)

        guard let peripheral = centralDelegate.discoveredPeripherals.first else {
            XCTFail("Should discover peripheral")
            return
        }

        peripheral.delegate = centralDelegate

        centralManager.connect(peripheral, options: nil)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Try to open unpublished channel
        let unpublishedPSM: CBL2CAPPSM = 99

        peripheral.openL2CAPChannel(unpublishedPSM)

        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify channel opening failed
        XCTAssertTrue(centralDelegate.channelErrors.count > 0, "Should receive error for unpublished channel")
        XCTAssertEqual(centralDelegate.openedChannels.count, 0, "Should not open unpublished channel")
    }
}

// MARK: - Test Delegates

@available(iOS 11.0, macOS 10.13, tvOS 11.0, watchOS 4.0, *)
class L2CAPTestCentralDelegate: NSObject, EmulatedCBCentralManagerDelegate, EmulatedCBPeripheralDelegate {
    var discoveredPeripherals: [EmulatedCBPeripheral] = []
    var connectedPeripherals: [EmulatedCBPeripheral] = []
    var openedChannels: [EmulatedCBL2CAPChannel] = []
    var channelErrors: [Error] = []

    func centralManagerDidUpdateState(_ central: EmulatedCBCentralManager) {}

    func centralManager(_ central: EmulatedCBCentralManager, didDiscover peripheral: EmulatedCBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        discoveredPeripherals.append(peripheral)
    }

    func centralManager(_ central: EmulatedCBCentralManager, didConnect peripheral: EmulatedCBPeripheral) {
        connectedPeripherals.append(peripheral)
    }

    func peripheral(_ peripheral: EmulatedCBPeripheral, didOpen channel: EmulatedCBL2CAPChannel?, error: Error?) {
        if let error = error {
            channelErrors.append(error)
        } else if let channel = channel {
            openedChannels.append(channel)
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: EmulatedCBPeripheral) {}
}

@available(iOS 11.0, macOS 10.13, tvOS 11.0, watchOS 4.0, *)
class L2CAPTestPeripheralManagerDelegate: NSObject, EmulatedCBPeripheralManagerDelegate {
    var publishedPSMs: [CBL2CAPPSM] = []
    var unpublishedPSMs: [CBL2CAPPSM] = []
    var openedChannels: [EmulatedCBL2CAPChannel] = []

    func peripheralManagerDidUpdateState(_ peripheral: EmulatedCBPeripheralManager) {}

    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, didPublishL2CAPChannel PSM: CBL2CAPPSM, error: Error?) {
        if error == nil {
            publishedPSMs.append(PSM)
        }
    }

    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, didUnpublishL2CAPChannel PSM: CBL2CAPPSM, error: Error?) {
        if error == nil {
            unpublishedPSMs.append(PSM)
        }
    }

    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, didOpen channel: EmulatedCBL2CAPChannel?, error: Error?) {
        if let channel = channel {
            openedChannels.append(channel)
        }
    }
}
