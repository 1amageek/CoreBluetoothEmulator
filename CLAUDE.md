# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CoreBluetoothEmulator is a pure-Swift implementation that fully emulates Apple's CoreBluetooth framework for hardware-free testing. The emulator provides real-device-compatible behavior, allowing developers to test BLE applications without physical hardware.

**Key Design Philosophy**: Uses `Emulated*` prefixed classes (e.g., `EmulatedCBCentralManager`) instead of type aliases. Users import `CoreBluetoothEmulator` for testing and `CoreBluetooth` for production. This approach was chosen over type aliases to avoid protocol conflicts and provide clearer API boundaries.

## Building and Testing

### Build
```bash
swift build
```

### Run Tests
```bash
swift test
```

### Run Specific Test
```bash
swift test --filter CoreBluetoothEmulatorTests.<TestClassName>/<testMethodName>
```

## Architecture

### Core Actor: EmulatorBus

`EmulatorBus` is the central actor that coordinates all emulated devices. It is implemented as a singleton actor for thread-safe state management.

**Key Responsibilities:**
- Device registration (centrals and peripherals)
- Advertisement routing from peripherals to scanning centrals
- Connection management between centrals and peripherals
- Message routing for read/write operations
- Event scheduling with configurable delays

**State Management:**
- `centrals`: Tracks all registered central managers with their scan state
- `peripherals`: Tracks all registered peripheral managers with advertisement data
- `connections`: Maps central UUIDs to sets of connected peripheral UUIDs
- `scanningCentrals`: Set of central UUIDs currently scanning
- `advertisingPeripherals`: Set of peripheral UUIDs currently advertising
- `connectionMTUs`: Per-connection MTU tracking
- `writeWithoutResponseQueues`: Backpressure queue state for write-without-response
- `notificationQueues`: Backpressure queue state for notifications

### Communication Flow

All cross-device communication flows through `EmulatorBus`:

1. **Scanning/Advertising**: Central calls `scanForPeripherals()` → EmulatorBus matches with advertising peripherals → Central receives `didDiscover` callback
2. **Connection**: Central calls `connect()` → EmulatorBus establishes connection → Both sides notified
3. **Service Discovery**: Peripheral calls `discoverServices()` → EmulatorBus retrieves from peripheral manager → Peripheral receives `didDiscoverServices`
4. **Read/Write**: Peripheral sends request → EmulatorBus routes to peripheral manager → Response routed back through EmulatorBus

### Class Hierarchy

```
EmulatedCBCentralManager (Central role manager)
└── EmulatedCBPeripheral (Central's view of remote peripheral)
    └── EmulatedCBService
        └── EmulatedCBCharacteristic
            └── EmulatedCBDescriptor

EmulatedCBPeripheralManager (Peripheral role manager)
└── EmulatedCBMutableService
    └── EmulatedCBMutableCharacteristic
        └── EmulatedCBMutableDescriptor

EmulatedCBCentral (Peripheral's view of connected central)
```

### Threading Model

- **EmulatorBus**: Actor-based isolation ensures thread-safe state access
- **Delegate Callbacks**: Always dispatched on the queue specified during initialization (or main queue if nil)
- **Internal Operations**: All EmulatorBus method calls use `Task {}` to bridge sync/async boundaries

## Configuration System

`EmulatorConfiguration` controls all timing, behavior, and error simulation:

**Preset Configurations:**
- `.default`: Realistic timing for development
- `.instant`: No delays for fast unit testing
- `.slow`: Simulates poor connection conditions
- `.unreliable`: Includes random errors and failures

**Key Configuration Options:**
- Timing delays for all operations (state updates, discovery, read/write)
- RSSI simulation (range and variation)
- Error simulation (connection failures, read/write errors)
- MTU settings (default: 185, max: 512)
- Backpressure simulation for write-without-response and notifications
- Scan behavior options (honor allow duplicates, solicited services)

Configure via:
```swift
await EmulatorBus.shared.configure(.instant)  // For tests
```

## Implementation Status Reference

### ✅ Production Ready (All 11 integration tests passing)
- Central Manager: Scanning, connecting, service/characteristic/descriptor discovery
- Peripheral Manager: Advertising, service hosting, read/write handling
- GATT Operations: Read, write, notify/indicate
- Connection Management: Connect, disconnect, state tracking
- Notifications: Subscription management with isNotifying state
- Scan Options: AllowDuplicatesKey (requires config), SolicitedServiceUUIDs (requires config)
- Advertisement Payload: Passthrough for all standard keys + auto-generation of TxPowerLevel and IsConnectable
- Bidirectional Events: Disconnect notifications to both sides, auto-unsubscribe
- Connection Events (iOS 13+): CBConnectionEvent support for peer connect/disconnect (requires `fireConnectionEvents = true`)
- MTU Management: Per-connection dynamic tracking (default 185, max 512)
- Backpressure Flow Control: Write-without-response and notification queues (requires `simulateBackpressure = true`)
- Permission Control: Read/write permission validation
- Connection Validation: Operations fail correctly when disconnected
- Service Filtering: Proper UUID-based filtering
- Subscription Management: Per-characteristic subscriber tracking with cleanup on disconnect
- State Restoration: Full restoration for Central and Peripheral managers (requires `stateRestorationEnabled = true`)
- Security/Pairing: Auto-pairing simulation (matches CoreBluetooth behavior)

