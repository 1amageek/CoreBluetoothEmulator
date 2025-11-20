# CoreBluetooth Framework Architecture

## Overview

CoreBluetoothは、iOS/macOSでBluetooth Low Energy (BLE)通信を行うためのフレームワークです。Central-Peripheralアーキテクチャを採用しています。

## Core Concepts

### Bluetooth LE Protocol Stack

CoreBluetoothは、Bluetooth LE (Low Energy) プロトコルスタックの上位レイヤーを抽象化します：

```
┌─────────────────────────────────┐
│     CoreBluetooth Framework     │  ← iOS/macOS API
├─────────────────────────────────┤
│  GATT (Generic Attribute Profile)│  ← データ構造とアクセス
├─────────────────────────────────┤
│   ATT (Attribute Protocol)      │  ← 読み書きプロトコル
├─────────────────────────────────┤
│  GAP (Generic Access Profile)   │  ← 発見と接続
├─────────────────────────────────┤
│        L2CAP / Link Layer       │  ← データ転送
├─────────────────────────────────┤
│       Physical Layer (2.4GHz)   │  ← 無線通信
└─────────────────────────────────┘
```

### GAP vs GATT

#### GAP (Generic Access Profile)
**役割**: デバイスの発見、接続確立、セキュリティ

**CoreBluetoothでの対応:**
- `CBCentralManager.scanForPeripherals()` - デバイス発見
- `CBCentralManager.connect()` - 接続確立
- `CBPeripheralManager.startAdvertising()` - アドバタイジング
- 接続パラメータの管理

#### GATT (Generic Attribute Profile)
**役割**: 接続後のデータ構造とアクセス方法の定義

**CoreBluetoothでの対応:**
- `CBService` - サービス（機能のグループ）
- `CBCharacteristic` - キャラクタリスティック（データの読み書き単位）
- `CBDescriptor` - ディスクリプタ（キャラクタリスティックのメタデータ）

**GATT階層:**
```
Profile
  └─ Service (Primary)
       ├─ Service (Included) [optional]
       └─ Characteristic
            ├─ Value (Data)
            ├─ Properties (Read/Write/Notify/etc)
            └─ Descriptor [optional]
                 └─ Value (Metadata)
```

### ATT (Attribute Protocol)

ATTはGATTの下位レイヤーで、実際の読み書き操作を定義します：

**操作タイプ:**
- **Read**: Centralがデータを読み取り（応答あり）
- **Write**: Centralがデータを書き込み（応答あり）
- **Write Without Response**: 書き込み（応答なし、高速）
- **Notify**: Peripheralからの通知（応答なし、軽量）
- **Indicate**: Peripheralからの通知（応答あり、確実）

**CoreBluetoothでの対応:**
- `CBPeripheral.readValue()` → ATT Read Request
- `CBPeripheral.writeValue(..., type: .withResponse)` → ATT Write Request
- `CBPeripheral.writeValue(..., type: .withoutResponse)` → ATT Write Command
- `CBPeripheral.setNotifyValue(true, ...)` → ATT Notify (or Indicate)
- `CBPeripheralManager.updateValue()` → ATT Notification送信

### Central vs Peripheral Roles

| Role | 説明 | CoreBluetoothクラス | 典型的なデバイス |
|------|------|---------------------|------------------|
| **Central** | デバイスをスキャンし、接続を開始する側 | `CBCentralManager`<br>`CBPeripheral` | iPhone、iPad、Mac |
| **Peripheral** | アドバタイズし、接続を受け入れる側 | `CBPeripheralManager`<br>`CBCentral` | Heart rate monitor、温度センサー |

**重要な特性:**
- 1つのデバイスが同時にCentralとPeripheral両方の役割を持つことが可能
- iOSデバイスは通常Centralとして動作するが、`CBPeripheralManager`でPeripheralにもなれる
- watchOS/tvOS/visionOSではPeripheralとしてのアドバタイジング不可

### UUID Naming Convention

Bluetooth SIGが定義する16ビットUUIDは標準化されています：

**標準サービス (例):**
- `0x180D` - Heart Rate Service
- `0x180F` - Battery Service
- `0x181A` - Environmental Sensing Service

**標準Characteristic (例):**
- `0x2A37` - Heart Rate Measurement
- `0x2A19` - Battery Level
- `0x2A6E` - Temperature

**カスタムUUID:**
128ビットUUID（例: `12345678-1234-1234-1234-123456789012`）を使用。
通常、ベンダー固有のサービスやCharacteristicに使用。

### Advertisement Data の構造

アドバタイジングパケットには最大31バイトのデータを含められます：

**主要なフィールド:**
- **Local Name**: デバイス名（最大29バイト）
- **Service UUIDs**: サービスのリスト
- **Manufacturer Data**: メーカー固有データ（会社IDコード + データ）
- **Tx Power Level**: 送信電力（RSSI距離計算に使用）
- **Service Data**: サービスごとのカスタムデータ
- **Flags**: 検出可能性、接続可能性のフラグ

**用語解説:**
- **Solicited Service UUIDs**: Centralが積極的に探しているサービスのリスト。Peripheralはこれを含めることで、特定のCentralにマッチしやすくなる
- **Overflow Service UUIDs**: 31バイト制限のため、アドバタイジングパケットに収まらなかったサービスUUID。スキャン応答 (Scan Response) に含まれる

