import Foundation

struct PetAssetManifest: Codable, Sendable, Equatable {
    let id: PetID
    let displayName: String
    let description: String
    let spriteVersionNumber: Int
    let spritesheetPath: String
}

struct PetBehaviorClipManifest: Codable, Sendable, Equatable {
    let id: PetBehaviorAnimation
    let row: Int
    let frameCount: Int
    let secondsPerFrame: Double
    let loops: Bool
    let interruptible: Bool
    let fallback: AnimationState
    let anchorX: Double
    let anchorY: Double
}

struct PetBehaviorAssetManifest: Codable, Sendable, Equatable {
    let version: Int
    let petID: PetID
    let cellWidth: Int
    let cellHeight: Int
    let columns: Int
    let spritesheetPath: String
    let clips: [PetBehaviorClipManifest]

    func clip(_ id: PetBehaviorAnimation) -> PetBehaviorClipManifest? {
        clips.first(where: { $0.id == id })
    }
}

enum PetAssetCatalog {
    static func spritesheetURL(for petID: PetID) -> URL? {
        Bundle.module.url(forResource: "\(petID.rawValue)-spritesheet", withExtension: "webp")
    }

    static func picturePromptURL(for petID: PetID) -> URL? {
        Bundle.module.url(forResource: "picture-\(petID.rawValue)", withExtension: "png")
    }

    static func manifest(for petID: PetID) throws -> PetAssetManifest {
        guard let url = Bundle.module.url(forResource: "\(petID.rawValue)-pet", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(PetAssetManifest.self, from: Data(contentsOf: url))
    }

    static func behaviorSpritesheetURL(for petID: PetID) -> URL? {
        Bundle.module.url(forResource: "\(petID.rawValue)-behavior-spritesheet", withExtension: "webp")
    }

    static func behaviorManifest(for petID: PetID) -> PetBehaviorAssetManifest? {
        guard let url = Bundle.module.url(forResource: "\(petID.rawValue)-behavior", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PetBehaviorAssetManifest.self, from: data)
    }
}

enum PetBehaviorFallback {
    static func state(for behavior: PetBehaviorAnimation, manifest: PetBehaviorAssetManifest?) -> AnimationState {
        if let fallback = manifest?.clip(behavior)?.fallback { return fallback }
        switch behavior {
        case .celebrate, .perchEnter, .perchExit, .stretch: return .jumping
        case .perchWalkLeft: return .runningLeft
        case .perchWalkRight: return .runningRight
        case .ashInviteWing: return .waving
        case .solPouncePrep, .mousseGroom, .ashHeadTilt: return .review
        case .solEarTwitch, .mousseProud: return .waiting
        case .nap, .perchSit, .solTailChase, .solPerchTailWag, .mousseElegantSit, .ashSlowSquint: return .idle
        }
    }
}
