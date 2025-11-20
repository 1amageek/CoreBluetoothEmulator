import XCTest
@testable import CoreBluetoothEmulator
import CoreBluetooth

final class FullWorkflowTests: XCTestCase {
    func testCompleteWorkflow() async throws {
        await EmulatorBus.shared.reset()
        await EmulatorBus.shared.configure(.instant)

        // MARK: - Setup Peripheral

        let peripheralManagerDelegate = WorkflowPeripheralManagerDelegate()
        let peripheralManager = EmulatedCBPeripheralManager(
            delegate: peripheralManagerDelegate,
            queue: nil
        )

        try await Task.sleep(nanoseconds: 100_000_000)

        // Create service and characteristics
        let service = EmulatedCBMutableService(type: CBUUID(string: "180D"), primary: true)

        let readCharacteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "2A37"),
            properties: [.read],
            value: Data([0x01, 0x02, 0x03]),
            permissions: [.readable]
        )

        let writeCharacteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "2A38"),
            properties: [.write],
            value: nil,
            permissions: [.writeable]
        )

        let notifyCharacteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "2A39"),
            properties: [.notify],
            value: nil,
            permissions: [.readable]
        )

        service.characteristics = [readCharacteristic, writeCharacteristic, notifyCharacteristic]
        peripheralManager.add(service)

        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "Heart Rate Monitor",
            CBAdvertisementDataServiceUUIDsKey: [service.uuid]
        ])

        // MARK: - Setup Central

        let centralDelegate = WorkflowCentralDelegate()
        let centralManager = EmulatedCBCentralManager(delegate: centralDelegate, queue: nil)

        try await Task.sleep(nanoseconds: 100_000_000)

        // MARK: - Scan and Discover

        centralManager.scanForPeripherals(withServices: [service.uuid], options: nil)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(centralDelegate.discoveredPeripherals.count, 1)

        guard let (peripheral, advertisementData, _) = centralDelegate.discoveredPeripherals.first else {
            XCTFail("Should discover peripheral")
            return
        }

        // Verify advertisement data
        XCTAssertEqual(advertisementData[CBAdvertisementDataLocalNameKey] as? String, "Heart Rate Monitor")

        centralManager.stopScan()

        // MARK: - Connect

        centralManager.connect(peripheral, options: nil)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(peripheral.state, .connected)
        XCTAssertEqual(centralDelegate.connectedPeripherals.count, 1)

        // MARK: - Service Discovery

        let peripheralDelegate = WorkflowPeripheralDelegate()
        peripheral.delegate = peripheralDelegate

        peripheral.discoverServices([service.uuid])
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(peripheralDelegate.discoveredServices.count, 1)
        guard let discoveredService = peripheral.services?.first else {
            XCTFail("Should have service")
            return
        }

        XCTAssertEqual(discoveredService.uuid, service.uuid)

        // MARK: - Characteristic Discovery

        peripheral.discoverCharacteristics(nil, for: discoveredService)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(peripheralDelegate.discoveredCharacteristics.count, 1)
        guard let characteristics = discoveredService.characteristics else {
            XCTFail("Should have characteristics")
            return
        }

        XCTAssertEqual(characteristics.count, 3)

        let read = characteristics.first { $0.uuid == readCharacteristic.uuid }!
        let write = characteristics.first { $0.uuid == writeCharacteristic.uuid }!
        let notify = characteristics.first { $0.uuid == notifyCharacteristic.uuid }!

        // MARK: - Read Operation

        peripheral.readValue(for: read)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(peripheralManagerDelegate.readRequests.count, 1)
        XCTAssertEqual(read.value, Data([0x01, 0x02, 0x03]))

        // MARK: - Write Operation

        peripheral.writeValue(Data([0x04, 0x05]), for: write, type: .withResponse)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(peripheralManagerDelegate.writeRequests.count, 1)
        XCTAssertEqual(peripheralDelegate.writtenCharacteristics.count, 1)

        // MARK: - Notification Subscription

        peripheral.setNotifyValue(true, for: notify)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(notify.isNotifying)
        XCTAssertEqual(peripheralManagerDelegate.subscribeCallbacks.count, 1)

        // Clear previous updates from reads
        peripheralDelegate.updatedValues.removeAll()

        // Send notification
        peripheralManager.updateValue(Data([0x06, 0x07]), for: notifyCharacteristic, onSubscribedCentrals: nil)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(peripheralDelegate.updatedValues.count, 1)
        XCTAssertEqual(peripheralDelegate.updatedValues.first?.1, Data([0x06, 0x07]))

        // MARK: - Unsubscribe

        peripheral.setNotifyValue(false, for: notify)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(notify.isNotifying)
        XCTAssertEqual(peripheralManagerDelegate.unsubscribeCallbacks.count, 1)

        // MARK: - Disconnect

        centralManager.cancelPeripheralConnection(peripheral)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(peripheral.state, .disconnected)
        XCTAssertEqual(centralDelegate.disconnectedPeripherals.count, 1)
    }
}

// MARK: - Test Delegates

class WorkflowCentralDelegate: EmulatedCBCentralManagerDelegate {
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

class WorkflowPeripheralDelegate: EmulatedCBPeripheralDelegate {
    var discoveredServices: [[EmulatedCBService]] = []
    var discoveredCharacteristics: [(EmulatedCBService, [EmulatedCBCharacteristic])] = []
    var updatedValues: [(EmulatedCBCharacteristic, Data?)] = []
    var writtenCharacteristics: [EmulatedCBCharacteristic] = []

    func peripheral(_ peripheral: EmulatedCBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            discoveredServices.append(services)
        }
    }

    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didDiscoverCharacteristicsFor service: EmulatedCBService,
        error: Error?
    ) {
        if let characteristics = service.characteristics {
            discoveredCharacteristics.append((service, characteristics))
        }
    }

    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didUpdateValueFor characteristic: EmulatedCBCharacteristic,
        error: Error?
    ) {
        updatedValues.append((characteristic, characteristic.value))
    }

    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didWriteValueFor characteristic: EmulatedCBCharacteristic,
        error: Error?
    ) {
        writtenCharacteristics.append(characteristic)
    }
}

class WorkflowPeripheralManagerDelegate: EmulatedCBPeripheralManagerDelegate {
    var readRequests: [EmulatedCBATTRequest] = []
    var writeRequests: [[EmulatedCBATTRequest]] = []
    var subscribeCallbacks: [(EmulatedCBCentral, EmulatedCBCharacteristic)] = []
    var unsubscribeCallbacks: [(EmulatedCBCentral, EmulatedCBCharacteristic)] = []

    func peripheralManagerDidUpdateState(_ peripheral: EmulatedCBPeripheralManager) {}

    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, didReceiveRead request: EmulatedCBATTRequest) {
        readRequests.append(request)
    }

    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, didReceiveWrite requests: [EmulatedCBATTRequest]) {
        writeRequests.append(requests)
    }

    func peripheralManager(
        _ peripheral: EmulatedCBPeripheralManager,
        central: EmulatedCBCentral,
        didSubscribeTo characteristic: EmulatedCBCharacteristic
    ) {
        subscribeCallbacks.append((central, characteristic))
    }

    func peripheralManager(
        _ peripheral: EmulatedCBPeripheralManager,
        central: EmulatedCBCentral,
        didUnsubscribeFrom characteristic: EmulatedCBCharacteristic
    ) {
        unsubscribeCallbacks.append((central, characteristic))
    }
}