## Core Components

### 1. CBManager (Base Class)

すべてのマネージャークラスの基底クラス。

**主要プロパティ:**
- `state: CBManagerState` - Bluetoothの状態
  - `.unknown` - 初期状態
  - `.resetting` - リセット中
  - `.unsupported` - デバイスがBLEをサポートしていない
  - `.unauthorized` - アプリが権限を持っていない
  - `.poweredOff` - Bluetoothがオフ
  - `.poweredOn` - Bluetoothが使用可能

### 2. CBCentralManager (Central Role)

BLEデバイスをスキャン、検出、接続するための中心的なクラス。

**主要メソッド:**

#### 初期化
```swift
init(delegate: CBCentralManagerDelegate?, queue: DispatchQueue?, options: [String: Any]?)
```

**初期化オプション:**
- `CBCentralManagerOptionShowPowerAlertKey` - Bluetooth無効時にアラート表示
- `CBCentralManagerOptionRestoreIdentifierKey` - バックグラウンド復帰用の識別子

#### スキャニング
```swift
func scanForPeripherals(withServices: [CBUUID]?, options: [String: Any]?)
func stopScan()
var isScanning: Bool
```

**スキャンオプション:**
- `CBCentralManagerScanOptionAllowDuplicatesKey` - 重複した広告パケットを報告
- `CBCentralManagerScanOptionSolicitedServiceUUIDsKey` - 要求されたサービスUUID

#### 接続管理
```swift
func connect(_ peripheral: CBPeripheral, options: [String: Any]?)
func cancelPeripheralConnection(_ peripheral: CBPeripheral)
```

**接続オプション:**
- `CBConnectPeripheralOptionNotifyOnConnectionKey` - 接続時に通知
- `CBConnectPeripheralOptionNotifyOnDisconnectionKey` - 切断時に通知
- `CBConnectPeripheralOptionNotifyOnNotificationKey` - 通知受信時に通知
- `CBConnectPeripheralOptionStartDelayKey` - 接続開始の遅延

#### Peripheral検索
```swift
func retrievePeripherals(withIdentifiers: [UUID]) -> [CBPeripheral]
func retrieveConnectedPeripherals(withServices: [CBUUID]) -> [CBPeripheral]
```

#### 接続イベント登録
```swift
func registerForConnectionEvents(options: [CBConnectionEventMatchingOption: Any]?)
```

#### 機能サポート確認 (iOS 13.0+)
```swift
class func supports(_ features: CBCentralManager.Feature) -> Bool
```

**利用可能なFeature flags:**
- `.extendedScanAndConnect` (iOS 13.0+) - 拡張スキャンと接続機能
- `.privacyFeature` (iOS 17.0+) - プライバシー機能のサポート

**使用例:**
```swift
if CBCentralManager.supports(.extendedScanAndConnect) {
    // 拡張スキャン機能を使用
}

if CBCentralManager.supports(.privacyFeature) {
    // iOS 17+ のプライバシー機能を使用
}
```

### 3. CBCentralManagerDelegate

Central Managerのイベントを受け取るプロトコル。

**必須メソッド:**
```swift
func centralManagerDidUpdateState(_ central: CBCentralManager)
```

**オプショナルメソッド:**

#### スキャン・検出
```swift
func centralManager(_ central: CBCentralManager,
                   didDiscover peripheral: CBPeripheral,
                   advertisementData: [String: Any],
                   rssi RSSI: NSNumber)
```

**advertisementDataのキー:**
- `CBAdvertisementDataLocalNameKey` - ローカル名
- `CBAdvertisementDataManufacturerDataKey` - メーカー固有データ
- `CBAdvertisementDataServiceDataKey` - サービスデータ
- `CBAdvertisementDataServiceUUIDsKey` - サービスUUID配列
- `CBAdvertisementDataOverflowServiceUUIDsKey` - オーバーフローサービスUUID
- `CBAdvertisementDataTxPowerLevelKey` - 送信電力レベル
- `CBAdvertisementDataIsConnectable` - 接続可能フラグ
- `CBAdvertisementDataSolicitedServiceUUIDsKey` - 要求されたサービスUUID

#### 接続イベント
```swift
func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)
func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?)
func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral)
```

#### 状態復元
```swift
func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any])
```

**復元ディクショナリのキー:**
- `CBCentralManagerRestoredStatePeripheralsKey` - 復元されたPeripheral配列
- `CBCentralManagerRestoredStateScanServicesKey` - スキャン中だったサービス
- `CBCentralManagerRestoredStateScanOptionsKey` - スキャンオプション

#### ANCS認証
```swift
func centralManager(_ central: CBCentralManager, didUpdateANCSAuthorizationFor peripheral: CBPeripheral)
```

### 4. CBPeripheralManager (Peripheral Role)

ローカルデバイスをPeripheralとして動作させるためのクラス。

**主要メソッド:**

#### 初期化
```swift
init(delegate: CBPeripheralManagerDelegate?, queue: DispatchQueue?, options: [String: Any]?)
```

**初期化オプション:**
- `CBPeripheralManagerOptionShowPowerAlertKey` - Bluetooth無効時にアラート表示
- `CBPeripheralManagerOptionRestoreIdentifierKey` - バックグラウンド復帰用の識別子

