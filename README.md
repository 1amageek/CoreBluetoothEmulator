# CoreBluetoothEmulator

A comprehensive CoreBluetooth emulator for iOS/macOS that provides hardware-free testing with real-device-compatible behavior.

## Overview

CoreBluetoothEmulator is a pure-Swift implementation that emulates the full CoreBluetooth framework, allowing you to:
- Test BLE applications without physical hardware
- Simulate various network conditions and error scenarios
- Run automated tests in CI/CD pipelines
- Develop and debug BLE features faster

## Features

### ✅ Fully Implemented (Production Ready)

#### Core Functionality
- **Central Manager**: Scanning, connecting, service/characteristic discovery
- **Peripheral Manager**: Advertising, service hosting, read/write handling
- **GATT Operations**: Read, write, notify/indicate support
- **Service Discovery**: Services, characteristics, descriptors
- **Connection Management**: Connect, disconnect, connection state tracking
- **Notifications**: Characteristic value updates with subscription management

#### Advanced Features
- **Scan Options**: Full support for CBCentralManagerScanOption
  - AllowDuplicatesKey: Honors duplicate advertisement delivery (requires `honorAllowDuplicatesOption = true`)
  - SolicitedServiceUUIDsKey: Filters by solicited services (requires `honorSolicitedServiceUUIDs = true`)
- **Advertisement Payload**: Complete passthrough support for all standard advertisement keys
  - LocalName, ServiceUUIDs, SolicitedServiceUUIDs, OverflowServiceUUIDs
  - ManufacturerData, ServiceData
  - TxPowerLevel, IsConnectable
  - Note: Unlike real CoreBluetooth, the emulator passes through all fields as-is without auto-generation
- **Bidirectional Events**: Disconnect notifications to both central and peripheral
  - Auto-unsubscribe on disconnect
  - Proper cleanup of subscriptions
- **Connection Events** (iOS 13+): CBConnectionEvent support for peer connect/disconnect
  - Requires `fireConnectionEvents = true` in configuration
  - Register with `centralManager.registerForConnectionEvents(options:)`
- **MTU Management**: Per-connection MTU tracking and negotiation (default: 185, max: 512)
- **Backpressure Flow Control**:
  - Write Without Response queue management (requires `simulateBackpressure = true`)
  - Notification queue management (requires `simulateBackpressure = true`)
  - peripheralIsReady and peripheralManagerIsReady callbacks
- **Permission Control**: Read/write permissions for characteristics and descriptors
- **Connection Validation**: Operations fail correctly when not connected
- **Service Filtering**: Proper filtering by service UUIDs
- **Subscription Management**: isNotifying state and subscriber tracking

#### Configuration System
- **Timing Control**: Configurable delays for all operations
- **RSSI Simulation**: Realistic signal strength with variation
- **Error Simulation**: Connection failures, read/write errors
- **MTU Settings**: Default and maximum MTU configuration (implemented)
- **Backpressure**: Queue limits for Write Without Response and notifications (implemented)
- **Scan Behavior**: Honor real CoreBluetooth scan options (implemented)
- **Security**: Pairing and encryption simulation settings (configuration ready)
- **Background Mode**: State preservation settings (configuration ready)

### 🔄 Partial Implementation

- **Security/Pairing**: Configuration ready, pairing process implementation pending
- **State Restoration**: Infrastructure ready, save/restore implementation pending

### ⏳ Future Enhancements

- **L2CAP Channels**: Configuration and delegate methods exist, implementation pending
- **ANCS Authorization**: Authorization update events
- **Advanced Latency**: setDesiredConnectionLatency implementation
- **Complete State Restoration**: Infrastructure exists, actual save/restore implementation pending

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/CoreBluetoothEmulator", from: "1.0.0")
]
```

## Quick Start

### 30-Second Tutorial

```swift
import CoreBluetoothEmulator

// 1. Configure emulator (.instant recommended for tests)
await EmulatorBus.shared.configure(.instant)

