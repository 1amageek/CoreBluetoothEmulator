import Foundation
import CoreBluetooth

// MARK: - Public API

// All emulated classes are directly exported
// No type aliases - users will use Emulated* classes directly

// MARK: - Emulator Configuration

/// Emulator configuration namespace
public enum Emulator {
    /// Configure the emulator behavior
    public static func configure(_ configuration: EmulatorConfiguration) {
        Task {
            await EmulatorBus.shared.configure(configuration)
        }
    }

    /// Get current configuration
    public static func getConfiguration() async -> EmulatorConfiguration {
        await EmulatorBus.shared.getConfiguration()
    }

    /// Reset the emulator (disconnect all devices, clear state)
    public static func reset() {
        Task {
            await EmulatorBus.shared.reset()
        }
    }

    /// Check if running in emulator mode
    public static var isEmulated: Bool {
        true
    }
}
