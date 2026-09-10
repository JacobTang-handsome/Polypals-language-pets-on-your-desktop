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
}