// 2. Create peripheral
let peripheralManager = EmulatedCBPeripheralManager(delegate: peripheralDelegate, queue: nil)
let service = EmulatedCBMutableService(type: CBUUID(string: "1234"), primary: true)
let characteristic = EmulatedCBMutableCharacteristic(
    type: CBUUID(string: "5678"),
    properties: [.read, .write, .notify],
    value: Data([0x01, 0x02]),
    permissions: [.readable, .writeable]
)
service.characteristics = [characteristic]
peripheralManager.add(service)
peripheralManager.startAdvertising([
    CBAdvertisementDataLocalNameKey: "My Device",
    CBAdvertisementDataServiceUUIDsKey: [service.uuid]
])

// 3. Create central and start scanning
let centralManager = EmulatedCBCentralManager(delegate: centralDelegate, queue: nil)
centralManager.scanForPeripherals(withServices: nil, options: nil)

// 4. Handle connection and operations in delegates
// → See complete examples below for details
```

## Complete Usage Guide

### 1. Peripheral Implementation (Device Side)

```swift
import CoreBluetoothEmulator
import CoreBluetooth

class MyPeripheralManager: EmulatedCBPeripheralManagerDelegate {
    var peripheralManager: EmulatedCBPeripheralManager!
    var heartRateCharacteristic: EmulatedCBMutableCharacteristic!

    func setup() async {
        // Configure emulator (.default for development, .instant for tests)
        await EmulatorBus.shared.configure(.default)

        // Create peripheral manager
        peripheralManager = EmulatedCBPeripheralManager(delegate: self, queue: nil)

        // Define service and characteristics
        let service = EmulatedCBMutableService(
            type: CBUUID(string: "180D"),  // Heart Rate Service
            primary: true
        )

        heartRateCharacteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "2A37"),  // Heart Rate Measurement
            properties: [.read, .notify],
            value: nil,
            permissions: [.readable]
        )

        let controlCharacteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "2A39"),  // Control Point
            properties: [.write],
            value: nil,
            permissions: [.writeable]
        )

        service.characteristics = [heartRateCharacteristic, controlCharacteristic]
        peripheralManager.add(service)

        // Start advertising (all fields can be specified)
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "Heart Rate Monitor",
            CBAdvertisementDataServiceUUIDsKey: [service.uuid],
            CBAdvertisementDataManufacturerDataKey: Data([0x4C, 0x00, 0x01, 0x02]),
            CBAdvertisementDataTxPowerLevelKey: NSNumber(value: -20),
            CBAdvertisementDataIsConnectable: NSNumber(value: true)
        ])
    }

    // MARK: - Delegate Methods

    func peripheralManagerDidUpdateState(_ peripheral: EmulatedCBPeripheralManager) {
        print("Peripheral state: \(peripheral.state.rawValue)")
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: EmulatedCBPeripheralManager, error: Error?) {
        if let error = error {
            print("Advertising failed: \(error)")
        } else {
            print("Advertising started")
        }
    }

    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, didAdd service: EmulatedCBService, error: Error?) {
        if let error = error {
            print("Failed to add service: \(error)")
        } else {
            print("Service added: \(service.uuid)")
        }
    }

    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, central: EmulatedCBCentral, didSubscribeTo characteristic: EmulatedCBCharacteristic) {
        print("Central subscribed to \(characteristic.uuid)")
        // Send periodic updates when subscribed
        sendHeartRateUpdate()
    }

    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, central: EmulatedCBCentral, didUnsubscribeFrom characteristic: EmulatedCBCharacteristic) {
        print("Central unsubscribed from \(characteristic.uuid)")
    }

    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, didReceiveRead request: EmulatedCBATTRequest) {
        print("Received read request for \(request.characteristic.uuid)")
        // Value is already set in characteristic, returned automatically
    }

    func peripheralManager(_ peripheral: EmulatedCBPeripheralManager, didReceiveWrite requests: [EmulatedCBATTRequest]) {
        for request in requests {
            if let value = request.value {
                print("Received write: \(value.map { String(format: "%02x", $0) }.joined())")
                // Process written value
                handleControlCommand(value)
            }
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: EmulatedCBPeripheralManager) {
        print("Ready to send more notifications")
        // Queue has space, can send next notification
    }

    // MARK: - Helper Methods

    func sendHeartRateUpdate() {
        let heartRate: UInt8 = UInt8.random(in: 60...100)
        let data = Data([0x00, heartRate])  // Flags + Heart Rate Value

        let success = peripheralManager.updateValue(
            data,
            for: heartRateCharacteristic,
            onSubscribedCentrals: nil
        )

        if success {
            print("Sent heart rate: \(heartRate) bpm")
        } else {
            print("Failed to send - queue full")
        }
    }

    func handleControlCommand(_ data: Data) {
        // Process command
        print("Processing command: \(data)")
    }
}
```

### 2. Central Implementation (App Side)

```swift
import CoreBluetoothEmulator
import CoreBluetooth

