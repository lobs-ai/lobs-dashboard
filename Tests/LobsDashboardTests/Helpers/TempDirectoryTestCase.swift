import XCTest
import Foundation

/// Base test case class that provides a temporary directory for each test.
/// The directory is automatically created before each test and cleaned up after.
class TempDirectoryTestCase: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        super.tearDown()
    }

    /// Write JSON data to a file in the temp directory
    func writeJSON<T: Encodable>(_ value: T, at path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(value)

        // Convert to Python-compatible format (": " instead of " : ")
        if var jsonString = String(data: data, encoding: .utf8) {
            jsonString = jsonString.replacingOccurrences(of: " : ", with: ": ")
            data = Data(jsonString.utf8)
        }

        let fileURL = tempDir.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
    }
}
