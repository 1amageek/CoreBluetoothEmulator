# CoreBluetooth Emulator Design

## Overview

CoreBluetoothEmulatorは、実際のBluetooth硬件を必要とせずにCoreBluetoothのAPIをエミュレートするフレームワークです。テストやシミュレーションに使用できます。

## Design Goals

1. **API互換性**: 実際のCoreBluetoothと同じAPIを提供
2. **同期的な動作**: 実際のBLEの非同期性をエミュレート
3. **柔軟性**: テストシナリオに応じて動作をカスタマイズ可能
4. **In-Memoryベース**: プロセス内で複数のCentral/Peripheralをシミュレート

## Architecture Components

### 1. Emulator Core

```
EmulatorBus (Singleton)
├── Centrals: [EmulatedCBCentralManager]
├── Peripherals: [EmulatedCBPeripheralManager]
└── EventDispatcher
```

#### EmulatorBus

すべてのエミュレートされたデバイス間の通信を管理。

**責務:**
- Central/Peripheralの登録・管理
- アドバタイジングパケットのルーティング
- 接続管理
- データ転送

**主要メソッド:**
```swift
actor EmulatorBus {
    static let shared = EmulatorBus()

    // デバイス管理
    func register(central: EmulatedCBCentralManager)
    func register(peripheral: EmulatedCBPeripheralManager)
    func unregister(central: EmulatedCBCentralManager)
    func unregister(peripheral: EmulatedCBPeripheralManager)

    // スキャニング
    func startScanning(central: EmulatedCBCentralManager, services: [CBUUID]?)
    func stopScanning(central: EmulatedCBCentralManager)

    // アドバタイジング
    func startAdvertising(peripheral: EmulatedCBPeripheralManager, data: [String: Any])
    func stopAdvertising(peripheral: EmulatedCBPeripheralManager)

    // 接続
    func connect(central: EmulatedCBCentralManager, peripheral: EmulatedCBPeripheral)
    func disconnect(central: EmulatedCBCentralManager, peripheral: EmulatedCBPeripheral)

    // データ転送
    func sendRead(from central: EmulatedCBPeripheral, request: CBATTRequest)
    func sendWrite(from central: EmulatedCBPeripheral, requests: [CBATTRequest])
    func sendResponse(from peripheral: EmulatedCBPeripheralManager, to request: CBATTRequest)
    func sendNotification(from peripheral: EmulatedCBPeripheralManager, value: Data, characteristic: CBCharacteristic, centrals: [CBCentral]?)
}
```

### 2. Central Side Classes

#### EmulatedCBCentralManager

```swift
public class EmulatedCBCentralManager: NSObject, @unchecked Sendable {
    public weak var delegate: (any CBCentralManagerDelegate)?
    public private(set) var state: CBManagerState = .unknown
    public private(set) var isScanning: Bool = false

    private let queue: DispatchQueue
    private var discoveredPeripherals: [UUID: EmulatedCBPeripheral] = [:]
    private var connectedPeripherals: Set<UUID> = []

    public init(delegate: (any CBCentralManagerDelegate)?, queue: DispatchQueue?, options: [String: Any]? = nil)

    // スキャニング
    public func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]? = nil)
    public func stopScan()

    // 接続管理
    public func connect(_ peripheral: EmulatedCBPeripheral, options: [String: Any]? = nil)
    public func cancelPeripheralConnection(_ peripheral: EmulatedCBPeripheral)

    // Peripheral検索
    public func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [EmulatedCBPeripheral]
    public func retrieveConnectedPeripherals(withServices serviceUUIDs: [CBUUID]) -> [EmulatedCBPeripheral]

    // 機能サポート
    public class func supports(_ features: Feature) -> Bool
}
```

**状態管理:**
- 初期化時に自動的に `.poweredOn` に遷移（遅延あり）
- オプションで `.poweredOff` や `.unauthorized` などをシミュレート可能

**スキャン動作:**
- スキャン開始時に `EmulatorBus` に登録
- アドバタイジング中のPeripheralを定期的に発見
- デリゲートに `didDiscover` を非同期で通知

#### EmulatedCBPeripheral

