# CoreBluetoothEmulator Complete Implementation Guide

## Overview

This document describes the complete implementation of advanced CoreBluetooth emulator features to achieve production-ready, real-device-compatible behavior.

## Architecture Enhancements

### 1. Scan Options Support

**Implementation Status**: ✅ Configuration Ready, ⏳ Logic Implementation Pending

**Design**:
- `EmulatorBus` tracks scan options per central
- `honorAllowDuplicatesOption`: When true, sends duplicate advertisements per scan interval
- `honorSolicitedServiceUUIDs`: When true, filters peripherals advertising solicited service UUIDs

**Files**:
- `EmulatorConfiguration.swift`: Configuration flags added
- `EmulatorBus.swift`: Scan option parsing in `startScanning`

**Implementation Notes**:
```swift
// In CentralRegistration struct
var scanOptions: [String: Any]?

// In scheduleDiscoveryNotifications
let allowDuplicates = config.honorAllowDuplicatesOption &&
    (scanOptions?[CBCentralManagerScanOptionAllowDuplicatesKey] as? Bool ?? false)

if allowDuplicates || !discoveredPeripheralIds.contains(peripheralId) {
    // Send advertisement
    if !allowDuplicates {
        discoveredPeripheralIds.insert(peripheralId)
    }
}
```

### 2. Full Advertisement Payload

**Implementation Status**: ✅ Partially Implemented, ⏳ Extended Keys Pending

**Current Support**:
- ✅ `CBAdvertisementDataLocalNameKey`
- ✅ `CBAdvertisementDataServiceUUIDsKey`

**Pending Keys**:
- `CBAdvertisementDataManufacturerDataKey`
- `CBAdvertisementDataServiceDataKey`
- `CBAdvertisementDataTxPowerLevelKey`
- `CBAdvertisementDataIsConnectable`
- `CBAdvertisementDataSolicitedServiceUUIDsKey`
- `CBAdvertisementDataOverflowServiceUUIDsKey`

**Usage Example**:
```swift
peripheralManager.startAdvertising([
    CBAdvertisementDataLocalNameKey: "MyDevice",
    CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
    CBAdvertisementDataManufacturerDataKey: manufacturerData,
    CBAdvertisementDataTxPowerLevelKey: -20,
    CBAdvertisementDataIsConnectable: true
])
```

### 3. Bidirectional Event Notifications

**Implementation Status**: ⏳ Pending

**Design**:
- Central disconnect → Peripheral Manager notified
- Peripheral disconnect → Central notified
- Subscription changes → Both sides updated

**Required Changes**:
```swift
// In EmulatorBus.disconnect
public func disconnect(centralIdentifier: UUID, peripheralIdentifier: UUID) async {
    // Existing: Remove connection
    connections[centralIdentifier]?.remove(peripheralIdentifier)

    // NEW: Notify peripheral manager
    if let peripheralReg = peripherals[peripheralIdentifier],
       let manager = peripheralReg.manager {
        await manager.notifyCentralDisconnected(centralIdentifier)
    }
}

// In EmulatedCBPeripheralManager
internal func notifyCentralDisconnected(_ centralIdentifier: UUID) async {
    // Find all subscribed characteristics for this central
    for service in services.values {
        for char in service.characteristics as? [EmulatedCBMutableCharacteristic] ?? [] {
            if let subscribers = char.subscribedCentrals {
                let central = subscribers.first { $0.identifier == centralIdentifier }
                if let central = central {
                    char.removeSubscribedCentral(central)
                    notifyDelegate { delegate in
                        delegate.peripheralManager(self, central: central,
                            didUnsubscribeFrom: char)
                    }
                }
            }
        }
    }
}
```

### 4. MTU Management

**Implementation Status**: ✅ Configuration Ready, ⏳ Per-Connection MTU Pending

**Design**:
- Per-connection MTU tracking
- Negotiation simulation
- `maximumWriteValueLength` returns correct value based on MTU