class MyCentralManager: EmulatedCBCentralManagerDelegate, EmulatedCBPeripheralDelegate {
    var centralManager: EmulatedCBCentralManager!
    var discoveredPeripheral: EmulatedCBPeripheral?
    var heartRateCharacteristic: EmulatedCBCharacteristic?

    func setup() async {
        // Configure emulator
        await EmulatorBus.shared.configure(.default)

        // Create central manager
        centralManager = EmulatedCBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        centralManager.scanForPeripherals(
            withServices: [CBUUID(string: "180D")],  // Heart Rate Service
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        print("Started scanning")
    }

    // MARK: - Central Manager Delegate

    func centralManagerDidUpdateState(_ central: EmulatedCBCentralManager) {
        print("Central state: \(central.state.rawValue)")

        if central.state == .poweredOn {
            startScanning()
        }
    }

    func centralManager(
        _ central: EmulatedCBCentralManager,
        didDiscover peripheral: EmulatedCBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        print("Discovered: \(peripheral.name ?? "Unknown") RSSI: \(RSSI)")
        print("Advertisement data: \(advertisementData)")

        // Access each field of advertisement data
        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            print("  Name: \(name)")
        }
        if let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            print("  Services: \(services)")
        }
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            print("  Manufacturer: \(manufacturerData.map { String(format: "%02x", $0) }.joined())")
        }

        // Connect to first discovered device
        discoveredPeripheral = peripheral
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: EmulatedCBCentralManager, didConnect peripheral: EmulatedCBPeripheral) {
        print("Connected to \(peripheral.name ?? "Unknown")")

        // Set peripheral delegate
        peripheral.delegate = self

        // Discover services
        peripheral.discoverServices([CBUUID(string: "180D")])
    }

    func centralManager(
        _ central: EmulatedCBCentralManager,
        didFailToConnect peripheral: EmulatedCBPeripheral,
        error: Error?
    ) {
        print("Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
    }

    func centralManager(
        _ central: EmulatedCBCentralManager,
        didDisconnectPeripheral peripheral: EmulatedCBPeripheral,
        error: Error?
    ) {
        print("Disconnected: \(error?.localizedDescription ?? "User initiated")")
    }

    // MARK: - Peripheral Delegate

    func peripheral(_ peripheral: EmulatedCBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Service discovery failed: \(error)")
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            print("Found service: \(service.uuid)")
            // Discover characteristics
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didDiscoverCharacteristicsFor service: EmulatedCBService,
        error: Error?
    ) {
        if let error = error {
            print("Characteristic discovery failed: \(error)")
            return
        }

        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            print("Found characteristic: \(characteristic.uuid)")
            print("  Properties: \(characteristic.properties.rawValue)")

            if characteristic.uuid == CBUUID(string: "2A37") {
                // Heart Rate Measurement
                heartRateCharacteristic = characteristic

                // Read value
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic)
                }

                // Subscribe to notifications
                if characteristic.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }

    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didUpdateValueFor characteristic: EmulatedCBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            print("Failed to read value: \(error)")
            return
        }

        guard let data = characteristic.value else { return }

        if characteristic.uuid == CBUUID(string: "2A37") {
            // Heart Rate Measurement
            if data.count >= 2 {
                let heartRate = data[1]
                print("Heart Rate: \(heartRate) bpm")
            }
        }
    }

    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didWriteValueFor characteristic: EmulatedCBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            print("Write failed: \(error)")
        } else {
            print("Write succeeded")
        }
    }

    func peripheral(
        _ peripheral: EmulatedCBPeripheral,
        didUpdateNotificationStateFor characteristic: EmulatedCBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            print("Notification subscription failed: \(error)")
        } else {
            print("Notifications \(characteristic.isNotifying ? "enabled" : "disabled")")
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: EmulatedCBPeripheral) {
        print("Ready to send more writes without response")
    }

    // MARK: - Operations

    func writeControlCommand(_ command: Data) {
        guard let peripheral = discoveredPeripheral,
              let service = peripheral.services?.first,
              let controlChar = service.characteristics?.first(where: { $0.uuid == CBUUID(string: "2A39") }) else {
            return
        }

        peripheral.writeValue(command, for: controlChar, type: .withResponse)
    }
}
```

## Configuration Presets

### Default Configuration
Realistic timing for development:
```swift
await EmulatorBus.shared.configure(.default)
```

### Instant Configuration
No delays for fast unit testing:
```swift
await EmulatorBus.shared.configure(.instant)
```

### Slow Configuration
Simulates poor connection:
```swift
await EmulatorBus.shared.configure(.slow)
```

### Unreliable Configuration
Simulates errors and failures:
```swift
await EmulatorBus.shared.configure(.unreliable)
```

### Custom Configuration
```swift
var config = EmulatorConfiguration.default
config.simulateBackpressure = true
config.maxWriteWithoutResponseQueue = 10
config.honorAllowDuplicatesOption = true
await EmulatorBus.shared.configure(config)
```

## Configuration Requirements

Some features require specific configuration flags to be enabled. This table shows what needs to be configured for each feature:

| Feature | Configuration Flag | Default Value | Notes |
|---------|-------------------|---------------|-------|
| **AllowDuplicatesKey** | `honorAllowDuplicatesOption` | `true` | Controls duplicate advertisement delivery |
| **SolicitedServiceUUIDs** | `honorSolicitedServiceUUIDs` | `true` | Filters peripherals by solicited services |
| **Connection Events** | `fireConnectionEvents` | `false` | Must also call `registerForConnectionEvents()` |
| **Backpressure Simulation** | `simulateBackpressure` | `false` | Enables queue management for writes/notifications |
| **Connection Failures** | `simulateConnectionFailure` | `false` | Randomly fails connections based on rate |
| **Read/Write Errors** | `simulateReadWriteErrors` | `false` | Randomly fails operations based on rate |
| **Pairing** | `simulatePairing` | `false` | Simulates pairing process with delay |
| **State Restoration** | `stateRestorationEnabled` | `false` | Enables state save/restore (partial) |

**Important Notes**:
- Most features work without configuration changes using sensible defaults
- Scan options (AllowDuplicates, SolicitedServices) are enabled by default
- Advertisement data passthrough works automatically - no configuration needed
- Connection events and backpressure require explicit enablement for realistic simulation

## Advanced Usage

### Testing Scan Duplicates

```swift
var config = EmulatorConfiguration.instant
config.honorAllowDuplicatesOption = true
await EmulatorBus.shared.configure(config)

