import Foundation
import CoreBluetooth

// MARK: - EmulatedCBCentral

/// Emulated CBCentral class (represents a central connected to a peripheral)
public class EmulatedCBCentral: NSObject, @unchecked Sendable {
    public let identifier: UUID
    public let maximumUpdateValueLength: Int

    internal init(identifier: UUID, maximumUpdateValueLength: Int = 512) {
        self.identifier = identifier
        self.maximumUpdateValueLength = maximumUpdateValueLength
        super.init()
    }
}

// MARK: - EmulatedCBATTRequest

/// Emulated CBATTRequest class
public class EmulatedCBATTRequest: NSObject, @unchecked Sendable {
    public let central: EmulatedCBCentral
    public let characteristic: EmulatedCBCharacteristic
    public let offset: Int
    public var value: Data?

    internal init(
        central: EmulatedCBCentral,
        characteristic: EmulatedCBCharacteristic,
        offset: Int = 0
    ) {
        self.central = central
        self.characteristic = characteristic
        self.offset = offset
        super.init()
    }
}