#### サービス管理
```swift
func add(_ service: CBMutableService)
func remove(_ service: CBMutableService)
func removeAllServices()
```

#### アドバタイジング
```swift
func startAdvertising(_ advertisementData: [String: Any]?)
func stopAdvertising()
var isAdvertising: Bool
```

**アドバタイジングデータのキー:**
- `CBAdvertisementDataLocalNameKey` - ローカル名
- `CBAdvertisementDataServiceUUIDsKey` - サービスUUID配列

#### 値の更新
```swift
func updateValue(_ value: Data,
                for characteristic: CBMutableCharacteristic,
                onSubscribedCentrals centrals: [CBCentral]?) -> Bool
```

#### リクエストへの応答
```swift
func respond(to request: CBATTRequest, withResult result: CBATTError.Code)
```

#### 接続レイテンシ設定
```swift
func setDesiredConnectionLatency(_ latency: CBPeripheralManagerConnectionLatency, for central: CBCentral)
```

#### L2CAPチャネル (iOS 11.0+)
```swift
func publishL2CAPChannel(withEncryption encrypted: Bool)
func unpublishL2CAPChannel(_ PSM: CBL2CAPPSM)
```

**プラットフォーム対応:**
- iOS 11.0+、macOS 10.13+、tvOS 11.0+、watchOS 4.0+

#### 認証状態
```swift
class func authorizationStatus() -> CBPeripheralManagerAuthorizationStatus
```

### 5. CBPeripheralManagerDelegate

Peripheral Managerのイベントを受け取るプロトコル。

**必須メソッド:**
```swift
func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager)
```

**オプショナルメソッド:**

#### サービス管理
```swift
func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?)
```

#### アドバタイジング
```swift
func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?)
```

#### Subscription管理
```swift
func peripheralManager(_ peripheral: CBPeripheralManager,
                      central: CBCentral,
                      didSubscribeTo characteristic: CBCharacteristic)
func peripheralManager(_ peripheral: CBPeripheralManager,
                      central: CBCentral,
                      didUnsubscribeFrom characteristic: CBCharacteristic)
```

#### リクエスト処理
```swift
func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest)
func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest])
```

#### 送信準備完了
```swift
func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager)
```

#### L2CAPチャネル
```swift
func peripheralManager(_ peripheral: CBPeripheralManager, didPublishL2CAPChannel PSM: CBL2CAPPSM, error: Error?)
func peripheralManager(_ peripheral: CBPeripheralManager, didUnpublishL2CAPChannel PSM: CBL2CAPPSM, error: Error?)
func peripheralManager(_ peripheral: CBPeripheralManager, didOpen channel: CBL2CAPChannel?, error: Error?)
```

#### 状態復元
```swift
func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any])
```

### 6. CBPeripheral

リモートのPeripheralデバイスを表すクラス。

**主要プロパティ:**
- `identifier: UUID` - 一意の識別子
- `name: String?` - デバイス名
- `state: CBPeripheralState` - 接続状態
- `services: [CBService]?` - サービス配列
- `canSendWriteWithoutResponse: Bool` - 応答なし書き込みが可能か

**主要メソッド:**

#### サービス探索
```swift
func discoverServices(_ serviceUUIDs: [CBUUID]?)
func discoverIncludedServices(_ includedServiceUUIDs: [CBUUID]?, for service: CBService)
```

#### Characteristic探索
```swift
func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: CBService)
```

#### Descriptor探索
```swift
func discoverDescriptors(for characteristic: CBCharacteristic)
```

#### 値の読み書き
```swift
func readValue(for characteristic: CBCharacteristic)
func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType)
func readValue(for descriptor: CBDescriptor)
func writeValue(_ data: Data, for descriptor: CBDescriptor)
```

#### 通知
```swift
func setNotifyValue(_ enabled: Bool, for characteristic: CBCharacteristic)
```

#### RSSI
```swift
func readRSSI()
```

#### L2CAPチャネル
```swift
func openL2CAPChannel(_ PSM: CBL2CAPPSM)
```

### 7. CBPeripheralDelegate

Peripheralのイベントを受け取るプロトコル。

**主要メソッド:**

#### 名前更新
```swift
func peripheralDidUpdateName(_ peripheral: CBPeripheral)
```

#### サービス
```swift
func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
func peripheral(_ peripheral: CBPeripheral, didDiscoverIncludedServicesFor service: CBService, error: Error?)
func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService])
```

#### Characteristic
```swift
func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?)
func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?)
```

#### Descriptor
```swift
func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?)
func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?)
func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?)
```

#### RSSI
```swift
func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?)
```

#### L2CAPチャネル
```swift
func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?)
```

#### 送信準備完了
```swift
func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral)
```

### 8. GATT Hierarchy

#### CBService
```swift
class CBService {
    var uuid: CBUUID
    var isPrimary: Bool
    var peripheral: CBPeripheral?
    var includedServices: [CBService]?
    var characteristics: [CBCharacteristic]?
}
```

#### CBMutableService
```swift
class CBMutableService: CBService {
    init(type: CBUUID, primary: Bool)
    var characteristics: [CBCharacteristic]?
    var includedServices: [CBService]?
}
```

