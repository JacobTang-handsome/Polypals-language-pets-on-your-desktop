import Testing
@testable import PolyPals

@Suite("Relationship levels")
struct RelationshipTests {
    @Test("Thresholds are monotonic and mapped exactly")
    func thresholds() {
        #expect(RelationshipLevel.forPoints(0).number == 1)
        #expect(RelationshipLevel.forPoints(9).number == 1)
        #expect(RelationshipLevel.forPoints(10).number == 2)
        #expect(RelationshipLevel.forPoints(70).title == "朋友")
        #expect(RelationshipLevel.forPoints(400).number == 7)
        #expect(RelationshipLevel.forPoints(999).progress(points: 999) == 1)
    }

    @Test("Events have locked points and daily limits")
    func eventRules() {
        #expect(RelationshipEvent.cardCompleted.points == 1)
        #expect(RelationshipEvent.cardCompleted.dailyLimit == 5)
        #expect(RelationshipEvent.memoryConfirmed.points == 3)
        #expect(RelationshipEvent.gift.dailyLimit == 1)
        #expect(RelationshipAwardPolicy.points(for: .gift, sameEventCount: 1, pointsAwardedToday: 0) == 0)
        #expect(RelationshipAwardPolicy.points(for: .memoryConfirmed, sameEventCount: 0, pointsAwardedToday: 17) == 1)
        #expect(RelationshipAwardPolicy.points(for: .chat, sameEventCount: 0, pointsAwardedToday: 18) == 0)
    }

    @Test("关系等级限制记忆引用且不改变内容难度")
    func expressionPolicy() {
        #expect(RelationshipExpressionPolicy.policy(for: 1).maximumMemoryReferences == 0)
        #expect(RelationshipExpressionPolicy.policy(for: 3).maximumMemoryReferences == 1)
        #expect(RelationshipExpressionPolicy.policy(for: 6).maximumMemoryReferences == 2)
        #expect(RelationshipExpressionPolicy.policy(for: 7).instruction.contains("情绪惩罚"))
        #expect(!RelationshipExpressionPolicy.policy(for: 1).allowsFamiliarAddress)
        #expect(RelationshipExpressionPolicy.policy(for: 4).allowsFamiliarAddress)
    }
}