centralManager.scanForPeripherals(
    withServices: nil,
    options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
)
// Will receive multiple discoveries for the same peripheral
```

### Full Advertisement Data

```swift
peripheralManager.startAdvertising([
    CBAdvertisementDataLocalNameKey: "My Device",
    CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
    CBAdvertisementDataManufacturerDataKey: Data([0x4C, 0x00, 0x01, 0x02]),
    CBAdvertisementDataTxPowerLevelKey: NSNumber(value: -20),
    CBAdvertisementDataIsConnectable: NSNumber(value: true)
])
```

### Testing Error Scenarios

```swift
var config = EmulatorConfiguration.default
config.simulateConnectionFailure = true
config.connectionFailureRate = 0.3  // 30% failure rate
config.simulateReadWriteErrors = true
config.readWriteErrorRate = 0.1  // 10% error rate
await EmulatorBus.shared.configure(config)
```

### Connection Events (iOS 13+)

```swift
// Enable connection events in configuration
var config = EmulatorConfiguration.default
config.fireConnectionEvents = true
await EmulatorBus.shared.configure(config)

// Register for connection events
if #available(iOS 13.0, *) {
    centralManager.registerForConnectionEvents(options: nil)
}

// Implement delegate method
@available(iOS 13.0, *)
func centralManager(
    _ central: EmulatedCBCentralManager,
    connectionEventDidOccur event: CBConnectionEvent,
    for peripheral: EmulatedCBPeripheral
) {
    switch event {
    case .peerConnected:
        print("Peer connected: \(peripheral.identifier)")
    case .peerDisconnected:
        print("Peer disconnected: \(peripheral.identifier)")
    @unknown default:
        break
    }
}
```

### Backpressure Testing

```swift
// Enable backpressure simulation
var config = EmulatorConfiguration.default
config.simulateBackpressure = true
config.maxWriteWithoutResponseQueue = 10
config.maxNotificationQueue = 10
config.backpressureProcessingDelay = 0.1  // 100ms per item
await EmulatorBus.shared.configure(config)

