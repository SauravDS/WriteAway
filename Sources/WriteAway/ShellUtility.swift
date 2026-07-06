import Foundation

/// Result of a command execution.
struct CommandResult {
    let status: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { status == 0 }
}

/// Shared helper for launching subprocesses.
/// Uses async pipe reads to avoid deadlocks when the child produces
/// more output than the kernel pipe buffer (~64 KB).
enum Shell {

    /// Run a command synchronously and capture its output.
    @discardableResult
    static func run(_ executablePath: String, _ arguments: [String] = []) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Read pipe data asynchronously to prevent deadlocks.
        // If the child fills the pipe buffer before we read, both sides block.
        var outData = Data()
        var errData = Data()

        let outSource = DispatchSource.makeReadSource(
            fileDescriptor: outPipe.fileHandleForReading.fileDescriptor,
            queue: .global(qos: .userInitiated)
        )
        let errSource = DispatchSource.makeReadSource(
            fileDescriptor: errPipe.fileHandleForReading.fileDescriptor,
            queue: .global(qos: .userInitiated)
        )

        let outLock = NSLock()
        let errLock = NSLock()

        outSource.setEventHandler {
            let chunk = outPipe.fileHandleForReading.availableData
            outLock.lock()
            outData.append(chunk)
            outLock.unlock()
        }
        errSource.setEventHandler {
            let chunk = errPipe.fileHandleForReading.availableData
            errLock.lock()
            errData.append(chunk)
            errLock.unlock()
        }

        outSource.resume()
        errSource.resume()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            outSource.cancel()
            errSource.cancel()
            return CommandResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        // Drain anything left in the pipes after the process exits.
        outSource.cancel()
        errSource.cancel()

        outLock.lock()
        let remainingOut = outPipe.fileHandleForReading.readDataToEndOfFile()
        outData.append(remainingOut)
        outLock.unlock()

        errLock.lock()
        let remainingErr = errPipe.fileHandleForReading.readDataToEndOfFile()
        errData.append(remainingErr)
        errLock.unlock()

        return CommandResult(
            status: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Run a command and return its stdout as raw `Data`, or nil on failure.
    static func runForData(_ executablePath: String, _ arguments: [String] = []) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe() // discard

        var outData = Data()
        let outSource = DispatchSource.makeReadSource(
            fileDescriptor: outPipe.fileHandleForReading.fileDescriptor,
            queue: .global(qos: .userInitiated)
        )
        let lock = NSLock()

        outSource.setEventHandler {
            let chunk = outPipe.fileHandleForReading.availableData
            lock.lock()
            outData.append(chunk)
            lock.unlock()
        }
        outSource.resume()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            outSource.cancel()
            return nil
        }

        outSource.cancel()

        lock.lock()
        let remaining = outPipe.fileHandleForReading.readDataToEndOfFile()
        outData.append(remaining)
        lock.unlock()

        return process.terminationStatus == 0 ? outData : nil
    }

    /// Properly escapes a string for embedding in a single-quoted shell argument.
    /// `foo'bar` → `'foo'\''bar'`
    static func shellEscape(_ string: String) -> String {
        let escaped = string.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