#### CBCharacteristic
```swift
class CBCharacteristic {
    var uuid: CBUUID
    var service: CBService
    var properties: CBCharacteristicProperties
    var value: Data?
    var descriptors: [CBDescriptor]?
    var isNotifying: Bool
}
```

**Properties:**
- `.broadcast` - ブロードキャスト可能
- `.read` - 読み取り可能
- `.writeWithoutResponse` - 応答なし書き込み可能
- `.write` - 書き込み可能
- `.notify` - 通知可能
- `.indicate` - インディケーション可能
- `.authenticatedSignedWrites` - 署名付き書き込み可能
- `.extendedProperties` - 拡張プロパティあり
- `.notifyEncryptionRequired` - 通知に暗号化必要
- `.indicateEncryptionRequired` - インディケーションに暗号化必要

#### CBMutableCharacteristic
```swift
class CBMutableCharacteristic: CBCharacteristic {
    init(type: CBUUID,
         properties: CBCharacteristicProperties,
         value: Data?,
         permissions: CBAttributePermissions)
    var subscribedCentrals: [CBCentral]?
}
```

**Permissions:**
- `.readable` - 読み取り可能
- `.writeable` - 書き込み可能
- `.readEncryptionRequired` - 読み取りに暗号化必要
- `.writeEncryptionRequired` - 書き込みに暗号化必要

#### CBDescriptor
```swift
class CBDescriptor {
    var uuid: CBUUID
    var characteristic: CBCharacteristic
    var value: Any?
}
```

#### CBMutableDescriptor
```swift
class CBMutableDescriptor: CBDescriptor {
    init(type: CBUUID, value: Any?)
}
```

### 9. CBUUID

UUIDの表現。

```swift
class CBUUID {
    init(string: String)
    init(data: Data)
    init(nsuuid: UUID)
    var data: Data
    var uuidString: String
}
```

**標準UUID:**
- サービス: 16ビットUUID (例: 0x180D = Heart Rate Service)
- Characteristic: 16ビットUUID (例: 0x2A37 = Heart Rate Measurement)
- カスタム: 128ビットUUID

### 10. CBCentral

Peripheralに接続しているCentralを表すクラス。

```swift
class CBCentral {
    var identifier: UUID
    var maximumUpdateValueLength: Int
}
```

### 11. CBATTRequest

読み書きリクエストを表すクラス。

```swift
class CBATTRequest {
    var central: CBCentral
    var characteristic: CBCharacteristic
    var offset: Int
    var value: Data?
}
```

### 12. CBL2CAPChannel

L2CAPチャネルを表すクラス。

```swift
class CBL2CAPChannel {
    var peer: CBPeer
    var inputStream: InputStream
    var outputStream: OutputStream
    var psm: CBL2CAPPSM
}
```

## State Flow

### Central Role Flow

```
1. CBCentralManager初期化
   ↓
2. centralManagerDidUpdateState(.poweredOn)
   ↓
3. scanForPeripherals(withServices:)
   ↓
4. didDiscover peripheral (繰り返し)
   ↓
5. connect(peripheral)
   ↓
6. didConnect peripheral
   ↓
7. discoverServices()
   ↓
8. didDiscoverServices
   ↓
9. discoverCharacteristics(for: service)
   ↓
10. didDiscoverCharacteristics
   ↓
11. readValue/writeValue/setNotifyValue
   ↓
12. didUpdateValue/didWriteValue
```

### Peripheral Role Flow

```
1. CBPeripheralManager初期化
   ↓
2. peripheralManagerDidUpdateState(.poweredOn)
   ↓
3. CBMutableService作成
   ↓
4. CBMutableCharacteristic作成
   ↓
5. サービスにCharacteristicを追加
   ↓
6. add(service)
   ↓
7. didAdd service
   ↓
8. startAdvertising()
   ↓
9. didStartAdvertising
   ↓
10. Centralからの接続待機
   ↓
11. didReceiveRead/didReceiveWrite
   ↓
12. respond(to: request)
    または
    updateValue(for: characteristic)
```

### Write Without Response Backpressure Flow (高スループットケース)

Central側で`writeValue(..., type: .withoutResponse)`を使用する場合のバックプレッシャー制御：

```
Central                           Peripheral
  |                                   |
  |-- canSendWriteWithoutResponse -→ | (プロパティチェック)
  |   (true を確認)                    |
  |                                   |
  |-- writeValue (without response)->|
  |-- writeValue (without response)->|
  |-- writeValue (without response)->| (送信キューがいっぱいに)
  |                                   |
  |   canSendWriteWithoutResponse    |
  |   (false に変化)                   | (バッファフル)
  |                                   |
  |   (送信を一時停止)                  |
  |                                   |
  |                                   | (バッファ処理)
  |                                   |
  |<- peripheralIsReady(...) --------|
  |   (デリゲートメソッド呼び出し)        |
  |                                   |
  |   canSendWriteWithoutResponse    |
  |   (true に戻る)                    |
  |                                   |
  |-- writeValue (without response)->| (送信再開)
  |-- writeValue (without response)->|
  |                                   |
```