// Check before writing without response
if peripheral.canSendWriteWithoutResponse {
    peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
}

// Implement ready callback
func peripheralIsReady(toSendWriteWithoutResponse peripheral: EmulatedCBPeripheral) {
    // Queue has space, can send more writes
}

// For peripheral manager notifications
func peripheralManagerIsReady(toUpdateSubscribers peripheral: EmulatedCBPeripheralManager) {
    // Queue has space, can send more notifications
    let success = peripheral.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
}
```

## Common Use Cases

### Testing

```swift
import XCTest
@testable import YourApp
import CoreBluetoothEmulator

class BluetoothTests: XCTestCase {
    var centralManager: EmulatedCBCentralManager!
    var peripheralManager: EmulatedCBPeripheralManager!

    override func setUp() async throws {
        // Reset emulator before each test
        await EmulatorBus.shared.reset()

        // Configure for fast testing
        await EmulatorBus.shared.configure(.instant)

        // Create test managers
        centralManager = EmulatedCBCentralManager(delegate: centralDelegate, queue: nil)
        peripheralManager = EmulatedCBPeripheralManager(delegate: peripheralDelegate, queue: nil)
    }

    func testDiscoveryAndConnection() async throws {
        // Setup peripheral
        let service = EmulatedCBMutableService(type: CBUUID(string: "1234"), primary: true)
        peripheralManager.add(service)
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "Test Device",
            CBAdvertisementDataServiceUUIDsKey: [service.uuid]
        ])

        // Start scanning
        centralManager.scanForPeripherals(withServices: nil, options: nil)

        // Wait for discovery
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        // Assert
        XCTAssertEqual(centralDelegate.discoveredPeripherals.count, 1)
    }
}
```

### Switching Between Production and Test Code

```swift
// Abstract with protocol
protocol BluetoothCentralManager {
    func scanForPeripherals(withServices: [CBUUID]?, options: [String: Any]?)
    func connect(_ peripheral: BluetoothPeripheral, options: [String: Any]?)
    // ...
}

// Real hardware implementation
class RealCentralManager: BluetoothCentralManager {
    private let manager: CBCentralManager

    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?) {
        manager.scanForPeripherals(withServices: serviceUUIDs, options: options)
    }
    // ...
}

// Emulator implementation
class EmulatedCentralManager: BluetoothCentralManager {
    private let manager: EmulatedCBCentralManager

    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?) {
        manager.scanForPeripherals(withServices: serviceUUIDs, options: options)
    }
    // ...
}

// Switch using DI
class App {
    let bluetoothManager: BluetoothCentralManager

    init(useEmulator: Bool = false) {
        if useEmulator {
            bluetoothManager = EmulatedCentralManager()
        } else {
            bluetoothManager = RealCentralManager()
        }
    }
}
```

### MTU Management

```swift
// Get MTU on iOS 15+
if #available(iOS 15.0, *) {
    let currentMTU = peripheral.mtu
    print("Current MTU: \(currentMTU)")

    // Calculate maximum write size
    let maxWriteLength = peripheral.maximumWriteValueLength(for: .withResponse)
    print("Max write length: \(maxWriteLength)")
}

