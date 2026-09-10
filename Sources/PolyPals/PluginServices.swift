import Foundation
import PolyPalsPluginKit

struct InstalledPlugin: Identifiable, Sendable {
    let manifest: PluginManifest
    let directory: URL
    let enabled: Bool
    let issues: [PluginValidationIssue]
    var id: String { manifest.id }
}

struct PluginPackService {
    let root: URL
    private let validator = PluginPackValidator(appVersion: "0.4.0")

    init(fileManager: FileManager = .default) throws {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        root = support.appendingPathComponent("PolyPals/Plugins", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func preview(_ source: URL) -> PluginValidationReport { validator.validate(directory: source) }

    func install(_ source: URL, fileManager: FileManager = .default) throws -> InstalledPlugin {
        let report = validator.validate(directory: source)
        guard report.isValid, let manifest = report.manifest else {
            throw NSError(domain: "PolyPalsPlugin", code: 1, userInfo: [NSLocalizedDescriptionKey: report.issues.map(\.message).joined(separator: "\n")])
        }
        let staging = root.appendingPathComponent(".install-\(UUID().uuidString).polypals-pack", isDirectory: true)
        let destination = root.appendingPathComponent("\(manifest.id).polypals-pack", isDirectory: true)
        let backup = root.appendingPathComponent(".backup-\(UUID().uuidString).polypals-pack", isDirectory: true)
        do {
            try fileManager.copyItem(at: source, to: staging)
            guard validator.validate(directory: staging).isValid else { throw CocoaError(.fileReadCorruptFile) }
            if fileManager.fileExists(atPath: destination.path) { try fileManager.moveItem(at: destination, to: backup) }
            do { try fileManager.moveItem(at: staging, to: destination) }
            catch {
                if fileManager.fileExists(atPath: backup.path) { try? fileManager.moveItem(at: backup, to: destination) }
                throw error
            }
            if fileManager.fileExists(atPath: backup.path) { try fileManager.removeItem(at: backup) }
            setEnabled(true, id: manifest.id)
            return .init(manifest: manifest, directory: destination, enabled: true, issues: [])
        } catch {
            if fileManager.fileExists(atPath: staging.path) { try? fileManager.removeItem(at: staging) }
            throw error
        }
    }

    func installed(fileManager: FileManager = .default) -> [InstalledPlugin] {
        let urls = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url in
            let report = validator.validate(directory: url)
            guard let manifest = report.manifest else { return nil }
            return InstalledPlugin(manifest: manifest, directory: url, enabled: report.isValid && isEnabled(manifest.id), issues: report.issues)
        }.sorted { $0.manifest.name < $1.manifest.name }
    }

    func setEnabled(_ enabled: Bool, id: String) {
        UserDefaults.standard.set(enabled, forKey: "plugin.enabled.\(id)")
    }

    func isEnabled(_ id: String) -> Bool {
        UserDefaults.standard.object(forKey: "plugin.enabled.\(id)") as? Bool ?? true
    }

    func delete(_ plugin: InstalledPlugin, fileManager: FileManager = .default) throws {
        let canonicalRoot = root.resolvingSymlinksInPath().path + "/"
        let canonicalTarget = plugin.directory.resolvingSymlinksInPath().path
        guard canonicalTarget.hasPrefix(canonicalRoot) else { throw CocoaError(.fileWriteNoPermission) }
        try fileManager.removeItem(at: plugin.directory)
        UserDefaults.standard.removeObject(forKey: "plugin.enabled.\(plugin.id)")
    }

    func contentDocumentData(for plugin: InstalledPlugin) throws -> Data? {
        guard plugin.manifest.kind == .content else { return nil }
        let cardsData = try Data(contentsOf: plugin.directory.appendingPathComponent("content/cards.json"))
        let cards = try JSONDecoder().decode([GeneratedCard].self, from: cardsData)
        let document = ContentPackDocument(
            schemaVersion: 1,
            pack: ContentPackManifest(id: plugin.id, title: plugin.manifest.name, version: plugin.manifest.version,
                                      author: plugin.manifest.author, language: plugin.manifest.languages.first ?? "",
                                      license: plugin.manifest.license),
            cards: cards
        )
        return try JSONEncoder().encode(document)
    }
}
