import Foundation
import CoreBluetooth

// MARK: - EmulatedCBCharacteristic

/// Emulated CBCharacteristic class
public class EmulatedCBCharacteristic: NSObject, @unchecked Sendable {
    public let uuid: CBUUID
    public weak var service: EmulatedCBService?
    public let properties: CBCharacteristicProperties
    public private(set) var value: Data?
    public private(set) var descriptors: [EmulatedCBDescriptor]?
    public private(set) var isNotifying: Bool = false

    // Internal properties
    internal let permissions: CBAttributePermissions

    internal init(
        uuid: CBUUID,
        properties: CBCharacteristicProperties,
        value: Data?,
        permissions: CBAttributePermissions
    ) {
        self.uuid = uuid
        self.properties = properties
        self.value = value
        self.permissions = permissions
        super.init()
    }

    internal func setValue(_ value: Data?) {
        self.value = value
    }

    internal func setNotifying(_ isNotifying: Bool) {
        self.isNotifying = isNotifying
    }

    internal func setDescriptors(_ descriptors: [EmulatedCBDescriptor]) {
        self.descriptors = descriptors
        for descriptor in descriptors {
            descriptor.characteristic = self
        }
    }
}

// MARK: - EmulatedCBMutableCharacteristic

/// Emulated CBMutableCharacteristic class
public class EmulatedCBMutableCharacteristic: EmulatedCBCharacteristic, @unchecked Sendable {
    public private(set) var subscribedCentrals: [EmulatedCBCentral]?

    public init(
        type uuid: CBUUID,
        properties: CBCharacteristicProperties,
        value: Data?,
        permissions: CBAttributePermissions
    ) {
        super.init(uuid: uuid, properties: properties, value: value, permissions: permissions)
    }

    public override var descriptors: [EmulatedCBDescriptor]? {
        get { super.descriptors }
        set {
            if let newValue = newValue {
                setDescriptors(newValue)
            }
        }
    }

    internal func addSubscribedCentral(_ central: EmulatedCBCentral) {
        if subscribedCentrals == nil {
            subscribedCentrals = []
        }
        if !subscribedCentrals!.contains(where: { $0.identifier == central.identifier }) {
            subscribedCentrals!.append(central)
        }
    }

    internal func removeSubscribedCentral(_ central: EmulatedCBCentral) {
        subscribedCentrals?.removeAll { $0.identifier == central.identifier }
    }
}