**実装例:**
```swift
class HighThroughputWriter {
    private var peripheral: CBPeripheral
    private var characteristic: CBCharacteristic
    private var dataQueue: [Data] = []
    private var isWriting = false

    func sendData(_ data: Data) {
        dataQueue.append(data)
        sendNextChunk()
    }

    private func sendNextChunk() {
        guard !isWriting else { return }
        guard !dataQueue.isEmpty else { return }

        // 送信可能かチェック
        guard peripheral.canSendWriteWithoutResponse else {
            // バッファがいっぱい - peripheralIsReady を待つ
            isWriting = true
            return
        }

        let data = dataQueue.removeFirst()
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)

        // 次のチャンクを送信
        sendNextChunk()
    }

    // CBPeripheralDelegate
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        isWriting = false
        sendNextChunk()  // 送信再開
    }
}
```

**重要なポイント:**
- `canSendWriteWithoutResponse` は動的に変化する
- `false` の場合は送信を停止し、`peripheralIsReady(toSendWriteWithoutResponse:)` を待つ
- 無視して送信を続けるとデータが失われる可能性がある
- iOS 11.0+ で利用可能

**最大スループット:**
- ATT MTU (Maximum Transmission Unit) に依存: 通常 23-512 バイト
- 接続間隔に依存: 7.5ms - 4秒
- 理論上の最大: 約 1 Mbps (実際は数百 kbps)

**MTU ネゴシエーション (iOS 10+):**
```swift
// iOS側は自動的に最大MTUをネゴシエート
// peripheral.maximumWriteValueLength でMTUを確認可能

let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
print("Maximum write size: \(mtu) bytes")

// データを MTU サイズに分割
func splitData(_ data: Data, maxSize: Int) -> [Data] {
    var chunks: [Data] = []
    var offset = 0

    while offset < data.count {
        let chunkSize = min(maxSize, data.count - offset)
        let chunk = data.subdata(in: offset..<(offset + chunkSize))
        chunks.append(chunk)
        offset += chunkSize
    }

    return chunks
}
```

## Error Handling

### CBATTError

ATT (Attribute Protocol) エラー。

```swift
enum CBATTError.Code {
    case success
    case invalidHandle
    case readNotPermitted
    case writeNotPermitted
    case invalidPdu
    case insufficientAuthentication
    case requestNotSupported
    case invalidOffset
    case insufficientAuthorization
    case prepareQueueFull
    case attributeNotFound
    case attributeNotLong
    case insufficientEncryptionKeySize
    case invalidAttributeValueLength
    case unlikelyError
    case insufficientEncryption
    case unsupportedGroupType
    case insufficientResources
}
```

#### 典型的なATTエラーシナリオ

| エラーコード | 典型的な原因 | 解決方法 |
|-------------|------------|----------|
| `.readNotPermitted` | Characteristicが読み取り不可<br>Permissionが`.readable`ではない | Characteristicのpropertiesを確認<br>`.read`プロパティがあるか確認 |
| `.writeNotPermitted` | Characteristicが書き込み不可<br>Permissionが`.writeable`ではない | Characteristicのpropertiesを確認<br>`.write`または`.writeWithoutResponse`があるか確認 |
| `.insufficientAuthentication` | ペアリングが必要<br>暗号化が必要なCharacteristicにアクセス | デバイスをペアリング<br>Permissionで`.readEncryptionRequired`または`.writeEncryptionRequired`が設定されている |
| `.insufficientEncryption` | 暗号化された接続が必要 | ペアリング後に再接続<br>iOS側で暗号化が自動的に処理される |
| `.insufficientAuthorization` | ユーザー認証が必要 | アプリ側で認証処理を実装<br>通常はカスタム認証フロー |
| `.invalidOffset` | ロング読み取り/書き込みのオフセットが不正 | オフセット値を確認<br>Characteristicの値のサイズを超えていない か |
| `.invalidAttributeValueLength` | 書き込みデータのサイズが不正<br>最大512バイトを超えている | データサイズを確認<br>分割して送信する |
| `.attributeNotFound` | 存在しないCharacteristic/Descriptorにアクセス | サービス/Characteristicの探索を再実行<br>UUIDが正しいか確認 |
| `.insufficientResources` | Peripheralのリソース不足<br>同時接続数が多すぎる | 接続数を減らす<br>リトライする |

**例: 暗号化が必要なCharacteristicへのアクセス**
```swift
func peripheral(_ peripheral: CBPeripheral,
               didUpdateValueFor characteristic: CBCharacteristic,
               error: Error?) {
    if let error = error as? CBATTError,
       error.code == .insufficientAuthentication {
        // ペアリングが必要
        // iOS は自動的にペアリングダイアログを表示
        // ペアリング後、自動的に再試行される
        print("Pairing required")
    }
}
```

### CBError

CoreBluetoothのエラー。

```swift
enum CBError.Code {
    case unknown
    case invalidParameters
    case invalidHandle
    case notConnected
    case outOfSpace
    case operationCancelled
    case connectionTimeout
    case peripheralDisconnected
    case uuidNotAllowed
    case alreadyAdvertising
    case connectionFailed
    case connectionLimitReached
    case unknownDevice
    case operationNotSupported
    case peerRemovedPairingInformation
    case encryptionTimedOut
    case tooManyLEPairedDevices
}
```

#### 典型的なCBErrorシナリオ