```swift
public class EmulatedCBPeripheral: NSObject, @unchecked Sendable {
    public let identifier: UUID
    public var name: String?
    public weak var delegate: (any CBPeripheralDelegate)?
    public private(set) var state: CBPeripheralState = .disconnected
    public private(set) var services: [EmulatedCBService]?
    public var canSendWriteWithoutResponse: Bool = true

    private let queue: DispatchQueue
    private weak var manager: EmulatedCBPeripheralManager?

    // サービス探索
    public func discoverServices(_ serviceUUIDs: [CBUUID]?)
    public func discoverIncludedServices(_ includedServiceUUIDs: [CBUUID]?, for service: EmulatedCBService)

    // Characteristic探索
    public func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: EmulatedCBService)

    // Descriptor探索
    public func discoverDescriptors(for characteristic: EmulatedCBCharacteristic)

    // 読み書き
    public func readValue(for characteristic: EmulatedCBCharacteristic)
    public func writeValue(_ data: Data, for characteristic: EmulatedCBCharacteristic, type: CBCharacteristicWriteType)
    public func readValue(for descriptor: EmulatedCBDescriptor)
    public func writeValue(_ data: Data, for descriptor: EmulatedCBDescriptor)

    // 通知
    public func setNotifyValue(_ enabled: Bool, for characteristic: EmulatedCBCharacteristic)

    // RSSI
    public func readRSSI()
}
```

**接続動作:**
- 接続リクエストは `EmulatorBus` を通じてPeripheralに伝達
- 非同期で接続完了を通知
- 切断時もデリゲートに通知

### 3. Peripheral Side Classes

#### EmulatedCBPeripheralManager

```swift
public class EmulatedCBPeripheralManager: NSObject, @unchecked Sendable {
    public weak var delegate: (any CBPeripheralManagerDelegate)?
    public private(set) var state: CBManagerState = .unknown
    public private(set) var isAdvertising: Bool = false

    private let queue: DispatchQueue
    private var services: [UUID: EmulatedCBMutableService] = [:]
    private var subscribedCentrals: [UUID: Set<UUID>] = [:]  // characteristic UUID -> central UUIDs

    public init(delegate: (any CBPeripheralManagerDelegate)?, queue: DispatchQueue?, options: [String: Any]? = nil)

    // サービス管理
    public func add(_ service: EmulatedCBMutableService)
    public func remove(_ service: EmulatedCBMutableService)
    public func removeAllServices()

    // アドバタイジング
    public func startAdvertising(_ advertisementData: [String: Any]?)
    public func stopAdvertising()

    // 値更新
    @discardableResult
    public func updateValue(_ value: Data, for characteristic: EmulatedCBMutableCharacteristic, onSubscribedCentrals centrals: [EmulatedCBCentral]?) -> Bool

    // リクエスト応答
    public func respond(to request: CBATTRequest, withResult result: CBATTError.Code)

    // 接続レイテンシ
    public func setDesiredConnectionLatency(_ latency: CBPeripheralManagerConnectionLatency, for central: EmulatedCBCentral)
}
```

**アドバタイジング動作:**
- アドバタイジング開始時に `EmulatorBus` に登録
- スキャン中のCentralに定期的に発見される
- カスタムアドバタイジングデータをサポート

**リクエスト処理:**
- Centralからの読み書きリクエストをデリゲートに転送
- `respond(to:withResult:)` でATTエラーをシミュレート可能

#### EmulatedCBCentral

```swift
public class EmulatedCBCentral: NSObject, @unchecked Sendable {
    public let identifier: UUID
    public let maximumUpdateValueLength: Int

    init(identifier: UUID, maximumUpdateValueLength: Int = 512)
}
```

### 4. GATT Classes

#### EmulatedCBService

```swift
public class EmulatedCBService: NSObject, @unchecked Sendable {
    public let uuid: CBUUID
    public let isPrimary: Bool
    public weak var peripheral: EmulatedCBPeripheral?
    public var includedServices: [EmulatedCBService]?
    public var characteristics: [EmulatedCBCharacteristic]?

    init(uuid: CBUUID, isPrimary: Bool)
}
```

#### EmulatedCBMutableService

```swift
public class EmulatedCBMutableService: EmulatedCBService {
    public override init(type uuid: CBUUID, primary: Bool)
    public var characteristics: [EmulatedCBCharacteristic]?
    public var includedServices: [EmulatedCBService]?
}
```