**Configuration Flags Required**:
- Scan options work by default (`honorAllowDuplicatesOption = true` by default)
- Connection events require `fireConnectionEvents = true`
- Backpressure requires `simulateBackpressure = true`
- State restoration requires `stateRestorationEnabled = true`
- Advertisement auto-generation enabled by default (`autoGenerateAdvertisementFields = true`)
- See `README.md` Configuration Requirements section for full details

### ⏳ Future Enhancements
- L2CAP Channels: Configuration exists, full channel logic not implemented
- ANCS Authorization: Configuration flag only, no implementation
- Advanced Latency: setDesiredConnectionLatency method exists but does nothing

**IMPORTANT**: See `IMPLEMENTATION_STATUS.md` for detailed analysis of what's implemented vs user expectations.

## Important Implementation Notes

### Delegate Protocol Pattern

The emulator defines custom delegate protocols (e.g., `EmulatedCBCentralManagerDelegate`) that mirror CoreBluetooth but use emulated types. All delegate methods have default implementations, so implementers only need to define methods they use.

### Async/Sync Bridge Pattern

Most public APIs are synchronous (matching CoreBluetooth), but internally use `Task {}` blocks to call async EmulatorBus methods. Delegate callbacks are always scheduled asynchronously on the configured queue:

```swift
public func connect(_ peripheral: EmulatedCBPeripheral, options: [String: Any]? = nil) {
    Task {
        await EmulatorBus.shared.connect(
            centralIdentifier: identifier,
            peripheralIdentifier: peripheral.identifier,
            options: options
        )
    }
}
```

### State Transitions

State changes in managers (e.g., `.unknown` → `.poweredOn`) are scheduled with configurable delays. Tests typically use `.instant` configuration to skip delays.

### Backpressure Implementation

The emulator simulates CoreBluetooth's backpressure behavior:
- **Write Without Response**: Queues fill up, `canSendWriteWithoutResponse` becomes false, `peripheralIsReadyToSendWriteWithoutResponse` called when drained
- **Notifications**: Queues track pending notifications, `peripheralManagerIsReadyToUpdateSubscribers` called when ready

## Documentation Structure

- `README.md`: User-facing documentation with quick start and examples
- `docs/CoreBluetooth_Architecture.md`: Apple CoreBluetooth framework reference
- `docs/Emulator_Design.md`: Original design document (Japanese)
- `docs/IMPLEMENTATION_GUIDE.md`: Detailed implementation status and architecture
- `docs/RECOMMENDED_APPROACH.md`: Type alias pattern discussion (Japanese) - Note: Final implementation uses `Emulated*` prefix approach instead
- `docs/REVISED_APPROACH.md`: Additional design considerations

## Testing Patterns

Integration tests in `Tests/CoreBluetoothEmulatorTests/` demonstrate common patterns:

1. **Basic Communication**: Create central and peripheral, scan, connect, discover, read/write
2. **Notifications**: Set up subscriptions, send notifications, verify reception
3. **Multiple Connections**: Multiple centrals to one peripheral
4. **Error Scenarios**: Test connection failures, read/write errors, permission errors
5. **Scan Behavior**: Test duplicate filtering, service UUID filtering

**Common Test Setup Pattern:**
```swift
// Configure for instant timing
await EmulatorBus.shared.configure(.instant)

// Create peripheral manager and add services
let peripheralManager = EmulatedCBPeripheralManager(delegate: peripheralDelegate, queue: nil)
peripheralManager.add(service)
peripheralManager.startAdvertising(advertisementData)

// Create central manager and scan
let centralManager = EmulatedCBCentralManager(delegate: centralDelegate, queue: nil)
centralManager.scanForPeripherals(withServices: serviceUUIDs, options: options)

// Wait for discovery (use async expectations or continuations)
// Connect, discover services/characteristics, perform operations
```

## Code Location Guide

**Core Infrastructure:**
- `Sources/CoreBluetoothEmulator/EmulatorBus.swift`: Central coordinator actor
- `Sources/CoreBluetoothEmulator/EmulatorConfiguration.swift`: Configuration and presets
- `Sources/CoreBluetoothEmulator/CoreBluetoothEmulator.swift`: Public API entry point

**Central Role:**
- `Sources/CoreBluetoothEmulator/Internal/EmulatedCBCentralManager.swift`: Central manager implementation
- `Sources/CoreBluetoothEmulator/Internal/EmulatedCBPeripheral.swift`: Central's view of peripheral

**Peripheral Role:**
- `Sources/CoreBluetoothEmulator/Internal/EmulatedCBPeripheralManager.swift`: Peripheral manager implementation
- `Sources/CoreBluetoothEmulator/Internal/EmulatedCBCentral.swift`: Peripheral's view of central

**GATT Types:**
- `Sources/CoreBluetoothEmulator/Internal/EmulatedCBService.swift`: Service classes (read-only and mutable)
- `Sources/CoreBluetoothEmulator/Internal/EmulatedCBCharacteristic.swift`: Characteristic classes
- `Sources/CoreBluetoothEmulator/Internal/EmulatedCBDescriptor.swift`: Descriptor classes

**Protocols:**
- `Sources/CoreBluetoothEmulator/EmulatedDelegates.swift`: All emulated delegate protocols with default implementations

## Language and Documentation

- Code: English (comments, variable names, documentation)
- Design documents in `docs/`: Mix of English and Japanese
- When Japanese docs conflict with code, the code is authoritative
