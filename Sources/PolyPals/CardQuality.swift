import Foundation

struct CardQualityReport: Sendable, Equatable {
    let score: Int
    let issues: [String]
}

struct CardQualityEvaluator: Sendable {
    func evaluate(_ card: GeneratedCard, pet: PetDefinition, existingFingerprints: Set<String> = []) -> CardQualityReport {
        evaluate(
            card,
            pet: pet,
            languageProfile: LanguageProfile(targetLanguage: pet.targetLanguage, currentLevel: pet.defaultLevel,
                                             chineseHelpRatio: max(0, 1 - pet.languageRatio)),
            existingFingerprints: existingFingerprints
        )
    }

    func evaluate(_ card: GeneratedCard, pet: PetDefinition, languageProfile: LanguageProfile,
                  existingFingerprints: Set<String> = []) -> CardQualityReport {
        var score = 0
        var issues: [String] = []
        guard card.isValid else { return .init(score: 0, issues: ["卡片时长或正文无效"]) }
        score += 20
        let expectedLanguages: Set<String> = switch pet.id {
        case .sol: ["es", "es-es", "spanish", "西班牙语"]
        case .mousse: ["fr", "fr-fr", "french", "法语"]
        case .ash: ["en", "en-us", "english", "英语"]
        }
        if card.petID == pet.id, expectedLanguages.contains(card.language.lowercased()) { score += 15 } else { issues.append("语言与宠物不匹配") }
        if card.supports(languageProfile.currentLevel) { score += 20 } else { issues.append("难度不在用户允许范围") }
        if (30...120).contains(card.estimatedSeconds) { score += 10 }
        if !existingFingerprints.contains(CardFingerprint.make(card)) { score += 15 } else { issues.append("内容已重复") }
        if card.type == .culture {
            if card.sourceTitle?.isEmpty == false, card.sourceURL?.isEmpty == false { score += 10 } else { issues.append("文化卡缺少来源") }
        } else { score += 10 }
        if !card.targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 10 }
        let policy = LanguagePolicy.policy(for: languageProfile.currentLevel)
        let longestSentence = card.targetText
            .split(whereSeparator: { ".!?\n。！？".contains($0) })
            .map { $0.split(whereSeparator: \.isWhitespace).count }
            .max() ?? 0
        if [.a1, .a2].contains(languageProfile.currentLevel), longestSentence > policy.suggestedSentenceWords.upperBound + 4 {
            issues.append("低等级卡片句子明显过长")
            score -= 35
        }
        return .init(score: min(100, score), issues: issues)
    }
}
