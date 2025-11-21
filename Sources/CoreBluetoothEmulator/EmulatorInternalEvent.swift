import Foundation
import CoreBluetooth

/// Internal events that flow through EmulatorBus
///
/// These events represent all possible communications between central and peripheral
/// managers in the emulator. They are serializable for cross-process communication.
public enum EmulatorInternalEvent: Codable, Sendable {
    // MARK: - Scanning & Discovery
    case scanStarted(centralID: UUID, serviceUUIDs: [Data]?)
    case scanStopped(centralID: UUID)
    case peripheralDiscovered(
        centralID: UUID,
        peripheralID: UUID,
        advertisementData: [String: CodableValue],
        rssi: Int
    )

    // MARK: - Connection
    case connectionRequested(centralID: UUID, peripheralID: UUID)
    case connectionEstablished(centralID: UUID, peripheralID: UUID)
    case connectionFailed(centralID: UUID, peripheralID: UUID, error: String)
    case disconnectionRequested(centralID: UUID, peripheralID: UUID)
    case disconnected(centralID: UUID, peripheralID: UUID)

    // MARK: - Service Discovery
    case servicesDiscoveryRequested(centralID: UUID, peripheralID: UUID, serviceUUIDs: [Data]?)
    case servicesDiscovered(centralID: UUID, peripheralID: UUID, serviceUUIDs: [Data])

    // MARK: - Characteristic Discovery
    case characteristicsDiscoveryRequested(
        centralID: UUID,
        peripheralID: UUID,
        serviceUUID: Data,
        characteristicUUIDs: [Data]?
    )
    case characteristicsDiscovered(
        centralID: UUID,
        peripheralID: UUID,
        serviceUUID: Data,
        characteristicUUIDs: [Data]
    )

    // MARK: - Read/Write
    case readRequested(centralID: UUID, peripheralID: UUID, characteristicUUID: Data)
    case readResponse(centralID: UUID, peripheralID: UUID, characteristicUUID: Data, value: Data?, error: String?)
    case writeRequested(
        centralID: UUID,
        peripheralID: UUID,
        characteristicUUID: Data,
        value: Data,
        type: Int // CBCharacteristicWriteType.rawValue
    )
    case writeResponse(centralID: UUID, peripheralID: UUID, characteristicUUID: Data, error: String?)

    // MARK: - Notifications
    case notifyStateChangeRequested(
        centralID: UUID,
        peripheralID: UUID,
        characteristicUUID: Data,
        enabled: Bool
    )
    case notifyStateChanged(
        centralID: UUID,
        peripheralID: UUID,
        characteristicUUID: Data,
        enabled: Bool
    )
    case notificationSent(peripheralID: UUID, characteristicUUID: Data, value: Data)

    // MARK: - Advertising
    case advertisingStarted(peripheralID: UUID, advertisementData: [String: CodableValue])
    case advertisingStopped(peripheralID: UUID)

    // MARK: - Descriptor Operations
    case descriptorReadRequested(centralID: UUID, peripheralID: UUID, descriptorUUID: Data)
    case descriptorReadResponse(centralID: UUID, peripheralID: UUID, descriptorUUID: Data, value: Data?, error: String?)
    case descriptorWriteRequested(centralID: UUID, peripheralID: UUID, descriptorUUID: Data, value: Data)
    case descriptorWriteResponse(centralID: UUID, peripheralID: UUID, descriptorUUID: Data, error: String?)

    // MARK: - MTU
    case mtuNegotiated(centralID: UUID, peripheralID: UUID, mtu: Int)

    // MARK: - Helper Methods