| エラーコード | 典型的な原因 | 解決方法 |
|-------------|------------|----------|
| `.connectionTimeout` | Peripheralが応答しない<br>距離が遠すぎる<br>電波干渉 | 距離を近づける<br>リトライする<br>タイムアウト時間を調整 |
| `.connectionFailed` | 接続確立に失敗<br>Peripheralがビジー状態<br>接続パラメータが不適切 | リトライする<br>少し待ってから再試行<br>他のCentralとの接続を切断 |
| `.peripheralDisconnected` | 接続中に切断された<br>範囲外に移動<br>電池切れ | 接続状態を監視<br>再接続ロジックを実装<br>`didDisconnectPeripheral`で処理 |
| `.notConnected` | 切断状態でAPIを呼び出し | 接続状態を確認してから操作<br>`peripheral.state == .connected`を確認 |
| `.connectionLimitReached` | 同時接続数の上限に達した<br>iOSの制限（通常10-20デバイス） | 不要な接続を切断<br>接続を使い回す |
| `.tooManyLEPairedDevices` | ペアリング済みデバイス数が上限<br>古いBluetooth コントローラーの制限 | Bluetooth設定で古いデバイスを削除<br>システムが自動的に古いペアリングを削除する場合もある |
| `.alreadyAdvertising` | 既にアドバタイジング中<br>`startAdvertising()`を重複呼び出し | `stopAdvertising()`を呼んでから再開<br>`isAdvertising`プロパティで確認 |
| `.operationNotSupported` | プラットフォームが機能をサポートしていない<br>watchOS/tvOSでのPeripheralアドバタイジングなど | プラットフォーム機能を確認<br>`CBCentralManager.supports()`で事前チェック |
| `.peerRemovedPairingInformation` | Peripheral側でペアリング情報が削除された | デバイスを再ペアリング<br>Bluetooth設定でデバイスを削除して再接続 |

**例: 接続エラーのハンドリング**
```swift
func centralManager(_ central: CBCentralManager,
                   didFailToConnect peripheral: CBPeripheral,
                   error: Error?) {
    if let error = error as? CBError {
        switch error.code {
        case .connectionTimeout:
            // タイムアウト - リトライ
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                central.connect(peripheral, options: nil)
            }

        case .connectionLimitReached:
            // 接続数上限 - 古い接続を切断
            disconnectOldestPeripheral()
            central.connect(peripheral, options: nil)

        case .tooManyLEPairedDevices:
            // ペアリング上限 - ユーザーに通知
            showAlert("Bluetooth設定で古いデバイスを削除してください")

        default:
            print("Connection failed: \(error.localizedDescription)")
        }
    }
}
```

### エラーハンドリングのベストプラクティス

**1. エラーを常にチェック:**
```swift
func peripheral(_ peripheral: CBPeripheral,
               didUpdateValueFor characteristic: CBCharacteristic,
               error: Error?) {
    guard error == nil else {
        handleError(error!)
        return
    }

    // 正常処理
    processValue(characteristic.value)
}
```

**2. リトライロジックを実装:**
```swift
func connectWithRetry(peripheral: CBPeripheral, maxRetries: Int = 3) {
    var retryCount = 0

    func attemptConnection() {
        centralManager.connect(peripheral, options: nil)
    }

    func handleFailure() {
        retryCount += 1
        if retryCount < maxRetries {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(retryCount)) {
                attemptConnection()
            }
        } else {
            // 最大リトライ回数に達した
            notifyConnectionFailed()
        }
    }
}
```

**3. タイムアウトを実装:**
```swift
func readValueWithTimeout(for characteristic: CBCharacteristic, timeout: TimeInterval = 5.0) {
    let timeoutTask = DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
        // タイムアウト処理
        self.handleReadTimeout(characteristic)
    }

    // タイムアウトをキャンセルできるように保存
    pendingReads[characteristic.uuid] = timeoutTask

    peripheral.readValue(for: characteristic)
}

func peripheral(_ peripheral: CBPeripheral,
               didUpdateValueFor characteristic: CBCharacteristic,
               error: Error?) {
    // タイムアウトをキャンセル
    pendingReads[characteristic.uuid]?.cancel()
    pendingReads.removeValue(forKey: characteristic.uuid)

    // 値を処理
}
```

## Threading Model

CoreBluetoothはすべてのデリゲートコールバックを指定されたDispatchQueueで実行します。

### Queue Management

**デフォルトキュー:**
```swift
// nilを指定するとメインキューが使用される
let central = CBCentralManager(delegate: self, queue: nil)
```

**カスタムキュー:**
```swift
// 専用のシリアルキューを使用
let queue = DispatchQueue(label: "com.example.bluetooth")
let central = CBCentralManager(delegate: self, queue: queue)
```

### 重要なスレッド制約

#### 1. すべてのAPIは指定されたキューから呼び出す必要がある

```swift
// ✓ 正しい: 同じキューから呼び出し
queue.async {
    centralManager.scanForPeripherals(withServices: nil, options: nil)
}

// ✗ 間違い: 別のキューから呼び出し（アサーションエラーの可能性）
DispatchQueue.global().async {
    centralManager.scanForPeripherals(withServices: nil, options: nil)  // クラッシュ!
}
```

