import CryptoKit
import Foundation
import ImageIO

public enum PluginKind: String, Codable, Sendable, CaseIterable { case content, pet }

public struct PluginManifest: Codable, Sendable, Equatable {
    public let formatVersion: Int
    public let id: String
    public let kind: PluginKind
    public let name: String
    public let version: String
    public let minimumAppVersion: String
    public let author: String
    public let license: String
    public let languages: [String]
    public let levels: [String]
    public let capabilities: [String]
    public let assetDigests: [String: String]

    public init(formatVersion: Int, id: String, kind: PluginKind, name: String, version: String,
                minimumAppVersion: String, author: String, license: String, languages: [String],
                levels: [String], capabilities: [String], assetDigests: [String: String]) {
        self.formatVersion = formatVersion; self.id = id; self.kind = kind; self.name = name
        self.version = version; self.minimumAppVersion = minimumAppVersion; self.author = author
        self.license = license; self.languages = languages; self.levels = levels
        self.capabilities = capabilities; self.assetDigests = assetDigests
    }
}

public struct PluginValidationIssue: Codable, Sendable, Equatable {
    public enum Severity: String, Codable, Sendable { case warning, error }
    public let severity: Severity
    public let code: String
    public let message: String
    public let path: String?
}

public struct PluginValidationReport: Codable, Sendable, Equatable {
    public let manifest: PluginManifest?
    public let issues: [PluginValidationIssue]
    public var isValid: Bool { !issues.contains { $0.severity == .error } }
}

public struct PluginValidationLimits: Sendable {
    public var maximumFiles = 1_000
    public var maximumTotalBytes: Int64 = 50 * 1_024 * 1_024
    public var maximumFileBytes: Int64 = 10 * 1_024 * 1_024
    public var maximumJSONBytes: Int64 = 2 * 1_024 * 1_024
    public var maximumCards = 500
    public init() {}
}

public struct PluginPackValidator: Sendable {
    public let limits: PluginValidationLimits
    public let appVersion: String

    public init(appVersion: String = "0.4.0", limits: PluginValidationLimits = .init()) {
        self.appVersion = appVersion; self.limits = limits
    }