**Required State**:
```swift
// In EmulatorBus
private var connectionMTUs: [UUID: [UUID: Int]] = [:]  // central -> peripheral -> MTU

public func negotiateMTU(
    centralIdentifier: UUID,
    peripheralIdentifier: UUID,
    requestedMTU: Int
) async -> Int {
    let negotiated = min(requestedMTU, configuration.maximumMTU)
    var centralMTUs = connectionMTUs[centralIdentifier] ?? [:]
    centralMTUs[peripheralIdentifier] = negotiated
    connectionMTUs[centralIdentifier] = centralMTUs
    return negotiated
}

public func getMTU(
    centralIdentifier: UUID,
    peripheralIdentifier: UUID
) -> Int {
    return connectionMTUs[centralIdentifier]?[peripheralIdentifier] ?? configuration.defaultMTU
}
```

**In EmulatedCBPeripheral**:
```swift
public func maximumWriteValueLength(for type: CBCharacteristicWriteType) -> Int {
    let mtu = await EmulatorBus.shared.getMTU(
        centralIdentifier: centralManagerIdentifier,
        peripheralIdentifier: peripheralManagerIdentifier
    )
    return mtu - 3  // ATT header
}
```

### 5. Backpressure & Flow Control

**Implementation Status**: ⏳ Pending

**Design**:
- Write Without Response queue per peripheral
- Notification queue per characteristic
- `canSendWriteWithoutResponse` reflects queue state
- `peripheralIsReady(toSendWriteWithoutResponse:)` called when queue available

**Required State**:
```swift
// In EmulatorBus
private var writeWithoutResponseQueues: [UUID: [UUID: Int]] = [:]  // central -> peripheral -> count
private var notificationQueues: [UUID: [CBUUID: Int]] = [:]  // peripheral -> characteristic UUID -> count

public func canSendWriteWithoutResponse(
    centralIdentifier: UUID,
    peripheralIdentifier: UUID
) -> Bool {
    guard configuration.simulateBackpressure else { return true }
    let count = writeWithoutResponseQueues[centralIdentifier]?[peripheralIdentifier] ?? 0
    return count < configuration.maxWriteWithoutResponseQueue
}

public func enqueueWriteWithoutResponse(
    centralIdentifier: UUID,
    peripheralIdentifier: UUID
) async {
    guard configuration.simulateBackpressure else { return }
    var centralQueues = writeWithoutResponseQueues[centralIdentifier] ?? [:]
    let current = centralQueues[peripheralIdentifier] ?? 0
    centralQueues[peripheralIdentifier] = current + 1
    writeWithoutResponseQueues[centralIdentifier] = centralQueues
}

public func dequeueWriteWithoutResponse(
    centralIdentifier: UUID,
    peripheralIdentifier: UUID
) async {
    guard configuration.simulateBackpressure else { return }
    var centralQueues = writeWithoutResponseQueues[centralIdentifier] ?? [:]
    if let current = centralQueues[peripheralIdentifier], current > 0 {
        centralQueues[peripheralIdentifier] = current - 1
        writeWithoutResponseQueues[centralIdentifier] = centralQueues

        // Notify peripheral ready
        if let peripheral = centrals[centralIdentifier]?.manager?.discoveredPeripherals.values.first(where: {
            $0.peripheralManagerIdentifier == peripheralIdentifier
        }) {
            // Fire ready callback
            peripheral.canSendWriteWithoutResponse = true
            await centrals[centralIdentifier]?.manager?.notifyDelegate { delegate in
                delegate.peripheralIsReady?(toSendWriteWithoutResponse: peripheral)
            }
        }
    }
}
```

### 6. Security & Pairing

**Implementation Status**: ⏳ Pending

**Design**:
- Per-connection pairing state
- Encrypted characteristic access control
- Pairing process simulation with delay

**Required State**:
```swift
// In EmulatorBus
private var pairedConnections: Set<ConnectionPair> = []

struct ConnectionPair: Hashable {
    let centralIdentifier: UUID
    let peripheralIdentifier: UUID
}

public func requiresPairing(characteristic: EmulatedCBCharacteristic) -> Bool {
    return configuration.requirePairing &&
           (characteristic.properties.contains(.authenticatedSignedWrites) ||
            characteristic.permissions.contains(.readEncryptionRequired) ||
            characteristic.permissions.contains(.writeEncryptionRequired))
}

public func isPaired(
    centralIdentifier: UUID,
    peripheralIdentifier: UUID
) -> Bool {
    let pair = ConnectionPair(
        centralIdentifier: centralIdentifier,
        peripheralIdentifier: peripheralIdentifier
    )
    return pairedConnections.contains(pair)
}

public func pair(
    centralIdentifier: UUID,
    peripheralIdentifier: UUID
) async throws {
    guard configuration.simulatePairing else { return }

    if configuration.pairingDelay > 0 {
        try await Task.sleep(nanoseconds: UInt64(configuration.pairingDelay * 1_000_000_000))
    }

    guard configuration.pairingSucceeds else {
        throw CBError(.pairingNotSupported)
    }

    let pair = ConnectionPair(
        centralIdentifier: centralIdentifier,
        peripheralIdentifier: peripheralIdentifier
    )
    pairedConnections.insert(pair)
}
```

