import Foundation
import CoreBluetooth

/// Emulated CBL2CAPChannel for L2CAP stream-based data transfer
@available(iOS 11.0, macOS 10.13, tvOS 11.0, watchOS 4.0, *)
public class EmulatedCBL2CAPChannel: NSObject, @unchecked Sendable {

    /// The peer device for this channel
    public private(set) var peer: EmulatedCBPeer

    /// Input stream for receiving data
    public private(set) var inputStream: InputStream?

    /// Output stream for sending data
    public private(set) var outputStream: OutputStream?

    /// The PSM (Protocol/Service Multiplexer) for this channel
    public private(set) var psm: CBL2CAPPSM

    internal let identifier: UUID
    internal var isOpen: Bool = false
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?

    internal init(peer: EmulatedCBPeer, psm: CBL2CAPPSM) {
        self.peer = peer
        self.psm = psm
        self.identifier = UUID()
        super.init()

        // Create pipe for bidirectional communication
        setupStreams()
    }

    private func setupStreams() {
        // Create pipes for input and output
        inputPipe = Pipe()
        outputPipe = Pipe()

        // Create streams from pipes
        if let inputPipe = inputPipe, let outputPipe = outputPipe {
            // Use CFStream for proper stream creation
            var readStream: Unmanaged<CFReadStream>?
            var writeStream: Unmanaged<CFWriteStream>?

            CFStreamCreatePairWithSocket(
                kCFAllocatorDefault,
                0, // dummy socket
                &readStream,
                &writeStream
            )

            if let read = readStream?.takeRetainedValue(),
               let write = writeStream?.takeRetainedValue() {
                inputStream = read as InputStream
                outputStream = write as OutputStream
            }
        }
    }

    internal func open() {
        guard !isOpen else { return }
        isOpen = true

        // Open streams
        inputStream?.open()
        outputStream?.open()
    }

    internal func close() {
        guard isOpen else { return }
        isOpen = false

        // Close streams
        inputStream?.close()
        outputStream?.close()
    }

    /// Send data through the output stream
    internal func send(data: Data) -> Int {
        guard isOpen, let outputStream = outputStream else { return -1 }

        return data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return outputStream.write(
                baseAddress.assumingMemoryBound(to: UInt8.self),
                maxLength: buffer.count
            )
        }
    }

    /// Receive data from the input stream
    internal func receive(maxLength: Int) -> Data? {
        guard isOpen, let inputStream = inputStream else { return nil }

        var buffer = [UInt8](repeating: 0, count: maxLength)
        let bytesRead = inputStream.read(&buffer, maxLength: maxLength)

        guard bytesRead > 0 else { return nil }
        return Data(buffer.prefix(bytesRead))
    }
}

/// Protocol for L2CAP peer (can be Central or Peripheral)
public protocol EmulatedCBPeer: AnyObject {
    var identifier: UUID { get }
}

/// Extend EmulatedCBPeripheral to conform to EmulatedCBPeer
extension EmulatedCBPeripheral: EmulatedCBPeer {}

/// Extend EmulatedCBCentral to conform to EmulatedCBPeer
extension EmulatedCBCentral: EmulatedCBPeer {}