#### EmulatedCBCharacteristic

```swift
public class EmulatedCBCharacteristic: NSObject, @unchecked Sendable {
    public let uuid: CBUUID
    public weak var service: EmulatedCBService?
    public let properties: CBCharacteristicProperties
    public var value: Data?
    public var descriptors: [EmulatedCBDescriptor]?
    public private(set) var isNotifying: Bool = false

    init(uuid: CBUUID, properties: CBCharacteristicProperties, value: Data?, permissions: CBAttributePermissions)
}
```

#### EmulatedCBMutableCharacteristic

```swift
public class EmulatedCBMutableCharacteristic: EmulatedCBCharacteristic {
    public let permissions: CBAttributePermissions
    public var subscribedCentrals: [EmulatedCBCentral]?

    public override init(type uuid: CBUUID, properties: CBCharacteristicProperties, value: Data?, permissions: CBAttributePermissions)
}
```

#### EmulatedCBDescriptor

```swift
public class EmulatedCBDescriptor: NSObject, @unchecked Sendable {
    public let uuid: CBUUID
    public weak var characteristic: EmulatedCBCharacteristic?
    public var value: Any?

    init(uuid: CBUUID, value: Any?)
}
```

#### EmulatedCBMutableDescriptor

```swift
public class EmulatedCBMutableDescriptor: EmulatedCBDescriptor {
    public override init(type uuid: CBUUID, value: Any?)
}
```

### 5. Configuration & Testing Support

#### EmulatorConfiguration

```swift
public struct EmulatorConfiguration {
    // タイミング設定
    public var stateUpdateDelay: TimeInterval = 0.1
    public var scanDiscoveryInterval: TimeInterval = 0.5
    public var connectionDelay: TimeInterval = 0.2
    public var disconnectionDelay: TimeInterval = 0.1
    public var serviceDiscoveryDelay: TimeInterval = 0.15
    public var characteristicDiscoveryDelay: TimeInterval = 0.15
    public var descriptorDiscoveryDelay: TimeInterval = 0.15
    public var readDelay: TimeInterval = 0.05
    public var writeDelay: TimeInterval = 0.05
    public var notificationDelay: TimeInterval = 0.05

    // RSSI設定
    public var rssiRange: ClosedRange<Int> = -80...(-40)
    public var rssiVariation: Int = 5

    // エラーシミュレーション
    public var simulateConnectionFailure: Bool = false
    public var connectionFailureRate: Double = 0.0
    public var simulateReadWriteErrors: Bool = false
    public var readWriteErrorRate: Double = 0.0

    // バックグラウンドモード
    public var backgroundModeEnabled: Bool = false

    public static var `default`: EmulatorConfiguration
    public static var instant: EmulatorConfiguration  // 遅延なし（テスト用）
}
```

#### EmulatorTestHelper

```swift
public class EmulatorTestHelper {
    // ペア生成
    public static func createCentralPeripheralPair() -> (EmulatedCBCentralManager, EmulatedCBPeripheralManager)

    // サービス生成
    public static func createService(uuid: CBUUID, characteristics: [EmulatedCBMutableCharacteristic]) -> EmulatedCBMutableService

    // Characteristic生成
    public static func createCharacteristic(uuid: CBUUID, properties: CBCharacteristicProperties, permissions: CBAttributePermissions, value: Data?) -> EmulatedCBMutableCharacteristic

    // 接続待機ヘルパー
    public static func waitForConnection(central: EmulatedCBCentralManager, peripheral: EmulatedCBPeripheral, timeout: TimeInterval) async throws

    // サービス探索待機ヘルパー
    public static func waitForServiceDiscovery(peripheral: EmulatedCBPeripheral, timeout: TimeInterval) async throws -> [EmulatedCBService]
}
```

## Communication Flow

### Scanning and Discovery

```
Central                    EmulatorBus              Peripheral
  |                            |                        |
  |-- scanForPeripherals ---->|                        |
  |                            |                        |
  |                            |<-- startAdvertising ---|
  |                            |                        |
  |                            |--- (定期的にマッチング) ---|
  |                            |                        |
  |<-- didDiscover ------------|                        |
  |    (非同期)                  |                        |
```

