# 改訂アプローチ: Protocol-Based Wrapper

## 問題の再確認

Type Aliasアプローチは、CoreBluetoothのデリゲートプロトコルが実際の型を要求するため実現不可能でした。

## 実用的な解決策

### アプローチ: Emulatedプレフィックス + Optional DI

**方針:**
1. `_Emulated` プレフィックスを削除し、シンプルに `EmulatedCB` とする
2. テストコードでは `EmulatedCB` クラスを直接使用
3. オプションで Protocol-based Wrapper を提供（上級ユーザー向け）

### ファイル構造

```
CoreBluetoothEmulator/
├── Sources/
│   └── CoreBluetoothEmulator/
│       ├── EmulatedCBCentralManager.swift    # ← _なし
│       ├── EmulatedCBPeripheral.swift
│       ├── EmulatedCBPeripheralManager.swift
│       ├── EmulatedCBService.swift
│       ├── EmulatedCBCharacteristic.swift
│       ├── EmulatedCBDescriptor.swift
│       ├── EmulatedCBCentral.swift
│       ├── EmulatedCBATTRequest.swift
│       ├── EmulatorBus.swift
│       └── EmulatorConfiguration.swift
```

### 使用例

#### テストコード

```swift
import XCTest
import CoreBluetoothEmulator

class BluetoothTests: XCTestCase {
    var centralManager: EmulatedCBCentralManager!
    var peripheralManager: EmulatedCBPeripheralManager!

    override func setUp() async throws {
        // Instant configuration for fast tests
        await Emulator.configure(.instant)

        centralManager = EmulatedCBCentralManager(delegate: self, queue: nil)
        peripheralManager = EmulatedCBPeripheralManager(delegate: self, queue: nil)
    }

    func testBasicCommunication() async throws {
        // Peripheral側: サービスをセットアップ
        let service = EmulatedCBMutableService(
            type: CBUUID(string: "180D"),
            primary: true
        )

        let characteristic = EmulatedCBMutableCharacteristic(
            type: CBUUID(string: "2A37"),
            properties: [.read, .notify],
            value: Data([0x01, 0x02]),
            permissions: [.readable]
        )

        service.characteristics = [characteristic]
        peripheralManager.add(service)
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: "180D")]
        ])

        // Central側: スキャンと接続
        centralManager.scanForPeripherals(withServices: nil, options: nil)

        // 発見を待機
        try await Task.sleep(nanoseconds: 100_000_000)

        // （実際にはデリゲートで取得したperipheralを使用）
        // ...
    }
}

extension BluetoothTests: EmulatedCBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: EmulatedCBCentralManager) {
        if central.state == .poweredOn {
            print("Central ready")
        }
    }

    func centralManager(
        _ central: EmulatedCBCentralManager,
        didDiscover peripheral: EmulatedCBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        print("Discovered: \(peripheral)")
    }
}

extension BluetoothTests: EmulatedCBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: EmulatedCBPeripheralManager) {
        if peripheral.state == .poweredOn {
            print("Peripheral ready")
        }
    }
}
```

#### 本番コードとの統合（オプショナル）

本番コードで実際のCoreBluetoothも使いたい場合、Protocol Wrapperを提供：

```swift
// Protocol定義（オプショナル、上級ユーザー向け）
public protocol CentralManagerProtocol: AnyObject {
    var delegate: CentralManagerDelegateProtocol? { get set }
    var state: CBManagerState { get }
    var isScanning: Bool { get }

    func scanForPeripherals(withServices: [CBUUID]?, options: [String: Any]?)
    func stopScan()
    func connect(_ peripheral: PeripheralProtocol, options: [String: Any]?)
    // ...
}

public protocol PeripheralProtocol: AnyObject {
    var identifier: UUID { get }
    var name: String? { get }
    var state: CBPeripheralState { get }
    // ...
}

// EmulatedCBCentralManager が Protocol に準拠
extension EmulatedCBCentralManager: CentralManagerProtocol {
    // Already implements all methods
}

// 本番環境用のWrapper
public class RealCBCentralManagerWrapper: CentralManagerProtocol {
    private let manager: CBCentralManager

    public init(delegate: CentralManagerDelegateProtocol?, queue: DispatchQueue?) {
        // Create real CBCentralManager
        self.manager = CBCentralManager(delegate: /* adapter */, queue: queue)
    }

    // Implement all protocol methods by forwarding to real manager
}
```

ただし、このProtocol Wrapperは複雑なので、**ほとんどのユーザーは不要**です。

### メリット

1. **シンプル**: プレフィックスを除けば、普通のSwiftクラス
2. **型安全**: コンパイル時チェック
3. **柔軟**: 必要に応じてProtocol Wrapperを追加可能
4. **実用的**: すぐに使い始められる

### デメリット

1. **既存コード修正が必要**: `CBCentralManager` → `EmulatedCBCentralManager` に変更
2. **本番とテストで異なる型**: ただし、DIパターンで解決可能

### 推奨する使い方

#### パターン1: テスト専用（最もシンプル）

```swift
// アプリコード（実機用）
import CoreBluetooth

class MyApp {
    let central = CBCentralManager(delegate: self, queue: nil)
}

// テストコード
import CoreBluetoothEmulator

class MyAppTests {
    let central = EmulatedCBCentralManager(delegate: self, queue: nil)
    // テスト専用のコードを書く
}
```

#### パターン2: DI パターン（柔軟）

```swift
// アプリコード
class BluetoothManager {
    private var central: Any  // または Protocol

    init(isTest: Bool = false) {
        if isTest {
            central = EmulatedCBCentralManager(delegate: self, queue: nil)
        } else {
            central = CBCentralManager(delegate: self, queue: nil)
        }
    }
}
```

## 結論

Type Aliasアプローチは理想的でしたが、CoreBluetoothの制約により実現不可能です。

代わりに、**明示的な `EmulatedCB` クラス**を使うアプローチが最も実用的です：
- テストコードでは `EmulatedCB` を直接使用
- 必要に応じてDIパターンで切り替え
- Protocol Wrapperはオプショナル（上級ユーザー向け）

これにより、**ハードウェア不要でCoreBluetoothのテストが可能**になります！