**重要:** CoreBluetoothのAPIを異なるキューから呼び出すと、実行時アサーションエラーが発生する可能性があります。すべての操作は初期化時に指定したキューから行う必要があります。

#### 2. デリゲートコールバックの合体 (Coalescing)

システムは複数のイベントを1つのコールバックにまとめる場合があります：

```swift
// 短時間に複数のアドバタイジングパケットを受信
func centralManager(_ central: CBCentralManager,
                   didDiscover peripheral: CBPeripheral,
                   advertisementData: [String: Any],
                   rssi RSSI: NSNumber) {
    // このメソッドは毎回呼ばれるとは限らない
    // バックグラウンドでは特に頻度が低下
}
```

**対策:**
- 重複検出を前提とした実装
- タイムスタンプやカウンターで追跡
- バックグラウンドでは頻度がさらに低下することを考慮

#### 3. デッドロックの回避

同期的な操作やロックを避ける：

```swift
// ✗ 危険: デリゲートメソッド内でメインキューをブロック
func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    DispatchQueue.main.sync {  // デッドロック の可能性!
        // UI更新
    }
}

// ✓ 安全: 非同期で処理
func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    DispatchQueue.main.async {
        // UI更新
    }
}
```

### ベストプラクティス

**1. 専用キューの使用を推奨:**
```swift
class BluetoothManager {
    private let queue = DispatchQueue(label: "com.example.bluetooth", qos: .userInitiated)
    private var centralManager: CBCentralManager!

    init() {
        centralManager = CBCentralManager(delegate: self, queue: queue)
    }

    func startScanning() {
        queue.async { [weak self] in
            self?.centralManager.scanForPeripherals(withServices: nil, options: nil)
        }
    }
}
```

**2. Actor を使用したモダンな並行処理 (Swift 5.5+):**
```swift
actor BluetoothManager: NSObject, CBCentralManagerDelegate {
    private let queue = DispatchQueue(label: "com.example.bluetooth")
    private var centralManager: CBCentralManager!

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: queue)
    }

    // Actor isolationで状態を保護
    private var discoveredDevices: [UUID: CBPeripheral] = [:]

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        Task {
            await handleDiscovery(peripheral)
        }
    }

    private func handleDiscovery(_ peripheral: CBPeripheral) {
        discoveredDevices[peripheral.identifier] = peripheral
    }
}
```

**3. キューの品質 (QoS) を適切に設定:**
```swift
// ユーザー操作に応答する場合
let queue = DispatchQueue(label: "com.example.bluetooth", qos: .userInitiated)

// バックグラウンド処理の場合
let queue = DispatchQueue(label: "com.example.bluetooth", qos: .utility)
```

## Background Modes

### Central Background Mode

`UIBackgroundModes` に `bluetooth-central` を追加すると、バックグラウンドでの動作が可能になります。

**できること:**
- バックグラウンドでのスキャン
- 既存接続の維持
- データの送受信
- 新規接続の確立（state restoration使用時）

**システムによる制限:**

#### スキャンの制限
- **スキャン頻度**: フォアグラウンドより大幅に低下（数秒〜数十秒に1回）
- **重複パケット**: `CBCentralManagerScanOptionAllowDuplicatesKey` は無視される
- **スキャン応答**: Scan Responseデータは取得できない可能性がある
- **CPU制限**: バックグラウンド処理時間が限られる

#### 接続の制限
- **新規接続**: State restorationを使用しない限り、フォアグラウンドに戻る必要がある
- **接続タイムアウト**: システムが接続を自動的に切断する可能性がある（通常30秒程度）

#### データ転送の制限
- **転送速度**: 制限される可能性がある
- **通知**: 受信可能だが、処理時間が限られる

**ベストプラクティス:**
```swift
// バックグラウンド状態を確認
if UIApplication.shared.applicationState == .background {
    // バックグラウンドでは軽量な処理のみ
    // 重い処理はフォアグラウンド復帰後に実行
}
```

### Peripheral Background Mode

`UIBackgroundModes` に `bluetooth-peripheral` を追加すると、バックグラウンドでPeripheralとして動作可能です。

**できること:**
- 既存接続の維持
- 接続されたCentralへのリクエスト応答
- 通知/インディケーションの送信
- アドバタイジングの継続（制限あり）

**システムによる制限:**

#### アドバタイジングの制限
- **ローカル名**: アドバタイジングパケットに含まれない
- **Service UUIDs**: 含まれるが、パケットサイズ制限がより厳しい
- **Manufacturer Data**: 含まれない
- **Service Data**: 含まれない
- **頻度**: アドバタイジング間隔が長くなる（発見されにくい）

**バックグラウンドでのアドバタイジング例:**
```swift
// フォアグラウンド
peripheralManager.startAdvertising([
    CBAdvertisementDataLocalNameKey: "My Device",      // ✓ 送信される
    CBAdvertisementDataServiceUUIDsKey: [serviceUUID], // ✓ 送信される
    CBAdvertisementDataManufacturerDataKey: data       // ✓ 送信される
])

// バックグラウンド（同じコード）
peripheralManager.startAdvertising([
    CBAdvertisementDataLocalNameKey: "My Device",      // ✗ 送信されない
    CBAdvertisementDataServiceUUIDsKey: [serviceUUID], // ✓ 送信される
    CBAdvertisementDataManufacturerDataKey: data       // ✗ 送信されない
])
```