### Connection Establishment

```
Central                    EmulatorBus              Peripheral
  |                            |                        |
  |-- connect(peripheral) ---->|                        |
  |                            |                        |
  |                            |-- (接続確立) ----------->|
  |                            |                        |
  |<-- didConnect -------------|                        |
  |    (非同期)                  |                        |
  |                            |-- didSubscribeTo ------>|
  |                            |    (if subscription)    |
```

### Service & Characteristic Discovery

```
Central                    EmulatorBus              Peripheral
  |                            |                        |
  |-- discoverServices ------->|                        |
  |                            |                        |
  |                            |-- (サービス取得) -------->|
  |                            |                        |
  |<-- didDiscoverServices ----|                        |
  |    (非同期)                  |                        |
  |                            |                        |
  |-- discoverCharacteristics->|                        |
  |                            |                        |
  |                            |-- (Characteristic取得)->|
  |                            |                        |
  |<-- didDiscoverCharacteristics|                      |
  |    (非同期)                  |                        |
```

### Read Operation

```
Central                    EmulatorBus              Peripheral
  |                            |                        |
  |-- readValue -------------->|                        |
  |                            |                        |
  |                            |-- didReceiveRead ------>|
  |                            |                        |
  |                            |<-- respond(to:) --------|
  |                            |                        |
  |<-- didUpdateValue ---------|                        |
  |    (非同期)                  |                        |
```

### Write Operation

```
Central                    EmulatorBus              Peripheral
  |                            |                        |
  |-- writeValue ------------->|                        |
  |                            |                        |
  |                            |-- didReceiveWrite ----->|
  |                            |                        |
  |                            |<-- respond(to:) --------|
  |                            |                        |
  |<-- didWriteValue ----------|                        |
  |    (非同期)                  |                        |
```

### Notification

```
Central                    EmulatorBus              Peripheral
  |                            |                        |
  |-- setNotifyValue(true) --->|                        |
  |                            |                        |
  |                            |-- didSubscribeTo ------>|
  |                            |                        |
  |<-- didUpdateNotificationState|                      |
  |    (非同期)                  |                        |
  |                            |                        |
  |                            |<-- updateValue ---------|
  |                            |                        |
  |<-- didUpdateValue ---------|                        |
  |    (通知)                    |                        |
```

## Threading Model

### Queue Management

すべてのデリゲートコールバックは指定されたDispatchQueueで実行:

```swift
// Centralマネージャー
let queue = DispatchQueue(label: "com.example.central")
let central = EmulatedCBCentralManager(delegate: self, queue: queue)

// Peripheralマネージャー
let peripheralQueue = DispatchQueue(label: "com.example.peripheral")
let peripheral = EmulatedCBPeripheralManager(delegate: self, queue: peripheralQueue)
```

### EmulatorBus Actor

`EmulatorBus` はactorとして実装し、内部状態のスレッドセーフを保証:

```swift
actor EmulatorBus {
    private var centrals: [UUID: EmulatedCBCentralManager] = [:]
    private var peripherals: [UUID: EmulatedCBPeripheralManager] = [:]
    private var connections: [UUID: Set<UUID>] = [:]  // central UUID -> peripheral UUIDs

    // すべてのメソッドは自動的にactor isolationで保護される
}
```

## Error Simulation

### Connection Errors

```swift
configuration.simulateConnectionFailure = true
configuration.connectionFailureRate = 0.3  // 30%の確率で失敗

// 接続試行時に確率的にエラーを発生
central.connect(peripheral)
// -> 30%の確率で didFailToConnect が呼ばれる
```

### Read/Write Errors

```swift
configuration.simulateReadWriteErrors = true
configuration.readWriteErrorRate = 0.1  // 10%の確率で失敗

peripheral.readValue(for: characteristic)
// -> 10%の確率で CBATTError が発生
```

### Custom Error Injection

```swift
// 特定のCharacteristicでエラーをシミュレート
EmulatorBus.shared.setError(
    .insufficientAuthentication,
    for: characteristicUUID,
    in: peripheralUUID
)
```

## Testing Scenarios

### Basic Central-Peripheral Communication

