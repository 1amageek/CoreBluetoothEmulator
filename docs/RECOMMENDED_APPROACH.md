# 推奨アプローチ: Type Alias パターン

## 問題

現在の設計では `EmulatedCBCentralManager` という別の型を作っているため、既存のCoreBluetoothコードをそのままテストできない。

## 解決策: Type Alias + Module Replacement

実際の `CBCentralManager` などと**全く同じAPI**を持つクラスを作り、Type Aliasで公開する。

### アーキテクチャ

```
CoreBluetoothEmulator モジュール
├── Internal Classes (内部実装)
│   ├── _EmulatedCBCentralManager
│   ├── _EmulatedCBPeripheral
│   ├── _EmulatedCBPeripheralManager
│   └── EmulatorBus
│
└── Public Type Aliases (公開API)
    ├── public typealias CBCentralManager = _EmulatedCBCentralManager
    ├── public typealias CBPeripheral = _EmulatedCBPeripheral
    ├── public typealias CBPeripheralManager = _EmulatedCBPeripheralManager
    ├── public typealias CBService = _EmulatedCBService
    ├── public typealias CBCharacteristic = _EmulatedCBCharacteristic
    └── ... (すべてのCoreBluetoothの型)
```

### 使用例

#### アプリコード（変更不要！）

```swift
// MyBluetoothManager.swift
// CoreBluetoothを使った既存のコード

// 本番環境
import CoreBluetooth

// テスト環境では import を変更するだけ
// import CoreBluetoothEmulator

class MyBluetoothManager: NSObject {
    private var centralManager: CBCentralManager!
    private var discoveredPeripherals: [CBPeripheral] = []

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }
}

extension MyBluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        }
    }

    func centralManager(_ central: CBCentralManager,
                       didDiscover peripheral: CBPeripheral,
                       advertisementData: [String: Any],
                       rssi RSSI: NSNumber) {
        discoveredPeripherals.append(peripheral)
    }
}
```

#### テストコード

```swift
// テストファイル
import XCTest
import CoreBluetoothEmulator  // ← ここだけ違う！

class MyBluetoothManagerTests: XCTestCase {
    func testScanning() async throws {
        // アプリコードはそのまま使える！
        let manager = MyBluetoothManager()

        // Peripheralをエミュレート
        let peripheralManager = CBPeripheralManager(delegate: self, queue: nil)

        let service = CBMutableService(type: CBUUID(string: "180D"), primary: true)
        peripheralManager.add(service)
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: "180D")]
        ])

        // スキャン開始
        manager.startScanning()

        // 発見されるのを待つ
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // 検証
        XCTAssertGreaterThan(manager.discoveredPeripherals.count, 0)
    }
}
```

### 実装の詳細

#### 1. 内部クラスの命名規則

```swift
// Sources/CoreBluetoothEmulator/Internal/_EmulatedCBCentralManager.swift

/// 内部実装クラス（アンダースコアプレフィックス）
public class _EmulatedCBCentralManager: NSObject {
    public weak var delegate: (any CBCentralManagerDelegate)?
    public private(set) var state: CBManagerState = .unknown
    public private(set) var isScanning: Bool = false

    private let queue: DispatchQueue?
    private let identifier = UUID()

    public init(delegate: (any CBCentralManagerDelegate)?,
                queue: DispatchQueue?,
                options: [String: Any]? = nil) {
        self.delegate = delegate
        self.queue = queue
        super.init()

        Task {
            await EmulatorBus.shared.register(central: self, identifier: identifier)
            // 状態を poweredOn に遷移
            await transitionToPoweredOn()
        }
    }

    // CoreBluetoothと全く同じシグネチャ
    public func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?,
                                  options: [String: Any]? = nil) {
        isScanning = true
        Task {
            await EmulatorBus.shared.startScanning(
                centralIdentifier: identifier,
                services: serviceUUIDs
            )
        }
    }

    // ... その他のメソッド
}
```

#### 2. Type Aliasの公開

```swift
// Sources/CoreBluetoothEmulator/CoreBluetoothEmulator.swift

// Manager classes
public typealias CBCentralManager = _EmulatedCBCentralManager
public typealias CBPeripheralManager = _EmulatedCBPeripheralManager

// Peripheral side
public typealias CBPeripheral = _EmulatedCBPeripheral
public typealias CBCentral = _EmulatedCBCentral

// GATT hierarchy
public typealias CBService = _EmulatedCBService
public typealias CBMutableService = _EmulatedCBMutableService
public typealias CBCharacteristic = _EmulatedCBCharacteristic
public typealias CBMutableCharacteristic = _EmulatedCBMutableCharacteristic
public typealias CBDescriptor = _EmulatedCBDescriptor
public typealias CBMutableDescriptor = _EmulatedCBMutableDescriptor

// Requests
public typealias CBATTRequest = _EmulatedCBATTRequest

// L2CAP
public typealias CBL2CAPChannel = _EmulatedCBL2CAPChannel

// 注: CBUUID, CBManagerState, CBError, CBATTError などの列挙型・構造体は
// CoreBluetoothから再エクスポート
@_exported import struct CoreBluetooth.CBUUID
@_exported import enum CoreBluetooth.CBManagerState
@_exported import enum CoreBluetooth.CBPeripheralState
@_exported import enum CoreBluetooth.CBCharacteristicProperties
@_exported import enum CoreBluetooth.CBAttributePermissions
@_exported import enum CoreBluetooth.CBCharacteristicWriteType
@_exported import struct CoreBluetooth.CBError
@_exported import struct CoreBluetooth.CBATTError
```

