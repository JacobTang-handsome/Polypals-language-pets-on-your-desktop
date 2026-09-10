import Testing
@testable import PolyPals

@Suite("UI state contracts")
struct PresentationSafetyTests {
    @Test("All user-visible modes have distinct labels")
    func labels() {
        #expect(Set(ProactiveMode.allCases.map(\.title)).count == 3)
        #expect(Set(CorrectionMode.allCases.map(\.title)).count == 3)
        #expect(Set(EnergyState.allCases.map(\.title)).count == 4)
    }

    @Test("聊天 Markdown 不会把粗体标记原样显示")
    func markdownRendering() {
        let rendered = ChatMarkdownRenderer.attributed("¡Exacto! **Tengo muchas ganas**\n\n- carrera\n- aprender")
        let visible = String(rendered.characters)
        #expect(visible.contains("Tengo muchas ganas"))
        #expect(!visible.contains("**"))
        #expect(visible.contains("carrera"))
    }
}
