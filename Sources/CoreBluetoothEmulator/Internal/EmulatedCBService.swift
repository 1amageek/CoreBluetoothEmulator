import Foundation
import CoreBluetooth

// MARK: - EmulatedCBService

/// Emulated CBService class
public class EmulatedCBService: NSObject, @unchecked Sendable {
    public let uuid: CBUUID
    public let isPrimary: Bool
    public weak var peripheral: EmulatedCBPeripheral?
    public private(set) var includedServices: [EmulatedCBService]?
    public private(set) var characteristics: [EmulatedCBCharacteristic]?

    internal init(uuid: CBUUID, isPrimary: Bool) {
        self.uuid = uuid
        self.isPrimary = isPrimary
        super.init()
    }

    internal func setCharacteristics(_ characteristics: [EmulatedCBCharacteristic]) {
        self.characteristics = characteristics
        for characteristic in characteristics {
            characteristic.service = self
        }
    }

    internal func setIncludedServices(_ services: [EmulatedCBService]) {
        self.includedServices = services
    }
}

// MARK: - EmulatedCBMutableService

/// Emulated CBMutableService class
public class EmulatedCBMutableService: EmulatedCBService, @unchecked Sendable {
    public override var characteristics: [EmulatedCBCharacteristic]? {
        get { super.characteristics }
        set {
            if let newValue = newValue {
                setCharacteristics(newValue)
            }
        }
    }

    public override var includedServices: [EmulatedCBService]? {
        get { super.includedServices }
        set {
            if let newValue = newValue {
                setIncludedServices(newValue)
            }
        }
    }

    public init(type uuid: CBUUID, primary: Bool) {
        super.init(uuid: uuid, isPrimary: primary)
    }
}