### 7. State Restoration

**Implementation Status**: ⏳ Pending

**Design**:
- Save central/peripheral state on key changes
- Restore on init with `restoreIdentifier`
- `willRestoreState` delegate calls

**Implementation Notes**:
```swift
// State structure
struct RestoredCentralState: Codable {
    let centralIdentifier: UUID
    let connectedPeripheralIdentifiers: [UUID]
    let scanServices: [String]?  // CBUUID data
}

struct RestoredPeripheralState: Codable {
    let peripheralIdentifier: UUID
    let isAdvertising: Bool
    let advertisementData: [String: Data]
}

// In EmulatorBus
private var restorationData: [String: Data] = [:]

public func saveStateForRestoration(
    identifier: String,
    state: Codable
) throws {
    let data = try JSONEncoder().encode(state)
    restorationData[identifier] = data
}

public func restoreState(
    identifier: String,
    as type: any Codable.Type
) throws -> any Codable {
    guard let data = restorationData[identifier] else {
        throw CBError(.unknown)
    }
    return try JSONDecoder().decode(type, from: data)
}
```

### 8. L2CAP Support

**Implementation Status**: ⏳ Stub Only

**Design**:
- PSM allocation registry
- Channel pair simulation
- Data streaming

**Note**: L2CAP requires significant additional infrastructure. For testing purposes, stub implementation returns errors unless `l2capSupported` is enabled.

### 9. Connection Events & ANCS

**Implementation Status**: ⏳ Pending

**Design**:
- Fire `connectionEventDidOccur` based on configuration
- Simulate ANCS authorization changes

**Implementation**:
```swift
// After connection established
if configuration.fireConnectionEvents {
    await central.notifyDelegate { delegate in
        delegate.centralManager?(
            central,
            connectionEventDidOccur: .peerConnected,
            for: peripheral
        )
    }
}

if configuration.fireANCSAuthorizationUpdates {
    // Simulate ANCS authorization
    Task {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await central.notifyDelegate { delegate in
            delegate.centralManager?(
                central,
                didUpdateANCSAuthorizationFor: peripheral
            )
        }
    }
}
```

## Testing Strategy

### Integration Test Suite

**File**: `Tests/CoreBluetoothEmulatorTests/IntegrationTests.swift`

**Test Coverage**:
1. Basic central-peripheral workflow
2. Scan option behavior (AllowDuplicates)
3. Service filtering
4. Connection/disconnection bidirectional events
5. Read/write with encryption requirements
6. Notification subscription
7. Backpressure scenarios
8. MTU negotiation
9. State restoration

### Example Test Structure