### メリット

1. **既存コードがそのまま動く**
   ```swift
   // 本番
   import CoreBluetooth

   // テスト
   import CoreBluetoothEmulator

   // コードは全く同じ！
   let central = CBCentralManager(delegate: self, queue: nil)
   ```

2. **型安全**
   - コンパイル時に型チェック
   - IDEの自動補完も正常に動作

3. **最小限の変更**
   - importを変えるだけ
   - 条件付きコンパイルも可能：
   ```swift
   #if DEBUG
   import CoreBluetoothEmulator
   #else
   import CoreBluetooth
   #endif
   ```

4. **段階的な移行が可能**
   - 一部のテストだけエミュレータを使う
   - 統合テストは実機で実行

### 制限事項と対処法

#### 1. Delegateプロトコル

実際の `CBCentralManagerDelegate` は CoreBluetooth の `CBPeripheral` を受け取る。

**解決策:** CoreBluetooth の Delegate プロトコルをそのまま使う

```swift
// CoreBluetooth の delegate をそのまま使う
public protocol CBCentralManagerDelegate: AnyObject {
    func centralManagerDidUpdateState(_ central: CBCentralManager)
    func centralManager(_ central: CBCentralManager,
                       didDiscover peripheral: CBPeripheral,
                       advertisementData: [String: Any],
                       rssi RSSI: NSNumber)
    // ...
}
```

これは **できません** ので、別の方法を取ります：

**実際の解決策:** `@_exported import` を使って CoreBluetooth の Delegate プロトコルを再エクスポート

```swift
// Sources/CoreBluetoothEmulator/CoreBluetoothEmulator.swift

// Delegate プロトコルは CoreBluetooth のものをそのまま使う
@_exported import protocol CoreBluetooth.CBCentralManagerDelegate
@_exported import protocol CoreBluetooth.CBPeripheralManagerDelegate
@_exported import protocol CoreBluetooth.CBPeripheralDelegate
```

これにより、既存のデリゲート実装がそのまま動作します。

#### 2. クラスの継承チェック

一部のコードは型チェックを行う場合があります：

```swift
if peripheral is CBPeripheral {  // 実際のCBPeripheralかチェック
    // ...
}
```

**解決策:** エミュレータであることを明示する静的プロパティを追加

```swift
extension _EmulatedCBPeripheral {
    public static var isEmulated: Bool { true }
}

// 使用側
if CBPeripheral.isEmulated {
    print("Running with emulator")
}
```

### プロジェクト構造

```
CoreBluetoothEmulator/
├── Package.swift
├── Sources/
│   └── CoreBluetoothEmulator/
│       ├── CoreBluetoothEmulator.swift      # Type aliases & re-exports
│       ├── EmulatorBus.swift                # Core emulator logic
│       ├── EmulatorConfiguration.swift      # Configuration
│       ├── Internal/
│       │   ├── _EmulatedCBCentralManager.swift
│       │   ├── _EmulatedCBPeripheral.swift
│       │   ├── _EmulatedCBPeripheralManager.swift
│       │   ├── _EmulatedCBService.swift
│       │   ├── _EmulatedCBCharacteristic.swift
│       │   └── ... (other internal classes)
│       └── Utilities/
│           └── EmulatorTestHelper.swift
└── Tests/
    └── CoreBluetoothEmulatorTests/
        ├── CentralPeripheralTests.swift
        └── ... (other tests)
```

### Package.swift

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CoreBluetoothEmulator",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        .library(
            name: "CoreBluetoothEmulator",
            targets: ["CoreBluetoothEmulator"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "CoreBluetoothEmulator",
            dependencies: [],
            swiftSettings: [
                // @_exported を有効化
                .unsafeFlags(["-Xfrontend", "-enable-library-evolution"])
            ]
        ),
        .testTarget(
            name: "CoreBluetoothEmulatorTests",
            dependencies: ["CoreBluetoothEmulator"]
        ),
    ]
)
```

## まとめ

このアプローチにより：

1. ✅ **Bleu非依存** - Pure CoreBluetoothのエミュレーション
2. ✅ **既存コード再利用** - importを変えるだけで動作
3. ✅ **ハードウェア不要** - 完全にソフトウェアでエミュレート
4. ✅ **検証容易** - テストシナリオを柔軟に構築可能
5. ✅ **型安全** - コンパイル時チェック

既存のCoreBluetoothコードを**一切変更せずに**エミュレータでテストできます！