// Send data considering MTU
func sendLargeData(_ data: Data, to characteristic: EmulatedCBCharacteristic) {
    let maxLength = peripheral.maximumWriteValueLength(for: .withoutResponse)
    var offset = 0

    while offset < data.count {
        let chunkSize = min(maxLength, data.count - offset)
        let chunk = data.subdata(in: offset..<offset + chunkSize)

        // Check backpressure
        if peripheral.canSendWriteWithoutResponse {
            peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
            offset += chunkSize
        } else {
            // Queue is full, wait
            print("Queue full, waiting...")
            break
        }
    }
}
```

### Error Handling

```swift
// Simulate connection errors
var config = EmulatorConfiguration.default
config.simulateConnectionFailure = true
config.connectionFailureRate = 0.3  // 30% failure rate
await EmulatorBus.shared.configure(config)

// Handle in delegate
func centralManager(
    _ central: EmulatedCBCentralManager,
    didFailToConnect peripheral: EmulatedCBPeripheral,
    error: Error?
) {
    if let error = error as? CBError {
        switch error.code {
        case .connectionFailed:
            print("Connection failed, retrying...")
            // Retry logic
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                central.connect(peripheral, options: nil)
            }
        default:
            print("Other error: \(error)")
        }
    }
}

// Simulate read/write errors
config.simulateReadWriteErrors = true
config.readWriteErrorRate = 0.1  // 10% error rate

func peripheral(
    _ peripheral: EmulatedCBPeripheral,
    didUpdateValueFor characteristic: EmulatedCBCharacteristic,
    error: Error?
) {
    if let error = error as? CBATTError {
        switch error.code {
        case .readNotPermitted:
            print("Read not permitted")
        case .insufficientAuthentication:
            print("Authentication required")
        default:
            print("ATT error: \(error)")
        }
    }
}
```

## Troubleshooting

### Issue: Device Not Discovered

**Causes and Solutions:**

1. **Emulator not configured**
   ```swift
   // Solution: Configure explicitly
   await EmulatorBus.shared.configure(.instant)
   ```

2. **Peripheral not advertising**
   ```swift
   // Check: Verify isAdvertising
   print("Is advertising: \(peripheralManager.isAdvertising)")

   // Solution: Call startAdvertising
   peripheralManager.startAdvertising([
       CBAdvertisementDataLocalNameKey: "Device",
       CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
   ])
   ```

3. **Filtered by service UUID**
   ```swift
   // Problematic code
   centralManager.scanForPeripherals(
       withServices: [CBUUID(string: "1234")],  // Only devices with this service
       options: nil
   )

   // Solution: Scan for all devices
   centralManager.scanForPeripherals(withServices: nil, options: nil)
   ```

### Issue: Notifications Not Received

**Causes and Solutions:**

1. **Characteristic missing notify property**
   ```swift
   // Problem
   let char = EmulatedCBMutableCharacteristic(
       type: uuid,
       properties: [.read],  // Missing notify
       value: nil,
       permissions: [.readable]
   )

   // Solution
   let char = EmulatedCBMutableCharacteristic(
       type: uuid,
       properties: [.read, .notify],  // Add notify
       value: nil,
       permissions: [.readable]
   )
   ```

2. **Not subscribed**
   ```swift
   // Solution: Call setNotifyValue
   peripheral.setNotifyValue(true, for: characteristic)
   ```

3. **Sending before subscription completes**
   ```swift
   // Problem: Send immediately
   peripheral.setNotifyValue(true, for: characteristic)
   peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: nil)

   // Solution: Wait for delegate callback
   func peripheralManager(
       _ peripheral: EmulatedCBPeripheralManager,
       central: EmulatedCBCentral,
       didSubscribeTo characteristic: EmulatedCBCharacteristic
   ) {
       // Send here
       peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
   }
   ```

### Issue: Write Without Response Cannot Send

**Causes and Solutions:**

1. **Backpressure enabled and queue full**
   ```swift
   // Check
   if !peripheral.canSendWriteWithoutResponse {
       print("Queue is full")
   }

   // Solution: Wait for ready callback
   func peripheralIsReady(toSendWriteWithoutResponse peripheral: EmulatedCBPeripheral) {
       // Resend here
       peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
   }
   ```

2. **Disable backpressure (for testing)**
   ```swift
   var config = EmulatorConfiguration.instant
   config.simulateBackpressure = false  // No queue limit
   await EmulatorBus.shared.configure(config)
   ```

### Issue: updateValue Returns false

**Causes and Solutions:**

Notification queue is full:

```swift
// Check: Verify updateValue return value
let success = peripheralManager.updateValue(
    data,
    for: characteristic,
    onSubscribedCentrals: nil
)