    /// Get the target process ID for routing
    public var targetID: UUID {
        switch self {
        case .scanStarted(let centralID, _),
             .scanStopped(let centralID),
             .peripheralDiscovered(let centralID, _, _, _),
             .connectionRequested(let centralID, _),
             .connectionEstablished(let centralID, _),
             .connectionFailed(let centralID, _, _),
             .disconnectionRequested(let centralID, _),
             .disconnected(let centralID, _),
             .servicesDiscoveryRequested(let centralID, _, _),
             .servicesDiscovered(let centralID, _, _),
             .characteristicsDiscoveryRequested(let centralID, _, _, _),
             .characteristicsDiscovered(let centralID, _, _, _),
             .readRequested(let centralID, _, _),
             .readResponse(let centralID, _, _, _, _),
             .writeRequested(let centralID, _, _, _, _),
             .writeResponse(let centralID, _, _, _),
             .notifyStateChangeRequested(let centralID, _, _, _),
             .notifyStateChanged(let centralID, _, _, _),
             .descriptorReadRequested(let centralID, _, _),
             .descriptorReadResponse(let centralID, _, _, _, _),
             .descriptorWriteRequested(let centralID, _, _, _),
             .descriptorWriteResponse(let centralID, _, _, _),
             .mtuNegotiated(let centralID, _, _):
            return centralID

        case .notificationSent(let peripheralID, _, _),
             .advertisingStarted(let peripheralID, _),
             .advertisingStopped(let peripheralID):
            return peripheralID
        }
    }
}

/// Codable wrapper for advertisement data values
public enum CodableValue: Codable, Sendable {
    case string(String)
    case data(Data)
    case number(Double)
    case bool(Bool)
    case array([CodableValue])
    case dictionary([String: CodableValue])
    case uuid(Data) // CBUUID as Data

    enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    enum ValueType: String, Codable {
        case string, data, number, bool, array, dictionary, uuid
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)

        switch type {
        case .string:
            let value = try container.decode(String.self, forKey: .value)
            self = .string(value)
        case .data:
            let value = try container.decode(Data.self, forKey: .value)
            self = .data(value)
        case .number:
            let value = try container.decode(Double.self, forKey: .value)
            self = .number(value)
        case .bool:
            let value = try container.decode(Bool.self, forKey: .value)
            self = .bool(value)
        case .array:
            let value = try container.decode([CodableValue].self, forKey: .value)
            self = .array(value)
        case .dictionary:
            let value = try container.decode([String: CodableValue].self, forKey: .value)
            self = .dictionary(value)
        case .uuid:
            let value = try container.decode(Data.self, forKey: .value)
            self = .uuid(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .string(let value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case .data(let value):
            try container.encode(ValueType.data, forKey: .type)
            try container.encode(value, forKey: .value)
        case .number(let value):
            try container.encode(ValueType.number, forKey: .type)
            try container.encode(value, forKey: .value)
        case .bool(let value):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        case .array(let value):
            try container.encode(ValueType.array, forKey: .type)
            try container.encode(value, forKey: .value)
        case .dictionary(let value):
            try container.encode(ValueType.dictionary, forKey: .type)
            try container.encode(value, forKey: .value)
        case .uuid(let value):
            try container.encode(ValueType.uuid, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }

    /// Convert to Any for use with CoreBluetooth APIs
    public var anyValue: Any {
        switch self {
        case .string(let value): return value
        case .data(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .array(let values): return values.map { $0.anyValue }
        case .dictionary(let dict): return dict.mapValues { $0.anyValue }
        case .uuid(let data): return CBUUID(data: data) as Any
        }
    }

    /// Create from Any value
    public static func from(_ value: Any) -> CodableValue? {
        switch value {
        case let string as String:
            return .string(string)
        case let data as Data:
            return .data(data)
        case let number as NSNumber:
            return .number(number.doubleValue)
        case let bool as Bool:
            return .bool(bool)
        case let array as [Any]:
            let codableArray = array.compactMap { CodableValue.from($0) }
            return .array(codableArray)
        case let dict as [String: Any]:
            let codableDict = dict.compactMapValues { CodableValue.from($0) }
            return .dictionary(codableDict)
        case let uuid as CBUUID:
            return .uuid(uuid.data)
        default:
            return nil
        }
    }
}

/// Convert advertisement data dictionary to codable format
public extension Dictionary where Key == String, Value == Any {
    func toCodable() -> [String: CodableValue] {
        return self.compactMapValues { CodableValue.from($0) }
    }
}

/// Convert codable advertisement data back to Any dictionary
public extension Dictionary where Key == String, Value == CodableValue {
    func toAny() -> [String: Any] {
        return self.mapValues { $0.anyValue }
    }
}