#### リクエスト処理の制限
- **処理時間**: 約10秒以内に応答する必要がある
- **CPU制限**: 重い処理は避ける
- **キューイング**: 複数のリクエストが同時に来る可能性がある

#### 通知送信の制限
- **送信頻度**: `updateValue()` の呼び出し頻度に制限
- **キューサイズ**: システムのバッファサイズに制限（通常20パケット程度）
- **バックプレッシャー**: `updateValue()` が `false` を返した場合は送信失敗

**推奨事項:**
- サービスUUIDのみでアドバタイジング
- ローカル名はGATTのDevice Name Characteristicで提供
- バックグラウンドでの重い処理を避ける
- State restorationを実装して接続を維持

### バックグラウンド実行時間の制限

**重要:** バックグラウンドモードは無制限の実行時間を保証しません：

- **アクティブ接続がある場合**: システムはアプリを維持
- **アクティブ接続がない場合**: 数分後にサスペンド される可能性
- **Bluetoothイベント発生時**: 一時的にアプリが起動（約10秒）
- **State restoration**: イベント発生時にアプリを再起動

### watchOS/tvOS/visionOS の制約

- **watchOS**: Peripheral modeでのアドバタイジング不可
- **tvOS**: Peripheral modeでのアドバタイジング不可
- **visionOS**: Peripheral modeでのアドバタイジング不可
- これらのプラットフォームではCentral modeのみサポート

## State Preservation and Restoration

アプリが終了しても状態を保持し、Bluetoothイベント発生時にシステムがアプリを再起動します。

### Central State Restoration

**1. Info.plistでBackground Modeを有効化:**
```xml
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
</array>
```

**2. Restore Identifierを指定してCentralManagerを初期化:**
```swift
let centralManager = CBCentralManager(
    delegate: self,
    queue: nil,
    options: [CBCentralManagerOptionRestoreIdentifierKey: "com.example.mycentral"]
)
```

**3. AppDelegateで復元処理を実装:**
```swift
func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    // システムがBluetoothイベントでアプリを起動したか確認
    if let centralManagerIdentifiers = launchOptions?[.bluetoothCentrals] as? [String] {
        // アプリがBluetoothイベントで起動された
        for identifier in centralManagerIdentifiers {
            // 同じrestore identifierでCentralManagerを再作成
            let restoredManager = CBCentralManager(
                delegate: self,
                queue: nil,
                options: [CBCentralManagerOptionRestoreIdentifierKey: identifier]
            )
            // マネージャーを保持
        }
    }
    return true
}
```

**4. デリゲートメソッドで状態を復元:**
```swift
func centralManager(
    _ central: CBCentralManager,
    willRestoreState dict: [String: Any]
) {
    // 接続されていたPeripheralを復元
    if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
        for peripheral in peripherals {
            peripheral.delegate = self
            // 必要に応じて再接続や再探索
        }
    }

    // スキャン中だったサービスを復元
    if let scanServices = dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID] {
        // スキャンを再開
        central.scanForPeripherals(withServices: scanServices, options: nil)
    }

    // スキャンオプションを復元
    if let scanOptions = dict[CBCentralManagerRestoredStateScanOptionsKey] as? [String: Any] {
        // ...
    }
}
```

### Peripheral State Restoration

**1. Info.plistでBackground Modeを有効化:**
```xml
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-peripheral</string>
</array>
```

**2. Restore Identifierを指定してPeripheralManagerを初期化:**
```swift
let peripheralManager = CBPeripheralManager(
    delegate: self,
    queue: nil,
    options: [CBPeripheralManagerOptionRestoreIdentifierKey: "com.example.myperipheral"]
)
```

**3. AppDelegateで復元処理を実装:**
```swift
func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    if let peripheralManagerIdentifiers = launchOptions?[.bluetoothPeripherals] as? [String] {
        for identifier in peripheralManagerIdentifiers {
            let restoredManager = CBPeripheralManager(
                delegate: self,
                queue: nil,
                options: [CBPeripheralManagerOptionRestoreIdentifierKey: identifier]
            )
        }
    }
    return true
}
```

**4. デリゲートメソッドで状態を復元:**
```swift
func peripheralManager(
    _ peripheral: CBPeripheralManager,
    willRestoreState dict: [String: Any]
) {
    // 追加されていたサービスを復元
    if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService] {
        for service in services {
            // サービスは既に自動的に復元されている
            // 必要に応じて参照を保持
        }
    }

    // アドバタイジングデータを復元
    if let advertisementData = dict[CBPeripheralManagerRestoredStateAdvertisementDataKey] as? [String: Any] {
        // 必要に応じてアドバタイジングを再開
        peripheral.startAdvertising(advertisementData)
    }
}
```

### 重要な注意点

**必須要件:**
- Background mode (`bluetooth-central` or `bluetooth-peripheral`) が必須
- `application(_:didFinishLaunchingWithOptions:)` で同じrestore identifierを使用してマネージャーを再作成する必要がある
- 再作成しない場合、状態復元は機能しない

**制限事項:**
- 復元はアプリがシステムによって終了された場合のみ機能
- ユーザーが手動でアプリを終了した場合は復元されない
- デバイス再起動後は復元されない