if !success {
    print("Notification queue full")
}

// Solution: Wait for ready callback
func peripheralManagerIsReady(toUpdateSubscribers peripheral: EmulatedCBPeripheralManager) {
    // Queue has space
    let success = peripheral.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
}
```

### Issue: Timing-Related Test Failures

**Solutions:**

1. **Use .instant configuration**
   ```swift
   await EmulatorBus.shared.configure(.instant)
   ```

2. **Add appropriate wait times**
   ```swift
   // Bad example
   centralManager.scanForPeripherals(withServices: nil, options: nil)
   XCTAssertEqual(discoveredDevices.count, 1)  // Check immediately

   // Good example
   centralManager.scanForPeripherals(withServices: nil, options: nil)
   try await Task.sleep(nanoseconds: 100_000_000)  // Wait 100ms
   XCTAssertEqual(discoveredDevices.count, 1)
   ```

### Issue: Test Interference with Multiple Tests

**Solution:**

Reset before each test:

```swift
override func setUp() async throws {
    await EmulatorBus.shared.reset()  // Important!
    await EmulatorBus.shared.configure(.instant)
}
```

## Best Practices

### 1. Configuration Selection

- **Development**: `.default` - Realistic timing for verification
- **Unit Tests**: `.instant` - Fast execution
- **Integration Tests**: `.default` or `.slow` - Conditions close to real hardware
- **Load Tests**: `.unreliable` - Verify error handling

### 2. Test Isolation

```swift
// Reset for each test
override func setUp() async throws {
    await EmulatorBus.shared.reset()
}

// For tests requiring specific configuration
func testSlowConnection() async throws {
    await EmulatorBus.shared.configure(.slow)
    // Test...
}
```

### 3. Error Handling

Check errors in all delegate methods:

```swift
func peripheral(
    _ peripheral: EmulatedCBPeripheral,
    didDiscoverServices error: Error?
) {
    if let error = error {
        // Handle error
        return
    }
    // Normal processing
}
```

### 4. Resource Management

```swift
// Stop scanning when not needed
centralManager.stopScan()

// Disconnect
centralManager.cancelPeripheralConnection(peripheral)

// Stop advertising
peripheralManager.stopAdvertising()
```

## Delegate Protocols

The emulator provides custom delegate protocols that mirror CoreBluetooth but use emulated types:

- `EmulatedCBCentralManagerDelegate`
- `EmulatedCBPeripheralDelegate`
- `EmulatedCBPeripheralManagerDelegate`

All methods have default implementations, so you only need to implement the ones you use.

## Architecture

### EmulatorBus
Central actor that coordinates all emulated devices and their interactions. Handles:
- Device registration
- Connection management
- Message routing
- Event scheduling

### EmulatedCBCentralManager
Emulates CBCentralManager for the central role:
- Scanning for peripherals
- Connection/disconnection
- Service and characteristic discovery

### EmulatedCBPeripheralManager
Emulates CBPeripheralManager for the peripheral role:
- Advertising
- Service hosting
- Handling read/write requests
- Sending notifications

### EmulatedCBPeripheral
Central's view of a remote peripheral:
- Service discovery
- Read/write operations
- Notification subscription

## Testing

Comprehensive integration tests are provided in `Tests/CoreBluetoothEmulatorTests/`.

Run tests:
```bash
swift test
```

## Implementation Status

See [IMPLEMENTATION_GUIDE.md](docs/IMPLEMENTATION_GUIDE.md) for detailed implementation status and architecture documentation.

## Documentation

- [Implementation Guide](docs/IMPLEMENTATION_GUIDE.md) - Complete architecture and implementation details
- [CoreBluetooth Architecture](docs/CoreBluetooth_Architecture.md) - CoreBluetooth framework reference
- [Emulator Design](docs/Emulator_Design.md) - Original design document

## Requirements

- Swift 5.9+
- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+

## License

MIT License

## Contributing

Contributions are welcome! Please see CONTRIBUTING.md for guidelines.

## Acknowledgments

This emulator is designed for testing purposes and does not replace actual hardware testing. Always verify your implementation on real Bluetooth hardware before production deployment.