    public func validate(directory: URL) -> PluginValidationReport {
        var issues: [PluginValidationIssue] = []
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard directory.pathExtension == "polypals-pack", fm.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .init(manifest: nil, issues: [error("pack.notDirectory", "Pack must be a .polypals-pack directory.")])
        }
        guard let root = try? directory.resolvingSymlinksInPath().resourceValues(forKeys: [.canonicalPathKey]).canonicalPath else {
            return .init(manifest: nil, issues: [error("pack.unreadable", "Pack directory cannot be resolved.")])
        }
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL), manifestData.count <= limits.maximumJSONBytes else {
            return .init(manifest: nil, issues: [error("manifest.missing", "manifest.json is missing or too large.", "manifest.json")])
        }
        let manifest: PluginManifest
        do { manifest = try JSONDecoder().decode(PluginManifest.self, from: manifestData) }
        catch { return .init(manifest: nil, issues: [self.error("manifest.invalid", "manifest.json is invalid.", "manifest.json")]) }

        if manifest.formatVersion != 1 { issues.append(error("manifest.formatVersion", "Unsupported formatVersion.", "manifest.json")) }
        if !Self.validReverseDomain(manifest.id) { issues.append(error("manifest.id", "id must be a stable reverse-domain identifier.", "manifest.json")) }
        if !Self.validVersion(manifest.version) || !Self.validVersion(manifest.minimumAppVersion) { issues.append(error("manifest.version", "Versions must use semantic versioning.", "manifest.json")) }
        if Self.compareVersions(appVersion, manifest.minimumAppVersion) < 0 { issues.append(error("manifest.appVersion", "Pack requires a newer PolyPals version.", "manifest.json")) }
        if manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manifest.author.isEmpty || manifest.license.isEmpty || manifest.languages.isEmpty || manifest.levels.isEmpty || manifest.capabilities.isEmpty {
            issues.append(error("manifest.required", "Manifest required fields must not be empty.", "manifest.json"))
        }
        if manifest.kind == .content && !manifest.capabilities.contains("cards") { issues.append(error("manifest.capability", "Content packs must declare the cards capability.", "manifest.json")) }
        if manifest.kind == .pet && (!manifest.capabilities.contains("pet") || !manifest.capabilities.contains("sprite-v2")) { issues.append(error("manifest.capability", "Pet packs must declare pet and sprite-v2 capabilities.", "manifest.json")) }
        let allowedLevels = Set(["A1", "A2", "B1", "B2", "C1", "C2"])
        if !Set(manifest.levels).isSubset(of: allowedLevels) { issues.append(error("manifest.levels", "levels contains an unknown CEFR level.", "manifest.json")) }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .canonicalPathKey]
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
            return .init(manifest: manifest, issues: issues + [error("pack.unreadable", "Pack contents cannot be read.")])
        }
        var files: [(url: URL, relative: String, size: Int64)] = []
        var caseFolded = Set<String>()
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let relative = String(url.path.dropFirst(directory.path.count + 1))
            guard Self.safeRelativePath(relative) else { issues.append(error("path.traversal", "Unsafe path.", relative)); continue }
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true { issues.append(error("path.symlink", "Symbolic links are not allowed.", relative)); continue }
            if let canonical = values?.canonicalPath, canonical != root && !canonical.hasPrefix(root + "/") { issues.append(error("path.escape", "Path escapes the pack directory.", relative)); continue }
            guard values?.isRegularFile == true else { continue }
            let folded = relative.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            if !caseFolded.insert(folded).inserted { issues.append(error("path.caseConflict", "File names conflict by case.", relative)) }
            let size = Int64(values?.fileSize ?? 0); total += size
            if size > limits.maximumFileBytes { issues.append(error("file.tooLarge", "File exceeds the per-file limit.", relative)) }
            if url.pathExtension.lowercased() == "json", size > limits.maximumJSONBytes { issues.append(error("json.tooLarge", "JSON file exceeds the limit.", relative)) }
            if Self.forbiddenExtensions.contains(url.pathExtension.lowercased()) { issues.append(error("file.executable", "Executable or script payloads are not allowed.", relative)) }
            let ext = url.pathExtension.lowercased()
            if !ext.isEmpty && !Self.allowedExtensions.contains(ext) { issues.append(error("file.unknown", "Unknown binary or file type is not allowed.", relative)) }
            if Self.imageExtensions.contains(ext), let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = image[kCGImagePropertyPixelWidth] as? Int, let height = image[kCGImagePropertyPixelHeight] as? Int,
               (width > 8192 || height > 8192) { issues.append(error("image.dimensions", "Image dimensions exceed 8192×8192.", relative)) }
            files.append((url, relative, size))
        }
        if files.count > limits.maximumFiles { issues.append(error("pack.tooManyFiles", "Pack contains too many files.")) }
        if total > limits.maximumTotalBytes { issues.append(error("pack.tooLarge", "Unpacked pack exceeds the size limit.")) }

        for file in files where file.relative != "manifest.json" {
            guard let expected = manifest.assetDigests[file.relative]?.lowercased() else { issues.append(error("digest.missing", "Every payload file needs a SHA-256 digest.", file.relative)); continue }
            guard let data = try? Data(contentsOf: file.url) else { issues.append(error("file.unreadable", "File cannot be read.", file.relative)); continue }
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if expected != actual { issues.append(error("digest.mismatch", "SHA-256 digest does not match.", file.relative)) }
        }
        let extraDigests = Set(manifest.assetDigests.keys).subtracting(files.map(\.relative))
        for path in extraDigests { issues.append(error("digest.missingFile", "Digest references a missing file.", path)) }

        switch manifest.kind {
        case .content: validateContent(in: directory, issues: &issues)
        case .pet: validatePet(in: directory, issues: &issues)
        }
        return .init(manifest: manifest, issues: issues)
    }

    private func validateContent(in directory: URL, issues: inout [PluginValidationIssue]) {
        let url = directory.appendingPathComponent("content/cards.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let cards = object as? [[String: Any]] else { issues.append(error("content.cards", "content/cards.json must contain a card array.", "content/cards.json")); return }
        if cards.isEmpty || cards.count > limits.maximumCards { issues.append(error("content.cardCount", "Card count must be between 1 and \(limits.maximumCards).", "content/cards.json")) }
        for (index, card) in cards.enumerated() {
            let path = "content/cards.json#\(index)"
            let required = ["petId", "type", "language", "minimumLevel", "recommendedLevel", "maximumLevel", "estimatedSeconds", "targetText", "prompt", "memoryKey"]
            if required.contains(where: { card[$0] == nil }) { issues.append(error("content.cardRequired", "Card is missing required fields.", path)) }
            if let seconds = card["estimatedSeconds"] as? Int, !(30...120).contains(seconds) { issues.append(error("content.duration", "Card duration must be 30...120 seconds.", path)) }
            let order = ["a1", "a2", "b1", "b2", "c1", "c2"]
            if let low = card["minimumLevel"] as? String, let recommended = card["recommendedLevel"] as? String, let high = card["maximumLevel"] as? String,
               let li = order.firstIndex(of: low), let ri = order.firstIndex(of: recommended), let hi = order.firstIndex(of: high), !(li <= ri && ri <= hi) {
                issues.append(error("content.levelRange", "CEFR range must contain the recommended level.", path))
            }
            if card["type"] as? String == "culture", ((card["sourceTitle"] as? String)?.isEmpty != false || (card["sourceURL"] as? String)?.isEmpty != false) { issues.append(error("content.cultureSource", "Culture cards require a source.", path)) }
        }
    }

    private func validatePet(in directory: URL, issues: inout [PluginValidationIssue]) {
        let url = directory.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { issues.append(error("pet.manifest", "pet.json is missing or invalid.", "pet.json")); return }
        let reserved = Set(["sol", "mousse", "ash"])
        if let id = object["petId"] as? String, reserved.contains(id.lowercased()) { issues.append(error("pet.reservedId", "Built-in pet IDs cannot be replaced.", "pet.json")) }
        guard object["spriteVersionNumber"] as? Int == 2 else { issues.append(error("pet.spriteVersion", "spriteVersionNumber must be 2.", "pet.json")); return }
        if object["frameWidth"] as? Int != 192 || object["frameHeight"] as? Int != 208 || object["columns"] as? Int != 8 || object["rows"] as? Int != 11 {
            issues.append(error("pet.grid", "Sprite v2 grid must be 192×208, 8 columns, and 11 rows.", "pet.json"))
        }
        if (object["animationRows"] as? [String])?.count != 11 { issues.append(error("pet.animationRows", "Pet manifest must declare all 11 animation rows.", "pet.json")) }
        let spritePath = object["spritesheet"] as? String ?? "assets/spritesheet.png"
        guard Self.safeRelativePath(spritePath) else { issues.append(error("pet.spritePath", "Sprite path is unsafe.", "pet.json")); return }
        let spriteURL = directory.appendingPathComponent(spritePath)
        guard let source = CGImageSourceCreateWithURL(spriteURL as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else { issues.append(error("pet.sprite", "Spritesheet cannot be decoded.", spritePath)); return }
        if width != 1536 || height != 2288 { issues.append(error("pet.spriteSize", "Sprite v2 must be 1536×2288 (8×11 of 192×208).", spritePath)) }
        if properties[kCGImagePropertyHasAlpha] as? Bool != true { issues.append(error("pet.alpha", "Spritesheet must have transparency.", spritePath)) }
        if object["lookDirections"] as? Int != 16 { issues.append(error("pet.directions", "Pet manifest must declare 16 look directions.", "pet.json")) }
    }

    private func error(_ code: String, _ message: String, _ path: String? = nil) -> PluginValidationIssue { .init(severity: .error, code: code, message: message, path: path) }
    private static let forbiddenExtensions = Set(["sh", "command", "zsh", "bash", "py", "rb", "pl", "js", "dylib", "so", "app", "pkg", "exe"])
    private static let allowedExtensions = Set(["json", "md", "txt", "png", "webp", "jpg", "jpeg", "gif", "heic", "svg", "strings", "xcstrings", "wav", "mp3", "m4a", "ogg"])
    private static let imageExtensions = Set(["png", "webp", "jpg", "jpeg", "gif", "heic"])
    private static func safeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.hasPrefix("~") && !path.split(separator: "/").contains("..") && !path.contains("\\") && !path.contains("\0")
    }
    private static func validReverseDomain(_ value: String) -> Bool {
        let parts = value.split(separator: "."); return parts.count >= 3 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }
    }
    private static func validVersion(_ value: String) -> Bool {
        let core = value.split(separator: "+", maxSplits: 1)[0].split(separator: "-", maxSplits: 1)[0]
        let parts = core.split(separator: "."); return parts.count == 3 && parts.allSatisfy { Int($0) != nil }
    }
    private static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let l = lhs.split(separator: ".").prefix(3).map { Int($0.split(separator: "-")[0]) ?? 0 }
        let r = rhs.split(separator: ".").prefix(3).map { Int($0.split(separator: "-")[0]) ?? 0 }
        for index in 0..<3 { let lv = index < l.count ? l[index] : 0; let rv = index < r.count ? r[index] : 0; if lv != rv { return lv < rv ? -1 : 1 } }
        return 0
    }
}