```swift
import XCTest
@testable import CoreBluetoothEmulator

final class IntegrationTests: XCTestCase {

    func testBasicWorkflow() async throws {
        // Configure instant mode for fast tests
        await EmulatorBus.shared.configure(.instant)

        // Setup peripheral
        let peripheralManager = EmulatedCBPeripheralManager(
            delegate: peripheralDelegate,
            queue: nil
        )

        let service = EmulatedCBMutableService(
            type: CBUUID(string: "1234"),
            primary: true
        )

        let characteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "5678"),
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )

        service.characteristics = [characteristic]
        peripheralManager.add(service)

        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "TestDevice",
            CBAdvertisementDataServiceUUIDsKey: [service.uuid]
        ])

        // Setup central
        let centralManager = EmulatedCBCentralManager(
            delegate: centralDelegate,
            queue: nil
        )

        // Wait for powered on
        await waitForPoweredOn(centralManager)

        // Scan
        centralManager.scanForPeripherals(withServices: [service.uuid], options: nil)

        // Wait for discovery
        let peripheral = try await waitForPeripheralDiscovery(centralDelegate)

        // Connect
        centralManager.connect(peripheral, options: nil)
        await waitForConnection(centralDelegate)

        // Discover services
        peripheral.discoverServices([service.uuid])
        await waitForServices(peripheralDelegate)

        // Read characteristic
        peripheral.readValue(for: characteristic)
        let value = try await waitForCharacteristicValue(peripheralDelegate)

        // Assert
        XCTAssertNotNil(value)
    }

    func testScanWithAllowDuplicates() async throws {
        var config = EmulatorConfiguration.instant
        config.honorAllowDuplicatesOption = true
        await EmulatorBus.shared.configure(config)

        // Setup and start advertising
        // ...

        // Scan with allow duplicates
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        // Should receive multiple discoveries for same peripheral
        let discoveries = try await waitForMultipleDiscoveries(centralDelegate, count: 3)
        XCTAssertEqual(discoveries.count, 3)
        XCTAssertEqual(Set(discoveries.map { $0.identifier }).count, 1)  // Same peripheral
    }

    func testBidirectionalDisconnect() async throws {
        // Setup connection
        // ...

        // Subscribe to characteristic
        peripheral.setNotifyValue(true, for: characteristic)
        await waitForSubscription(peripheralDelegate)

        // Disconnect from central
        centralManager.cancelPeripheralConnection(peripheral)

        // Peripheral should receive unsubscribe notification
        let unsubscribeEvent = try await waitForUnsubscribe(peripheralDelegate)
        XCTAssertEqual(unsubscribeEvent.characteristic.uuid, characteristic.uuid)
    }

    func testBackpressure() async throws {
        var config = EmulatorConfiguration.instant
        config.simulateBackpressure = true
        config.maxWriteWithoutResponseQueue = 3
        await EmulatorBus.shared.configure(config)

        // Setup and connect
        // ...

        // Send multiple write without response
        XCTAssertTrue(peripheral.canSendWriteWithoutResponse)

        for _ in 0..<3 {
            peripheral.writeValue(Data([0x01]), for: characteristic, type: .withoutResponse)
        }

        // Queue should be full
        XCTAssertFalse(peripheral.canSendWriteWithoutResponse)

        // Wait for queue to drain
        let readyNotification = try await waitForPeripheralReady(centralDelegate)
        XCTAssertTrue(peripheral.canSendWriteWithoutResponse)
    }
}
```

## Implementation Priority

Given the scope, recommended implementation priority:

1. ✅ **DONE**: Configuration infrastructure
2. 🔄 **HIGH**: Scan options (AllowDuplicates, SolicitedServiceUUIDs)
3. 🔄 **HIGH**: Full advertisement payload support
4. 🔄 **HIGH**: Bidirectional disconnect notifications
5. 🔄 **MEDIUM**: MTU management
6. 🔄 **MEDIUM**: Backpressure flow control
7. 🔄 **LOW**: Security/Pairing simulation
8. 🔄 **LOW**: State restoration
9. 🔄 **LOW**: L2CAP stub improvements
10. 🔄 **LOW**: Connection Events & ANCS

## Usage Examples

### Example 1: Testing with Backpressure

```swift
var config = EmulatorConfiguration.default
config.simulateBackpressure = true
config.maxWriteWithoutResponseQueue = 5
await EmulatorBus.shared.configure(config)

// Your test code will now experience realistic backpressure
```

### Example 2: Testing Scan Duplicates

```swift
var config = EmulatorConfiguration.instant
config.honorAllowDuplicatesOption = true
await EmulatorBus.shared.configure(config)

central.scanForPeripherals(
    withServices: nil,
    options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
)
// Will receive multiple discoveries for the same peripheral
```

### Example 3: Testing Encrypted Characteristics

```swift
var config = EmulatorConfiguration.default
config.requirePairing = true
config.simulatePairing = true
config.pairingSucceeds = true
await EmulatorBus.shared.configure(config)

// Attempting to read encrypted characteristic will trigger pairing
```

## Summary

This implementation guide provides a complete architecture for production-ready CoreBluetooth emulation. The configuration infrastructure is in place, and each feature can be implemented incrementally based on testing priorities.

Key benefits:
- ✅ Comprehensive configuration system
- ✅ Clear separation of concerns
- ✅ Testable design
- ✅ Real-device behavior simulation
- ✅ Progressive enhancement approach
