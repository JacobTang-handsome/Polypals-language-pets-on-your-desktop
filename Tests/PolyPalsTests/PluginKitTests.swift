import Foundation
import Testing
import PolyPalsPluginKit

@Suite("Declarative plugin packs")
struct PluginKitTests {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test("Both repository examples pass the shared validator")
    func examples() {
        let validator = PluginPackValidator()
        let content = validator.validate(directory: root.appendingPathComponent("Examples/ContentPack/ExampleContent.polypals-pack"))
        let pet = validator.validate(directory: root.appendingPathComponent("Examples/PetPack/ExamplePet.polypals-pack"))
        #expect(content.isValid, Comment(rawValue: content.issues.map(\.message).joined(separator: "; ")))
        #expect(pet.isValid, Comment(rawValue: pet.issues.map(\.message).joined(separator: "; ")))
    }

    @Test("Unsafe paths and executable payloads are rejected")
    func hostileManifest() throws {
        let pack = FileManager.default.temporaryDirectory.appendingPathComponent("Hostile-\(UUID().uuidString).polypals-pack")
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pack) }
        let manifest = PluginManifest(formatVersion: 1, id: "org.example.hostile", kind: .content, name: "Hostile", version: "1.0.0", minimumAppVersion: "0.4.0", author: "Test", license: "CC0-1.0", languages: ["en"], levels: ["A1"], capabilities: ["cards"], assetDigests: [:])
        try JSONEncoder().encode(manifest).write(to: pack.appendingPathComponent("manifest.json"))
        try Data("echo bad".utf8).write(to: pack.appendingPathComponent("run.sh"))
        let report = PluginPackValidator().validate(directory: pack)
        #expect(!report.isValid)
        #expect(report.issues.contains { $0.code == "file.executable" })
    }
}
