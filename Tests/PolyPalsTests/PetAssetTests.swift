import ImageIO
import Testing
@testable import PolyPals

@Suite("Pet v2 assets")
struct PetAssetTests {
    @Test("Every built-in pet ships a valid v2 atlas", arguments: PetID.allCases)
    func atlasContract(petID: PetID) throws {
        let manifest = try PetAssetCatalog.manifest(for: petID)
        #expect(manifest.id == petID)
        #expect(manifest.spriteVersionNumber == 2)
        #expect(manifest.spritesheetPath == "\(petID.rawValue)-spritesheet.webp")

        let url = try #require(PetAssetCatalog.spritesheetURL(for: petID))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1_536)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 2_288)
        #expect(PetAssetCatalog.picturePromptURL(for: petID) != nil)
    }

    @Test("Every built-in pet ships a valid behavior atlas", arguments: PetID.allCases)
    func behaviorAtlasContract(petID: PetID) throws {
        let manifest = try #require(PetAssetCatalog.behaviorManifest(for: petID))
        #expect(manifest.version == 1)
        #expect(manifest.petID == petID)
        #expect(manifest.cellWidth == 192)
        #expect(manifest.cellHeight == 208)
        #expect(manifest.columns == 6)
        #expect(manifest.clip(.nap) != nil)
        #expect(manifest.clip(.stretch) != nil)
        #expect(manifest.clip(.celebrate) != nil)
        #expect(manifest.clip(.perchEnter) != nil)
        #expect(manifest.clip(.perchSit) != nil)
        #expect(manifest.clip(.perchExit) != nil)
        for action in PetPersonalityBehavior.actions(for: petID) {
            #expect(manifest.clip(action) != nil)
        }

        let url = try #require(PetAssetCatalog.behaviorSpritesheetURL(for: petID))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let rowCount = (manifest.clips.map(\.row).max() ?? -1) + 1
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == manifest.cellWidth * manifest.columns)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == manifest.cellHeight * rowCount)
    }

    @Test("Missing behavior assets use semantic v2 fallbacks")
    func behaviorFallbacks() {
        #expect(PetBehaviorFallback.state(for: .nap, manifest: nil) == .idle)
        #expect(PetBehaviorFallback.state(for: .stretch, manifest: nil) == .jumping)
        #expect(PetBehaviorFallback.state(for: .perchWalkLeft, manifest: nil) == .runningLeft)
        #expect(PetBehaviorFallback.state(for: .perchWalkRight, manifest: nil) == .runningRight)
        #expect(PetBehaviorFallback.state(for: .ashInviteWing, manifest: nil) == .waving)
    }
}