```swift
func testBasicCommunication() async throws {
    let config = EmulatorConfiguration.instant
    EmulatorBus.shared.configure(config)

    // Peripheral側
    let peripheralManager = EmulatedCBPeripheralManager(delegate: peripheralDelegate, queue: nil)
    let service = createService()
    peripheralManager.add(service)
    peripheralManager.startAdvertising(nil)

    // Central側
    let centralManager = EmulatedCBCentralManager(delegate: centralDelegate, queue: nil)
    centralManager.scanForPeripherals(withServices: nil)

    // 発見待機
    let peripheral = try await waitForDiscovery()

    // 接続
    centralManager.connect(peripheral)
    try await waitForConnection()

    // サービス探索
    peripheral.discoverServices(nil)
    let services = try await waitForServices()

    // Characteristic探索
    peripheral.discoverCharacteristics(nil, for: services[0])
    let characteristics = try await waitForCharacteristics()

    // 読み取り
    peripheral.readValue(for: characteristics[0])
    let value = try await waitForValue()

    XCTAssertEqual(value, expectedValue)
}
```

### Multiple Centrals to Single Peripheral

```swift
func testMultipleCentrals() async throws {
    // 1つのPeripheralに複数のCentralが接続
    let peripheral = createPeripheral()
    let central1 = createCentral()
    let central2 = createCentral()

    try await connectAll([central1, central2], to: peripheral)

    // 通知をテスト
    peripheral.updateValue(data, for: characteristic, onSubscribedCentrals: nil)

    // 両方のCentralが通知を受信
    try await waitForNotification(on: central1)
    try await waitForNotification(on: central2)
}
```

### Error Recovery

```swift
func testConnectionFailureRecovery() async throws {
    config.simulateConnectionFailure = true
    config.connectionFailureRate = 1.0  // 必ず失敗

    central.connect(peripheral)

    // エラーを待機
    try await waitForConnectionError()

    // リトライ（今度は成功させる）
    config.connectionFailureRate = 0.0
    central.connect(peripheral)
    try await waitForConnection()
}
```

## Platform Compatibility

### macOS
- Full support
- NSObject ベース

### iOS/iPadOS
- Full support
- Background mode simulation

### watchOS/tvOS
- Advertising制限をエミュレート
- Read-only operations

### Linux (Swift 6+)
- Foundation互換性に依存
- NSObject依存を最小化

## Future Enhancements

### 1. L2CAP Channel Support
```swift
peripheral.publishL2CAPChannel(withEncryption: true)
central.openL2CAPChannel(psm)
```

### 2. State Restoration
```swift
// バックグラウンド復帰のシミュレート
central = EmulatedCBCentralManager(
    delegate: self,
    queue: nil,
    options: [CBCentralManagerOptionRestoreIdentifierKey: "my-central"]
)
```

### 3. ANCS (Apple Notification Center Service)
```swift
// ANCS認証のシミュレート
func centralManager(_ central: CBCentralManager, didUpdateANCSAuthorizationFor peripheral: CBPeripheral)
```

### 4. Extended Advertising
```swift
// Bluetooth 5.0 拡張アドバタイジング
peripheralManager.startAdvertising([
    CBAdvertisementDataExtendedKey: true,
    CBAdvertisementDataPrimaryPHYKey: CBPHY.le2M
])
```

### 5. Network Simulation
```swift
// 複数プロセス間でのエミュレート（IPC/ネットワーク経由）
EmulatorBus.shared.enableNetworkMode(port: 8080)
```

## Implementation Priority

### Phase 1: Core Foundation (Current)
- [x] EmulatorBus基本設計
- [ ] EmulatedCBCentralManager
- [ ] EmulatedCBPeripheralManager
- [ ] EmulatedCBPeripheral
- [ ] Basic GATT classes

### Phase 2: Full GATT Support
- [ ] Service/Characteristic/Descriptor完全実装
- [ ] Read/Write operations
- [ ] Notifications/Indications
- [ ] RSSI simulation

### Phase 3: Advanced Features
- [ ] Error simulation
- [ ] Configuration system
- [ ] Test helpers
- [ ] Performance optimization

### Phase 4: Extended Features
- [ ] L2CAP channels
- [ ] State restoration
- [ ] Background modes
- [ ] Extended advertising
