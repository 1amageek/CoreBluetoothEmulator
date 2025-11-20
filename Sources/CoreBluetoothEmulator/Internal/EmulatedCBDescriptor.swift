import Foundation
import CoreBluetooth

// MARK: - EmulatedCBDescriptor

/// Emulated CBDescriptor class
public class EmulatedCBDescriptor: NSObject, @unchecked Sendable {
    public let uuid: CBUUID
    public weak var characteristic: EmulatedCBCharacteristic?
    public private(set) var value: Any?

    // Internal properties
    internal let permissions: CBAttributePermissions

    internal init(uuid: CBUUID, value: Any?, permissions: CBAttributePermissions = [.readable, .writeable]) {
        self.uuid = uuid
        self.value = value
        self.permissions = permissions
        super.init()
    }

    internal func setValue(_ value: Any?) {
        self.value = value
    }
}

// MARK: - EmulatedCBMutableDescriptor

/// Emulated CBMutableDescriptor class
public class EmulatedCBMutableDescriptor: EmulatedCBDescriptor, @unchecked Sendable {
    public init(type uuid: CBUUID, value: Any?, permissions: CBAttributePermissions = [.readable, .writeable]) {
        super.init(uuid: uuid, value: value, permissions: permissions)
    }
}
